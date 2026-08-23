# What loudness standard should an Export normalize to, and how do apps that produce audio files actually do it?

Research for [issue #23](https://github.com/SamWongML/macos-audio-recording/issues/23), part of the [map](https://github.com/SamWongML/macos-audio-recording/issues/1). Constraints carried over: macOS 27.0 only, no back-deployment; local use only, no notarization/sandbox/App Store; official Apple components preferred, a custom control needs a stated reason. Per [ADR-0003](../adr/0003-immutable-lossless-caf-master.md), a Recording is an immutable, lossless, native-Float32 CAF master (~1.4 GB/hour at 48 kHz stereo) that is written once and never modified; Trim is two points stored against the Recording; Export always reads the trimmed frame range from the master and re-encodes it to a chosen Quality Preset — it is never a byte-copy. The tap hands the app post-mix Float32 that can already exceed 0 dBFS.

## Recommendation

**Compute loudness at Export time, over the trimmed frame range read from the CAF master, immediately before re-encode — not at capture time and not as a standing background pass.** Implement ITU-R BS.1770-5's K-weighting/gating/true-peak algorithm by hand over the trimmed Float32 frames rather than depending on macOS 27's new `MusicUnderstanding.LoudnessResult` API for the production Export gain: that API is real (see §4) but is a "song understanding" framework of unverified cost and unverified suitability for arbitrary non-music system audio, has no sub-range input for file-based assets, does not expose a documented true-peak figure, and — like every first-party API found — does not apply gain itself. A hand-rolled BS.1770 pass is small, well-specified, and (§4) cheap enough on Apple Silicon that none of that matters: back-of-envelope, K-weighting plus 4×-oversampled true-peak detection over a full trimmed hour of 48 kHz stereo Float32 is on the order of single-digit seconds of CPU time, not minutes, and is CPU-bound, not I/O-bound.

Recommend **Export Loudness Normalization as an opt-in, per-Export setting, default off**, matching Trim's non-destructive-by-default posture and CONTEXT.md's avoidance of implicit, hidden processing. When enabled, target **-16 LUFS integrated with a -1 dBTP true-peak ceiling**: -16 sits at the quiet end of the -14…-16 LUFS band the surveyed consumer platforms have converged on (§2) — closer to Apple's own Sound Check territory than to Spotify/Tidal/Amazon's music-mastering-tuned -14, appropriate because AppTape's source material (arbitrary captured app audio: games, calls, video playback) is not curated/limited music and shouldn't be pushed as hot as a mastered track. -1 dBTP is the one number every platform and vendor doc surveyed agrees on. Apply a **single fixed linear gain** computed once over the trimmed range (the iZotope RX Loudness Control model, not a dynamics/compressor model), and when the gain needed to hit -16 LUFS would push the measured true peak over -1 dBTP, **clamp the applied gain down to whatever keeps true peak at the ceiling rather than inserting a limiter** — simpler to reason about and to explain in the UI than Adobe Audition's or Spotify's look-ahead limiters, and consistent with a local utility that should not audibly reshape a recording's transients by default. This is a product recommendation, not a settled fact; a future ADR should confirm the default-off/target/clamp choices explicitly.

## 1. The measurement: ITU-R BS.1770 / EBU R128 mechanics

### Primary sources used

Fetched and read directly (PDF text extracted locally, not paraphrased from a blog):
- **ITU-R BS.1770-5** (November 2023, current revision — supersedes -4), "Algorithms to measure audio programme loudness and true-peak audio level." [itu.int/rec/R-REC-BS.1770-5-202311-I/en](https://www.itu.int/rec/R-REC-BS.1770-5-202311-I/en), PDF: [R-REC-BS.1770-5-202311-I!!PDF-E.pdf](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf).
- **EBU R 128** (Geneva, v5, November 2023), "Loudness normalisation and permitted maximum level of audio signals." [tech.ebu.ch/docs/r/r128.pdf](https://tech.ebu.ch/docs/r/r128.pdf).
- **EBU Tech 3341** (v-2023), "Loudness Metering: 'EBU Mode' metering to supplement loudness normalisation in accordance with EBU R 128." [tech.ebu.ch/docs/tech/tech3341.pdf](https://tech.ebu.ch/docs/tech/tech3341.pdf).
- **EBU Tech 3342** (v4, November 2023), "Loudness Range: A measure to supplement loudness normalisation in accordance with EBU R 128." [tech.ebu.ch/docs/tech/tech3342.pdf](https://tech.ebu.ch/docs/tech/tech3342.pdf).

### K-weighting (BS.1770-5 Annex 1)

K-weighting is a two-stage cascaded biquad pre-filter, not a single curve:
- **Stage 1**, a shelving filter modelling "the acoustic effects of the head" (treated as a rigid sphere). At 48 kHz: `b0=1.53512485958697, a1=-1.69065929318241, b1=-2.69169618940638, a2=0.73248077421585, b2=1.19839281085285`.
- **Stage 2**, a high-pass filter ("RLB weighting"). At 48 kHz: `b0=1.0, a1=-1.99004745483398, b1=-2.0, a2=0.99007225036621, b2=1.0`.

The Recommendation is explicit that **these coefficients are only valid at 48 kHz**: "Implementations at other sampling rates will require different coefficient values, which should be chosen to provide the same frequency response that the specified filter provides at 48 kHz." A recorder that only ever writes 48 kHz masters (AppTape's tap always produces the source device's native rate — ADR-0003 notes the format is read from `kAudioTapPropertyFormat`, not assumed) needs to keep this in mind if a Source ever taps at 44.1 kHz or 96 kHz.

After the pre-filter, per-channel mean-square power is combined with channel weights (`GL=GR=GC=1.0` / 0 dB, `GLs=GRs=1.41` / ~+1.5 dB, LFE excluded) into `Loudness = -0.691 + 10·log10(Σ Gi·zi) LKFS`. A pure 0 dBFS, 997 Hz sine into one channel reads **-3.01 LKFS, not 0 LUFS** — a specific, precise instance of the "commonly got wrong" answer below.

### Gating: how integrated loudness is separated from momentary/short-term

BS.1770-5 Annex 1 defines a two-stage gate applied to 400 ms analysis blocks (75% overlap):
1. **Absolute gate**: discard any 400 ms block whose (ungated) loudness is below **-70 LKFS**. This exists so long stretches of silence or noise floor don't drag the average down.
2. **Relative gate**: from the blocks that survive the absolute gate, compute their average loudness, then discard any block more than **-10 LU below that value**. This is Eq. (7) in the Recommendation, and is what EBU R128 explicitly calls out by equation number as "the level-gated measurement of Programme Loudness."
3. **Integrated loudness** is the (ungated-formula) loudness of only the blocks that survive *both* gates.

This is a **two-pass** algorithm — the first pass measures unweighted average loudness to establish the relative threshold, the second applies both thresholds — which is a common implementation shortcut to skip (see below). The relative gate value has itself changed over the standard's history: EBU Tech 3341/3342's own document-history tables record it moving from **-8 LU to -10 LU in the August 2011 revision**, so any older reference material citing -8 LU is measuring a superseded definition.

**Momentary** (0.4 s sliding window, *ungated*, update ≥10 Hz) and **short-term** (3 s sliding window, *ungated*, update ≥10 Hz) are not BS.1770 terms — they are defined in **EBU Tech 3341** on top of BS.1770's 400 ms gating-block machinery, explicitly *without* the absolute/relative gating that integrated loudness uses. Loudness Range (LRA, **EBU Tech 3342**) reuses the same 3 s short-term windows but with a *different* relative gate — **-20 LU** (not -10 LU) below the absolute-gated level, absolute gate still -70 LUFS — and is defined as the difference between the **10th and 95th percentiles** of the resulting (gated) distribution of short-term loudness values. Tech 3342's own worked example (*The Matrix*, DVD): absolute-gated loudness -21.6 LUFS, relative gate at -41.6 LUFS, LRA = 25.0 LU.

### True peak (BS.1770-5 Annex 2)

True-peak level is "the maximum (positive or negative) value of the signal waveform in the continuous time domain," which "may be higher than the largest sample value" because the actual peak of a band-limited waveform generally falls **between** samples. Annex 2's algorithm:
1. Attenuate 12.04 dB (headroom for the next steps).
2. **4× oversample** (48 kHz → 192 kHz minimum oversampled rate; a source already at 96 kHz only needs 2× to reach the same 192 kHz floor — the requirement is the *resulting* rate, not a fixed multiplier).
3. Low-pass/interpolation filter — Annex 2 publishes one concrete filter (order-48, 4-phase FIR) with exact coefficients.
4. Absolute value.
5. Convert to dB, add back the 12.04 dB, report as **dBTP**.

Annex 2's own worst-case under-read table shows *why* 4× is the specified floor rather than an arbitrary round number: at a 4× oversampling ratio the worst-case under-read is ~0.55–0.69 dB; at 8× it drops to ~0.14–0.17 dB; at 32× to ~0.01 dB. 4× is "enough to matter" but not "as accurate as possible" — a meter wanting a tighter guarantee should oversample further.

### What is commonly got wrong

Cross-referencing the Recommendations' own text (not third-party retellings) against what implementations typically skip:

1. **Treating 0 dBFS as 0 LUFS.** The K-weighting reference calibration makes a full-scale 997 Hz tone read **-3.01 LKFS**, not 0. Naive "loudness ≈ RMS in dB" implementations get this wrong by construction.
2. **Single-pass "RMS-ish" loudness instead of the two-stage absolute+relative gate.** Skipping the relative gate (or using a fixed gate instead of one computed per-programme) systematically over- or under-states integrated loudness for content with long quiet/silent stretches — exactly the case BS.1770's gating exists to fix. EBU R128 calls this out directly: measurement "shall be made with a loudness meter compliant with ITU-R BS.1770 (including the level-gating method described in equation (7))" — a plain RMS or ungated average is explicitly non-compliant.
3. **Peak-sample metering mistaken for true-peak.** BS.1770-5's own Annex 2 attachment spends several pages on this: peak-sample meters "do not always register the true-peak value," produce inconsistent readings across replays/sample-rate conversions, miss "unexpected overloads," and under-read tones near Nyquist by several dB. Apple's own Apple Digital Masters guidance (§2) independently rediscovers the same problem under the name "inter-sample clipping" and ships a dedicated tool (`afclip`) specifically because ordinary peak meters miss it.
4. **Confusing "Momentary Loudness" definitions across standards.** EBU Tech 3341 explicitly warns that its own sliding-rectangular-window Momentary Loudness and **ITU-R BS.1771's** differently-defined, IIR-filtered Momentary Loudness "can differ by up to 2 LU" — a 2 LU discrepancy purely from picking the wrong standard's definition of the same term.
5. **Hardcoding the 48 kHz K-weighting coefficients for other sample rates.** BS.1770-5 states outright that other rates "require different coefficient values" re-derived to match the 48 kHz frequency response — a filter design step, not a lookup.
6. **Treating loudness target and true-peak ceiling as independently satisfiable.** iZotope RX's own documentation flags this directly (§3): requesting, say, -10 LKFS loudness together with a -20 dBTP ceiling is an incompatible combination given the source's own peak-to-loudness ratio — the two constraints interact through the material's crest factor, they are not two independent dials.

## 2. Platform targets and true-peak ceilings

Every numeric figure below is labeled **[Published]** (found stated on the platform's own current page/doc, with URL) or **[Measured]** (third-party measured/consensus, no first-party page found publishing it). Per the ticket's warning, YouTube's and several platforms' widely-repeated numbers were specifically checked against an official page rather than assumed.

| Platform | Integrated target | True-peak ceiling | Attenuate-only or also amplifies? | Status |
|---|---|---|---|---|
| **Broadcast (EBU R128)** | -23.0 LUFS (±1.0 LU live tolerance; ±0.2 LU QC tolerance) | -1 dBTP (±0.3 dB tolerance, 20 kHz-bandwidth signal) | N/A — production target, not per-listener playback normalization | **[Published]** — [EBU R 128](https://tech.ebu.ch/docs/r/r128.pdf), items (h) and (m) |
| **Spotify** | -14 LUFS (Normal). User-selectable: Loud -11 LUFS, Normal -14 LUFS, Quiet -19 LUFS | Recommend ≤-1 dBTP; ≤-2 dBTP if the master is louder than -14 LUFS ("to avoid distortion during transcoding") | **Both** — "Positive gain is applied to softer masters so the loudness level is -14 dB LUFS" | **[Published]** — [support.spotify.com, Loudness normalization](https://support.spotify.com/us/artists/article/loudness-normalization/) |
| **Apple Music (Sound Check)** | No exact figure published in Apple's own docs found in this research; commonly cited as **~-16 LUFS** | No dBTP figure published; Apple recommends "at least 1 dB of headroom" before 0 dBFS to avoid oversampling-induced inter-sample clipping on playback | **Both** — Apple's own doc: Sound Check metadata "is then used to **raise or lower** the volume of each track" | Target: **[Measured]** (widely repeated, not found on an Apple page); mechanism/behavior: **[Published]** — [Apple Digital Masters](https://www.apple.com/apple-music/apple-digital-masters/docs/apple-digital-masters.pdf) tech brief |
| **YouTube** | No exact figure found on any `support.google.com` page in this research; commonly cited as **~-14 LUFS** | Not found published anywhere | Reported as attenuate-loud-content-only in third-party sources; boosting quiet content not confirmed either way | **[Measured]** only — see "what I could not verify" |
| **Tidal** | ~-14 LUFS; listener-selectable quieter setting reported around -18 LUFS | ~-1 dBTP | Reported attenuate-only — "does not raise the level of music whose loudness is less than -14 LUFS" | **[Measured]** — no official Tidal page located; figures per third-party mastering-engineer sources (e.g. productionadvice.co.uk) |
| **Amazon Music** | ~-14 LUFS | ~-2 dBTP (more conservative than the -1 dBTP baseline, attributed to lossy-transcode headroom) | Reported attenuate-only for content above target | **[Measured]** — no official Amazon Music page located |

The clearest, best-corroborated pattern across the survey: **modern consumer platforms cluster around -14 to -16 LUFS integrated with a -1 dBTP (occasionally -2 dBTP) true-peak ceiling**, and broadcast is a deliberately quieter -23 LUFS aimed at a different delivery pipeline (wide dynamic range preserved for downstream processing, not final consumer playback level). The most decision-relevant correction found: **the frequently-repeated claim that "Apple Music/Sound Check only turns tracks down, never up" is contradicted by Apple's own Apple Digital Masters documentation**, which states plainly that Sound Check's stored gain metadata is used to "raise or lower" volume — i.e. it does amplify quiet tracks, the same as Spotify, not attenuate-only as several current (2026) third-party guides claim.

## 3. What producing apps offer at Export

| App | Peak / LUFS / both | Shipped default | Clip handling when gain would clip | Presented to non-expert as |
|---|---|---|---|---|
| **Logic Pro** | Both, but **not unified**: the Loudness Meter (channel-strip effect) is a live BS.1770 M/S/I *display* with a draggable target line (-30…0 LUFS) that turns yellow past target — it does not apply gain. Separately, Audio File Editor → Functions → Normalize (⌃N) is classic **peak** normalization ("locates the point with the highest volume… and raises the level… accordingly"), applied destructively to the source file. | No one-click LUFS-target Export/Bounce normalization found in Apple's documented feature set | N/A for peak-normalize (can't clip by construction, since gain is calibrated to the file's own peak); LUFS meter is manual/monitoring only, so clip handling is on the user | A meter you read and a menu command you invoke — no guided workflow |
| **Audacity** | Both, user-selected: Effect → Volume and Compression → **Loudness Normalization**, with "Perceived Loudness" (LUFS, default) or RMS mode | -23 LUFS (perceived, "the EBU standard") or -20 dB (RMS) | **Not documented** on Audacity's own manual page (checked directly) — see "what I could not verify" | A dialog with a raw numeric LUFS/dB field and stereo-channel checkboxes — exposed, technical |
| **Adobe Audition** | Both: **Match Loudness**, at file level or in the Export Multitrack Mixdown "Loudness" effects section | Ships standards-based presets, e.g. **ATSC A/85** (US broadcast): -24 LUFS ±2 LU, -2 dBTP | Dedicated **look-ahead True Peak limiter** ("Match True Peak Level") that "calculates whether the signal will clip **between samples**" before it happens, explicitly contrasted with a "normal hard limiter" that only catches on-sample clipping | Preset picker plus an explicit true-peak safety net — the most complete clip story surveyed |
| **Ferrite Recording Studio** | **Peak only** for its automatic "Normalize" (applied invisibly on import: loudest point of each imported clip is raised to "the edge… and no further"). Not LUFS/BS.1770-based | Peak-normalize on import is automatic and always-on; **Auto-Levelling** is a separate, opt-in, vendor-custom algorithm ("aspects of normalisation, dynamic range compression, peak limiting, and noise gating… it isn't really any of those things specifically") | Per-track normalize can't clip by construction; the vendor's own blog notes **multiple normalized tracks summed together can still clip**, which is what Auto-Levelling at export exists to catch | Fully automatic/invisible by default — no dialog for basic normalize |
| **Descript** | LUFS only, via a licensed third-party engine: "Loudness Target" uses **Auphonic's Global Loudness Normalization Algorithms** to "apply a constant gain to reach a defined target level in LUFS" | Auto-Leveling on import defaults to **-16 LUFS** ("the Apple Podcasts guideline"); adjustable range -31 to -8 LUFS | An Auphonic "True Peak Limiter" is referenced as a related/companion feature; the specific behavior when gain would clip is not fully spelled out in the fetched help article | A single number with a sensible default, framed in plain language ("a quiet guest and a loud host arrive matched") — the most abstracted-for-non-experts of the group |
| **iZotope RX (Loudness Control module)** | LUFS (LKFS) with an explicit **true-peak** ceiling as a second, jointly-constrained parameter | User sets integrated target (LKFS) ± tolerance, plus max true peak | Applies a **fixed, time-invariant gain**, and "a post-limiter will be applied to the signal, if it is required to meet the True peak specification" — limiter engages *only* when needed. Also explicitly documents **incompatible target combinations** (e.g. -10 LKFS with -20 dBTP) as a real failure mode | Two explicit numbers (loudness + true peak) with an automatic safety limiter — professional-tool framing, not hidden |

iZotope RX's own documentation draws a distinction directly relevant to AppTape's design: it separates a **Loudness Control** module (single fixed gain to hit an integrated target, with a true-peak-triggered post-limiter as the only nonlinearity) from a **Leveler** module (continuously time-varying gain / dynamics processing). Everything AppTape needs at Export is the former — a one-shot gain computed from the trimmed range's own measured loudness — not the latter.

## 4. The macOS 27 API surface

Checked directly against the installed macOS 27.0 SDK at `/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk` (this machine: Xcode 27.0 build 27A5237l, macOS 27.0 build 26A5416b, confirmed via `sw_vers`), plus `mcp__xcode__DocumentationSearch` for the Apple Documentation text. A blanket case-insensitive grep for `LUFS|loudness|BS\.?1770|EBU ?R ?128|true.?peak|TruePeak` across every header in `System/Library/Frameworks` returned exactly the hits discussed below — nothing else in the SDK mentions these terms.

### The AudioUnit dynamics units are not BS.1770-aware

`AUComponent.r:56-58` defines the three dynamics-adjacent effect subtypes:
```
kAudioUnitSubType_PeakLimiter          'lmtr'   // AUComponent.r:56
kAudioUnitSubType_DynamicsProcessor    'dcmp'   // AUComponent.r:57
kAudioUnitSubType_MultiBandCompressor  'mcmp'   // AUComponent.r:58
```
Apple's own documentation descriptions (via `DocumentationSearch`) confirm these are ordinary peak/RMS-domain real-time dynamics processors, not loudness-measurement tools: `kAudioUnitSubType_PeakLimiter` is described only as "An audio unit that enforces an upper dynamic limit on an audio signal" — no mention of LUFS, K-weighting, or integration windows anywhere in any of the three units' documented parameters. `AVFAudio`'s `AVAudioUnitEffect` family (`AVAudioUnitEQ`, `AVAudioUnitDistortion`, `AVAudioUnitDelay`, `AVAudioUnitReverb`) is a generic AudioUnit-hosting wrapper, not an algorithm, and none of its concrete subclasses are loudness-related. **No AudioUnit anywhere in the SDK measures or normalizes to BS.1770 integrated loudness.**

### Adjacent but not equivalent: codec-side program-loudness metadata

`AudioToolbox/AudioCodec.h` has decoder/encoder properties for *playback-time* loudness metadata, which solve a different problem (a compressed stream carrying a loudness tag a decoder uses for DRC) than measuring a file's loudness at Export:
- `kAudioCodecPropertyProgramTargetLevelConstant` / `kAudioCodecPropertyProgramTargetLevel` (`AudioCodec.h:456,466`), paired with the `ProgramTargetLevel` enum (`AudioCodec.h:644-657`): `kProgramTargetLevel_None=0`, `kProgramTargetLevel_Minus31dB=1`, `kProgramTargetLevel_Minus23dB=2`, `kProgramTargetLevel_Minus20dB=3` — decoder-side target-loudness constants "typically used for loudness normalization" of *playback*, not a measurement API.
- `AVEncoderDynamicRangeControlConfigurationKey` (`AVAudioSettings.h:43`, `API_AVAILABLE(macos(26.0), ios(26.0), watchos(26.0), tvos(26.0))`) with values `AVAudioDynamicRangeControlConfiguration_{None,Music,Speech,Movie,Capture}` (`AVAudioSettings.h:79-83`) — an AAC-encoder-side DRC profile selector, new in macOS 26, again about how a *decoder* should later compress dynamic range for a listening context, not a BS.1770 measurement or file-normalization tool.

Neither is what the ticket is asking about, but both are evidence Apple's audio stack is loudness-metadata-aware in the codec layer even where it isn't loudness-*measurement*-aware at the file layer.

### The one real hit: `MusicUnderstanding.LoudnessResult` (new in macOS 27.0)

The SDK ships a new framework, `MusicUnderstanding.framework` (`MacOSX.sdk/System/Library/Frameworks/MusicUnderstanding.framework`), available starting **macOS 27.0** (`@available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)` on every public symbol, per the module's `.swiftinterface`). It analyzes an audio source for six things — rhythm, key, loudness, pace, structure, instrument activity — and Apple's own documentation states its `LoudnessResult` "delivers perceptual loudness measurements that align with human hearing perception, using the Loudness K-weighted Full Scale (LUFS) standard defined in ITU-R BS.1770."

```swift
// MusicUnderstanding.swiftmodule/arm64e-apple-macos.swiftinterface:62-67
public struct LoudnessResult : Codable, Sendable {
  public let integrated: TimedValue<Float>     // "measured in LUFS over its full duration"
  public let momentary: [TimedValue<Float>]    // 400ms window, 100ms hop — matches BS.1770/Tech 3341 gating cadence
  public let shortTerm: [TimedValue<Float>]    // 3s window, 100ms hop — matches EBU short-term/LRA window
  public let peak: TimedValue<Float>           // "peak amplitude … in decibels (dB)" — see caveat below
}
```

reached via `MusicUnderstandingSession` (`arm64e-apple-macos.swiftinterface:166`, an `actor`), either from a whole `AVAsset` (`init(asset:)`) or a caller-fed streaming sequence of `AVReadOnlyAudioPCMBuffer` (`init(audioProvider:)`), calling `analyze(for: [.loudness])` or consuming the live `loudnessResults` async sequence.

This is genuinely decision-relevant — it's the first first-party macOS API found anywhere in this research that computes real BS.1770-style integrated/momentary/short-term LUFS — but every gap matters for whether AppTape should depend on it for Export:

- **Measurement only, no normalization.** Every `LoudnessResult` field is a read-only `let`. There is no gain-application method anywhere in the framework — the caller must compute and apply the corrective gain itself.
- **`peak` is not documented as true peak.** The doc text says only "peak amplitude … in decibels (dB)" — no mention of oversampling, no `dBTP` unit, nothing resembling BS.1770 Annex 2's 4× oversampling methodology. Treat this as **likely sample-peak, not BS.1770 true-peak**, until proven otherwise; **unverified**.
- **No Loudness Range (LRA) anywhere in the struct or `SessionResult`.**
- **No file sub-range / time-range parameter** on `init(asset:)` — for AppTape's need to measure only the *trimmed* range of a Recording, the streaming `init(audioProvider:)` path (feeding it exactly the trimmed frames read from the CAF master) is the workable option; the asset-based path appears to analyze the whole asset.
- **Packaging signals a "song" framework, not a general system-audio one.** The module `import`s `CoreML` (implying on-device model use, at least for the non-loudness analyses), and `MusicUnderstandingError` includes a `.hasProtectedContent` case — consistent with a framework built around Apple Music–style catalog "song" content. BS.1770 itself is signal-type-agnostic by design (the Recommendation only specifically disclaims accuracy "to estimate the subjective loudness of pure tones"), so there's no stated reason the loudness analysis specifically would misbehave on captured game audio, VoIP speech, or mixed browser-tab audio — but this has not been confirmed anywhere and is inference, not a documented guarantee.
- **Cost is entirely unbenchmarked.** `analyze(for:)` takes a `Set<AnalysisType>`, so requesting only `.loudness` should in principle skip the other five (ML-flavored) analyses, but the docs never say so explicitly.

### Hand-implementation cost estimate

No Apple or third-party benchmark was found for either path, so this is a back-of-envelope estimate from the published algorithm, not a measurement — flagged as such. For a 1-hour, 48 kHz stereo Float32 trimmed range (~1.4 GB, ~345.6M total samples across both channels):

- **Sequential disk read** of ~1.4 GB from local SSD storage: at even a conservative few-hundred-MB/s sustained sequential read, comfortably under a few seconds — and Export already has to read every byte of the trimmed range to re-encode it, so this I/O is not incremental cost.
- **K-weighting** (2 cascaded biquads per channel, ~9 multiply-adds per biquad stage per sample): on the order of a few billion multiply-adds total — sub-second to low-single-digit seconds even unvectorized; faster with Accelerate/vDSP's biquad routines.
- **BS.1770 Annex 2 true-peak** (order-48, 4-phase FIR interpolator to 4× oversample, i.e. up to ~48 multiply-adds per input sample per channel): the heaviest stage, on the order of 15-35 billion multiply-adds across both channels for the full hour — still comfortably low-single-digit seconds on any Apple Silicon CPU core, let alone with SIMD/Accelerate.
- Gating and percentile/threshold bookkeeping on 400 ms blocks is negligible by comparison.

Net: a full hand-rolled BS.1770 integrated + true-peak pass over an hour-long trimmed range is **CPU-bound, not I/O-bound, and cheap in absolute terms** — plausibly well under 5-10 seconds total on any Apple Silicon Mac, small next to the AAC/ALAC re-encode Export already performs on the same data. This is the practical basis for the recommendation to hand-implement rather than take on `MusicUnderstanding`'s unverified cost and content-suitability profile.

## 5. Applying this to AppTape

**Where normalization lives in the ADR-0003 pipeline.** Three places were considered:
- **At capture time, on the realtime IOProc thread.** Rejected outright — the IOProc "can drop samples, and must say so" per ADR-0003 precisely because it must never block; adding filtering work to it risks the dropped-sample path for no benefit, and a Recording's Trim range (hence the range that actually needs measuring) isn't known until later.
- **As a standing analysis pass right after Recording stops.** Rejected as the primary path: it would measure the *whole* Recording, but only the Trim range ever gets Exported, and Trim can change after the fact (CONTEXT.md: Trim "can be widened, narrowed, or undone at any time"), so a fixed post-capture measurement would frequently be measuring the wrong range. A worthwhile optimization for later, though: cache each 400 ms block's K-weighted power once (whether at Recording-stop or on first Export), after which any future Trim/Export re-run of the gating math is cheap arithmetic over cached block powers, not a re-filter of raw Float32 — but that's an implementation refinement, not where the *decision* needs to live.
- **At Export time, over the trimmed frame range, immediately before re-encode.** Recommended. This matches ADR-0003's own description of Export as the place that "reads the trimmed frame range from the master and re-encodes it" — loudness measurement is naturally an extra pass (or a fused pass) over data Export is already reading, and by construction it always measures exactly the range being produced.

**Target and ceiling.** -16 LUFS integrated, -1 dBTP true peak (see Recommendation above for reasoning) — offered as a per-Export toggle alongside the existing Quality Preset choice, default off.

**Clip handling.** Fixed single gain per Export (not a dynamics processor), clamped down — never up past what -1 dBTP allows — when the gain needed to hit -16 LUFS would exceed the true-peak ceiling. This mirrors iZotope RX Loudness Control's model (fixed gain + true-peak-triggered intervention) but chooses the simpler of RX's two intervention options (gain clamp) over Adobe Audition's look-ahead limiter, on the reasoning that a general local capture tool shouldn't apply audible dynamics processing by default to arbitrary app audio it didn't curate.

**Cost.** Per §4: a hand-rolled BS.1770 pass over a trimmed range up to an hour long is CPU-bound and cheap (plausibly single-digit seconds on Apple Silicon), small relative to the AAC/ALAC encode Export already performs, and does not require pulling in `MusicUnderstanding`'s CoreML-backed, unverified-cost, unverified-content-suitability dependency. AppTape should implement K-weighting, gating, and 4× true-peak oversampling directly over the Float32 frames read for Export, using BS.1770-5 Annex 1/Annex 2's published coefficients — it is a small, fully-specified, one-time DSP implementation, not an open-ended research problem.

## What I could not verify

- **Whether `MusicUnderstanding.LoudnessResult.peak` is BS.1770 Annex-2-style true peak or plain sample peak.** Apple's documentation text is ambiguous ("peak amplitude … in decibels (dB)"), with no oversampling or `dBTP` language found anywhere in the docs or headers. Assumed sample-peak for planning purposes; would need runtime testing against a known inter-sample-peak test signal to confirm either way.
- **Whether `MusicUnderstandingSession.analyze(for: [.loudness])` actually skips the cost of the other five (rhythm/key/pace/structure/instrument) analyses**, or whether the framework still does shared preprocessing work regardless of the requested set. Not documented either way.
- **Any quantitative cost/latency benchmark for `MusicUnderstandingSession`**, from Apple or any third party. None found.
- **YouTube's actual current published loudness target.** No `support.google.com` page stating an exact LUFS figure was found in this research despite multiple targeted searches; "-14 LUFS" is a widely-repeated third-party consensus figure, not confirmed against an official YouTube page. Whether YouTube boosts quiet uploads (vs. attenuate-only) is also inconsistently described across secondary sources and was not resolved to a primary source.
- **Official Tidal and Amazon Music support pages for their loudness targets.** Both platforms' figures here rest on third-party mastering-engineer sources; no first-party Tidal or Amazon Music documentation page was located.
- **Audacity's own documented behavior when the gain needed to hit a Loudness Normalization target would clip.** The manual page fetched (`manual.audacityteam.org/man/loudness_normalization.html`) does not address this; would need either a deeper manual page or the source code to confirm.
- **Descript's exact clip/limiter behavior for its Loudness Target setting.** The fetched help article references an Auphonic "True Peak Limiter" as a related feature via a "learn more" link but doesn't fully spell out the mechanics in the article body itself.
- **EBU R 128 s2 ("Loudness in Streaming")'s specific numeric guidance.** Confirmed it exists (v3.0, November 2023) and that it says streaming services "typically use a higher Target Loudness Level than specified in Broadcast Loudness standards," but did not extract its specific recommended figures — the platform-specific numbers in §2 were sourced from each platform's own page instead.
- **Whether Adobe Audition's Match Loudness ships an EBU R128 (-23 LUFS) preset in addition to the confirmed ATSC A/85 preset.** Plausible (this class of tool typically ships both) but not independently confirmed — Adobe's own Match Loudness help page (`helpx.adobe.com/audition/using/match-loudness.html`) repeatedly failed to render its full body text through the fetch tooling used in this research; the ATSC A/85 figure came through in a partial fetch, but the full preset list was not confirmed.

## Sources

**ITU-R / EBU primary standards (PDF text extracted and read directly):**
- [ITU-R BS.1770-5 (11/2023)](https://www.itu.int/rec/R-REC-BS.1770-5-202311-I/en) — [PDF](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf)
- [EBU R 128 (v5, 11/2023)](https://tech.ebu.ch/docs/r/r128.pdf)
- [EBU Tech 3341 (v-2023), "EBU Mode" metering](https://tech.ebu.ch/docs/tech/tech3341.pdf)
- [EBU Tech 3342 (v4, 11/2023), Loudness Range](https://tech.ebu.ch/docs/tech/tech3342.pdf)
- [EBU R 128 s2, "Loudness in Streaming" (v3.0, 11/2023)](https://tech.ebu.ch/publications/r128s2) — existence and general framing confirmed; specific figures not extracted (see "could not verify")

**Platform-published pages:**
- [Spotify, Loudness normalization (support.spotify.com)](https://support.spotify.com/us/artists/article/loudness-normalization/)
- [Apple, Apple Digital Masters technology brief (PDF)](https://www.apple.com/apple-music/apple-digital-masters/docs/apple-digital-masters.pdf)
- [Apple Support, "If music in Apple Music sounds quiet"](https://support.apple.com/en-us/109331) (content confirmed via search-snippet extraction of the live page; direct full-body fetch was blocked by the page's JS rendering)

**Producing-app vendor docs:**
- [Apple, Loudness Meter in Logic Pro for Mac](https://support.apple.com/guide/logicpro/loudness-meter-lgce12d9d256/mac)
- [Apple, Normalize audio files in Logic Pro for Mac](https://support.apple.com/guide/logicpro/normalize-audio-files-lgcp21590742/mac)
- [Audacity Manual, Loudness Normalization](https://manual.audacityteam.org/man/loudness_normalization.html)
- [Adobe, Adjusting loudness to match across the file (Match Loudness)](https://helpx.adobe.com/audition/using/match-loudness.html)
- [Wooji Juice (Ferrite), "Audio Clipping (And Normalisation And More)"](https://www.wooji-juice.com/blog/audio-clipping.html)
- [Descript Help, Advanced Audio Mixing Settings](https://help.descript.com/hc/en-us/articles/23106157717133-Advanced-Audio-Mixing-Settings)
- [iZotope, RX 9 Help — Loudness Control](https://s3.amazonaws.com/izotopedownloads/docs/rx9/en/loudness/index.html)

**macOS 27 SDK headers** (`/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`, this machine: Xcode 27.0 build 27A5237l on macOS 27.0 build 26A5416b):
- `AudioUnit.framework/Headers/AUComponent.r:56-58` — `kAudioUnitSubType_PeakLimiter`/`DynamicsProcessor`/`MultiBandCompressor`
- `AudioToolbox.framework/Versions/A/Headers/AudioCodec.h:456,466,523,525,644-657` — `kAudioCodecPropertyProgramTargetLevel(Constant)`, `ProgramTargetLevel` enum
- `AVFAudio.framework/Versions/A/Headers/AVAudioSettings.h:43-44,78-83` — `AVEncoderDynamicRangeControlConfigurationKey` (`API_AVAILABLE(macos(26.0))`), `AVAudioDynamicRangeControlConfiguration`
- `MusicUnderstanding.framework/Versions/A/Modules/MusicUnderstanding.swiftmodule/arm64e-apple-macos.swiftinterface` (full file, 236 lines) — `LoudnessResult` (lines 61-67), `MusicUnderstandingSession` (line 165-166), `AnalysisType`, `SessionResult`, all `@available(macOS 27.0, *)`
- Negative-result greps confirming no other framework references these terms: case-insensitive search for `LUFS|loudness|BS\.?1770|EBU ?R ?128|true.?peak|TruePeak` across every header under `System/Library/Frameworks`

**Apple Developer Documentation** (via `mcp__xcode__DocumentationSearch`): `LoudnessResult`, `MusicUnderstandingSession`, `AVAudioUnitEffect`, `kAudioUnitSubType_PeakLimiter`, "Effect Audio Unit Subtypes," "MusicUnderstanding Extended API Documentation."

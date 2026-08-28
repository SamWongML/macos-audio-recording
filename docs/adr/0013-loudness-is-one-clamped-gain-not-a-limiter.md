---
status: accepted
---

# Loudness normalization is one clamped gain, not a limiter

An Export can normalize a Recording's **Loudness** to a fixed target so that captures from
different Sources play back at the same level. The correction is **opt-in and default off**,
matching Trim's non-destructive posture, and is measured over the **trimmed range** at Export
time — never over the whole Recording and never at capture — because only the trimmed range is ever
produced and Trim can change after the fact (ADR-0003, and the measure-then-encode pass of
ADR-0012). The measurement is a hand-rolled **ITU-R BS.1770-5 / EBU R128** pass over the trimmed
Float32 frames; the correction it drives is a **single fixed linear gain**. This ADR fixes the
numbers and the boundary behaviour of that gain. **Loudness** is the measured level and the
automatic correction; **Gain** (ADR glossary) is the user's separate manual offset on top, starting
at 0 and stored against the Recording like Trim.

The contract:

- **Target −16 LUFS integrated, ceiling −3 dBTP true peak.** Identical across all four Quality
  Presets (ADR-0005): Loudness and quality are independent axes.
- **Amplify toward the target, capped at +12 dB; attenuate uncapped.**
- **Clamp the gain at the ceiling — never insert a limiter.** A single fixed linear gain, reduced
  until true peak sits at −3 dBTP, landing short of the target rather than reshaping the waveform.
- **A range with no measurable integrated loudness gets no correction (0 dB).**
- **The toggle is a sticky, app-wide preference, off on first use** — the shape of the Quality
  Preset (ADR-0005), not a per-Recording property like Gain and Trim.

## Considered options

**−16 LUFS over the −14 the platforms cluster nearest, and −3 dBTP over their −1.** AppTape's
Exports are for personal playback, never uploaded, so no platform figure is a compliance target —
the −14…−16 LUFS convergence across five independent services is only *evidence about comfortable
playback level on the same phones, headphones and speakers an Export is played through*. −16 sits at
the quiet end of that band deliberately: the material is captured, not mastered, so its
peak-to-loudness ratio is whatever the producing app happened to output, and there is more reason
for caution than when a platform normalizes an already-limited master. The ceiling departs from
every surveyed platform's −1 dBTP (occasionally −2) for a concrete reason: their ceilings protect a
*downstream transcode* they perform, which AppTape does not have — an Export is the last re-encode
anyone runs on this audio. The −3 dBTP margin instead absorbs the AAC/ALAC re-encode's own
inter-sample ringing near a hard ceiling and banks a usable ~3 dB for a manual Gain nudge, where
−1 dBTP would leave under 1 dB before a later boost clips, at no audible loudness cost.

**Amplify-and-cap over attenuate-only, and over uncapped amplify.** Attenuate-only fails the
Library-consistency goal outright — a −28 LUFS phone-call Recording stays at −28 forever, exactly
the content that most wants help — so it is not a safer default, it is a *non*-default that opts
quiet captures out of the feature. Uncapped amplify has the opposite failure, specific to this
material: a whole-file fixed gain cannot spare a quiet background from a large boost the way a
segment-aware leveler can (Auphonic's Adaptive Leveler excludes noise/breath/silence segments from
amplification; a single scalar cannot), so an uncurated capture's noise floor rises with its signal.
The cap resolves it: **+12 dB** closes the consistency gap for ordinary quiet captures while
refusing to chase a very quiet, very noisy capture all the way to target, leaving it under −16
rather than audible hiss. Attenuation carries no equivalent risk — it lowers noise with signal — so
it is applied uncapped.

**A gain clamp over a look-ahead limiter, though the limiter is available.** When the gain needed to
reach −16 LUFS would breach −3 dBTP or the +12 dB cap, the gain is clamped down and the Export lands
short. The alternative — a look-ahead true-peak limiter that hits the target by holding transients
down (Adobe Audition, iZotope RX) — is a real, shipped pattern, and the SDK ships the primitive for
it: `kAudioUnitSubType_PeakLimiter` (`'lmtr'`) exists in `AUComponent.h`. It is declined on purpose.
A local utility should not apply audible dynamics processing by default to arbitrary app audio it did
not curate, and — decisively — a clamp keeps the whole path a **pure scalar multiply**, which is what
makes the double-normalization stance below hold. A limiter is a nonlinearity that can compound;
a clamp cannot.

**Hand-rolled BS.1770 over `MusicUnderstanding.LoudnessResult`, verified against the macOS 27 SDK.**
macOS 27 ships the first first-party BS.1770-style API, but it does not fit Export. Verified in
`MusicUnderstanding.framework`'s `arm64e-apple-macos.swiftinterface`: every field of
`LoudnessResult` (`integrated`, `momentary`, `shortTerm`, `peak`) is a read-only `public let` with
**no gain-applying method anywhere** — the caller must compute and apply the corrective gain itself —
and the only session initializer, `init(asset:)`, together with `analyze(for:)`, **takes no
time-range**, so it cannot measure a Trim on the asset path. Its `peak` is documented only as "peak
amplitude … in decibels," with no oversampling or dBTP language, so it is not dependable as BS.1770
true peak. Against that, a hand-rolled K-weighting + gating + 4× true-peak pass over the trimmed
Float32 is small, fully specified by BS.1770-5 Annexes 1–2, and cheap — single-digit CPU-seconds for
an hour of 48 kHz stereo, small next to the re-encode Export already performs on the same frames. A
blanket grep for `LUFS|BS.1770|true.?peak` across every framework header returns nothing that both
measures BS.1770 loudness *and* applies gain.

**Two separate figures over one combined, for the correction and the manual Gain.** Showing a single
merged dB number would hide which part the app measured and chose and which the user dialed in, and
defeat Gain being a defeatable offset the user can reason about. They stay distinct, matching the
glossary's own split.

## Consequences

**The correction is a dB figure, previewed before Export, with a caption only when it falls short.**
When normalization is on for the selected Recording and Trim, the inspector shows the correction it
will apply as a decibel figure (never as LUFS) — resolving after a brief measure rather than
instantly, since the figure needs a full BS.1770 pass where ADR-0005's size estimate needs only
arithmetic. A full hit shows just the number (`+4.2 dB`). The three ways it can land short of −16
each add a plain-language caption naming *why*, because silently missing the target is the failure
mode: the **+12 dB cap** (`+12.0 dB · limited to keep the noise floor down`), the **−3 dBTP ceiling**
(`+5.1 dB · peak ceiling reached`), and an **unmeasurable range** (no number:
`No correction — range too quiet to measure`). Distinguishing the cap from the ceiling is honest and
cheap — one guards hiss, the other guards clipping.

**A trimmed range with no measurable integrated loudness gets 0 dB, and the Export still completes.**
Integrated loudness is undefined in two reachable cases. A **silent range** — every 400 ms block
below the −70 LKFS absolute gate — has no loudness to amplify toward, and amplifying it is infinite
gain on noise. A **too-short range**: the Trim minimum is **0.2 s** (issue #7), shorter than one
400 ms gating block, so a 0.2–0.4 s trim contains no complete block and integrated loudness cannot be
formed at all — as does any adopted Recording under 0.2 s (issue #30). Both resolve the same way:
apply no gain, produce the file normally at the chosen preset, and show the "range too quiet to
measure" telling. A correction is never invented from an undefined measurement.

**Re-normalizing an already-normalized Source does not meaningfully double-normalize.** Two
independent reasons, and the design leans on the second. First, a Core Audio process tap captures
post-mix Float32 downstream of the app's own volume control and the system output slider (ADR-0003
notes it can already exceed 0 dBFS), none of them BS.1770-aware — so a stream nominally served at
−14 LUFS is captured at whatever level those sliders left it, and the source's nominal figure is not
a number AppTape can trust or skip its own measurement over. Second, because the correction is a
fixed linear gain (the clamp above, never a limiter), stacking it on a source's prior fixed gain is
one combined multiply, not two compounding nonlinear passes. This is accepted as reasoned, not gated
on an empirical Spotify-capture test; it is worth a spot-check once the capture path writes real
Recordings.

**Gain rides on top, as its own axis.** The manual Gain offset (glossary) applies after the Loudness
correction, starts at 0, and is stored per-Recording like Trim; it is shown as its own dB figure, not
folded into the correction's. Its exact control — slider range and placement in the inspector — is
left as implementation latitude here; nothing in this contract turns on it.

**An implementation refinement, not a decision:** each 400 ms block's K-weighted power can be cached
on first measure, after which a new Trim re-runs only the gating arithmetic over cached block powers
rather than re-filtering raw Float32 — what makes the previewed figure cheap to update as a handle
moves.

Settled in issue #24. Research in issue #23.

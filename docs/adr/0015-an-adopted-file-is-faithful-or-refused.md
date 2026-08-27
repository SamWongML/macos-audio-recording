# An adopted file is faithful-or-refused, never silently converted

The Library is an ordinary folder ([ADR-0006](0006-the-library-is-a-folder.md)), so any file the user drops in is **adopted** as a Recording — audio whose channel count, sample rate and format the app did not choose, breaking the stereo-mixdown guarantee ([ADR-0003](0003-immutable-lossless-caf-master.md)) that made [#9](https://github.com/SamWongML/macos-audio-recording/issues/9)'s "stereo at native rate, no resampler, no downmix" Export path safe. We adopt broadly but Export **faithful-or-refuse**: preserve the source exactly where a preset's codec can encode it, and where it can't, disable *that preset* with a plain reason rather than resample or downmix. We never silently convert an adopted file, and we never track its provenance.

## Context

The platform default is the opposite of what we want. Verified by live query against this macOS 27 system (`AudioFormatGetProperty`, `afconvert -hf`):

- `AudioConverter` with a mismatched output **silently truncates** channels (`kAudioConverterChannelMap` default keeps the first N inputs, discards the rest — a lossy channel drop, *not* a mix; `kAudioConverterPropertyPerformDownmix` defaults off) and **silently resamples** (built-in SRC engages automatically when the codec can't take the source rate). No error, no warning.
- So faithfulness is not free: it requires the app to actively gate on the source format *before* configuring the encoder. `AVAudioFile.fileFormat.channelCount` / `.sampleRate` are cheap (read from the container header, no decode), so the gate costs nothing.
- The encoders' real limits: **AAC-LC** takes 1–8 channels (mono through 5.1 encode natively) but caps at **48 kHz**; **HE-AAC** ("Compact", 64 kbps) takes even channel counts only; **ALAC** takes any rate and up to 8 channels losslessly. So preserving the source mostly *works* — the genuine refusal cases are a sample rate above 48 kHz (disables the three AAC rungs) and odd channel counts above 2 on Compact. Master/ALAC always works, the escape hatch for exotic files.
- `AVAudioFile` reads any of caf/wav/aiff/m4a(AAC,ALAC)/mp3/flac/ogg-opus, transparently decoding to Float32 regardless of on-disk format, so a non-Float or integer source needs no special handling on the read side.

## Decision

- **Adoption gate.** List a Library row for any non-hidden file whose UTType conforms to `public.audio`; confirm by actually opening it on selection. `public.audio` is necessary but not sufficient (WMA, RealAudio, MIDI, SoundFont, Audible DRM conform to it yet won't open), so the open-on-selection step is the real gate — a typed-but-unopenable file shows an inline "can't open" state rather than crashing or vanishing, and stays deletable via the normal `trashItem`.
- **Format handling.** Gate on the cheap `fileFormat` channel count and sample rate; preserve the source where the codec accepts it (mono→mono, 5.1→5.1 AAC — no invented upmix or downmix); disable a preset the codec can't encode faithfully, with a plain reason. Never resample, never downmix.
- **Disabled presets and the sticky preference.** [#9](https://github.com/SamWongML/macos-audio-recording/issues/9)'s Quality Preset is an app-wide sticky preference. When the sticky preset can't encode the selected file, the unusable rungs show disabled with a reason and Export is blocked until a working rung is chosen — **no silent fallback** (which would surprise the user with a much larger ALAC file and break "parameters snapshot at launch"). Disabling a rung for one file is a display over the sticky preference, not a change to it; navigating to a normal Recording restores the sticky choice untouched.
- **Lossy sources.** An already-lossy adopted file (`.m4a`, `.mp3`) Exports normally with no guard and no warning — every preset re-encodes by design, the app is not a quality guardian, and the codec is already visible as preset subtitle text.
- **Sub-0.2 s files.** A file shorter than the Trim minimum ([#7](https://github.com/SamWongML/macos-audio-recording/issues/7)) is adopted and listed with Trim fixed to the whole file; play and whole-file Export still work ([#24](https://github.com/SamWongML/macos-audio-recording/issues/24) already gives the sub-400 ms range 0 dB and completes the Export).
- **No provenance.** Origin is never tracked, marked, or derived — only *capability* differences surface (a disabled preset's reason, a fixed Trim). Consistent with [ADR-0006](0006-the-library-is-a-folder.md): the folder is the truth, there is no marker to write and nothing to re-derive.
- **Size estimate.** [#9](https://github.com/SamWongML/macos-audio-recording/issues/9)'s `bitrate × duration × 1.02` estimate is shown unchanged for adopted files — it is output-codec-driven, independent of the source, and already a promised-nothing "≈".

## Consequences

- The Export path must branch on the source format for adopted files; it cannot assume the ADR-0003 stereo-mixdown invariant. This is a deliberate, contained divergence, gated on two cheap header reads.
- The **Recording** glossary is sharpened: an adopted file behaves identically *except* that which Quality Presets are available depends on its format.
- Master/ALAC becomes load-bearing as the universal Export path for any file AAC can't take.

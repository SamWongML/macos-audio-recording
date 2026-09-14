# AppTape

A macOS menu-bar utility that records the audio of one running application and lets you trim and
export it. Capture uses Core Audio process taps, so only the chosen app is recorded — not the
system mix, and not your microphone.

## Requirements

- macOS 27 or later
- Xcode 27 (Swift 6.4 toolchain)
- A code-signing team: the app needs the System Audio Recording entitlement, which ad-hoc signing
  cannot carry. See [ADR-0002](docs/adr/0002-personal-team-code-signing.md).

## Build and test

```sh
xcodebuild build -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS'
xcodebuild test  -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
swift-format lint --strict --recursive AppTape   # $(xcrun --find swift-format)
```

## How it is put together

The app target is one flat directory of 61 files. The shape that matters:

- **Capture** — `CaptureRun` owns one run start to stop and makes every decision; `CaptureEngine`
  owns the tap, the writer thread and the CAF master. They meet at four protocols in
  `CaptureAdapters.swift`, which is what lets the suite drive a whole run with no audio hardware.
- **Library** — `LibraryStore` lists an ordinary folder. A `Recording` is a file; Trim and Gain
  ride in its extended attributes, so a Finder rename or move is followed silently.
- **Editor** — `EditorModel` coordinates store, selection, playback and Export. Views accept their
  state rather than reaching for singletons.
- **Export** — `ExportReadiness` decides once whether an Export can run; `ExportCoordinator` runs
  it off the main actor and `ExportEncoder` does the encode.

Decisions live in [`docs/adr/`](docs/adr/README.md) — 48 records, indexed. Source files do not cite
them inline.

## Conventions

- Swift 6 language mode, complete strict concurrency. The app target's default actor isolation is
  `MainActor`; anything off it says `nonisolated` explicitly, and the compiler now enforces that.
- Tests are Swift Testing only. No XCUITest layer — see
  [ADR-0018](docs/adr/0018-no-xcuitest-layer.md).
- Comments carry one sentence. Rationale, measurements and history belong in an ADR, not in a doc
  comment.

## Vocabulary

Terms that mean something specific here, and are used consistently in code, tests and ADRs.

| Term | Meaning |
|---|---|
| **Source** | The single running application whose audio is captured. Chosen once and remembered. |
| **Recording** | The audio captured in one continuous run, saved automatically. Its content begins at the first sound the Source produces, so silence before playback is never part of it — and if the Source never makes a sound, nothing is saved. A file placed in the Library by hand is adopted as a Recording and behaves identically. |
| **Dropout** | A stretch of silence inside a Recording standing in for audio that never arrived, because capture was interrupted or a buffer was lost under load. It keeps the Recording true against the clock, so everything after it still sits where it was heard. |
| **Library** | The folder of Recordings the app lists — an ordinary visible folder, so the user can rearrange it in Finder and the app follows. |
| **Trim** | The start and end points selecting which part of a Recording is Exported. Choosing them never alters the Recording. |
| **Trimmed-away** | The part of a Recording outside its Trim. Still audio and still shown, quieter than the kept part rather than removed from the picture. |
| **Export** | Producing a finished audio file from a Recording at a chosen Quality Preset. |
| **Quality Preset** | A named audio-quality setting offered at Export. It determines the file's size, which is only ever estimated, never promised. |
| **Runway** | How much longer a Recording could keep capturing before the disk runs short. Always a length of time, never free bytes. |
| **Loudness** | How loud a Recording sounds over time, measured to BS.1770 rather than read off its peaks. Export can correct it to a fixed target. |
| **Gain** | A manual decibel offset for one Recording, applied on top of any Loudness correction. Like Trim, it never alters the Recording. |
| **Ceiling** | The highest true peak an Export lets the audio reach while correcting Loudness. |
| **Amplification cap** | The largest boost a Loudness correction will apply, so a very quiet, noisy Recording is left below target rather than having its noise floor lifted into audibility. |

## Licence

MIT — see [LICENSE](LICENSE).

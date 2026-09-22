# AppTape

hello from chatgpt chat

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

The app target uses one flat source directory. The shape that matters:

- **Capture** — `CaptureRun` owns one run start to stop and makes every decision; `CaptureEngine`
  owns the tap, the writer thread and the CAF master. They meet at four protocols in
  `CaptureAdapters.swift`, which is what lets the suite drive a whole run with no audio hardware.
- **Library** — `LibraryStore` lists an ordinary folder. A `Recording` is a file; Trim and Gain
  ride in its extended attributes, so a Finder rename or move is followed silently.
- **Editor** — `EditorModel` coordinates store, selection, playback and Export. Views accept their
  state rather than reaching for singletons.
- **Export** — `ExportReadiness` decides once whether an Export can run; `ExportCoordinator` runs
  it off the main actor and `ExportEncoder` does the encode.

Decisions live in [`docs/adr/`](docs/adr/README.md) — indexed by work area. Source files do not cite
them inline.

## Conventions

- Swift 6 language mode, complete strict concurrency. The app target's default actor isolation is
  `MainActor`; anything off it says `nonisolated` explicitly, and the compiler now enforces that.
- Tests are Swift Testing only. No XCUITest layer — see
  [ADR-0018](docs/adr/0018-no-xcuitest-layer.md).
- Comments carry one sentence. Rationale, measurements and history belong in an ADR, not in a doc
  comment.

## Vocabulary

Canonical domain terms are defined in [CONTEXT.md](CONTEXT.md). Read the glossary when naming
concepts in code, tests, issues or ADRs.

## Licence

MIT — see [LICENSE](LICENSE).

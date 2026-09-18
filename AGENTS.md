# AppTape

macOS menu-bar app that records one running application's audio via Core Audio process taps, then
trims and exports it. One Xcode project, two targets, no package manager. Builds require Xcode 27
and the macOS 27 SDK; the deployment target is macOS 27.

## Commands

Run from the repository root. Build a signed app for manual capture checks:

```sh
xcodebuild build -project AppTape/AppTape.xcodeproj -scheme AppTape \
  -destination 'platform=macOS'
```

Run the Swift Testing suite, format Swift sources, and check formatting:

```sh
xcodebuild test -project AppTape/AppTape.xcodeproj -scheme AppTape \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
$(xcrun --find swift-format) format -i --recursive AppTape
$(xcrun --find swift-format) lint --strict --recursive AppTape
```

`AppTape/AppTape/` uses a synchronised folder group — adding a `.swift` file needs no project edit.

The unsigned test command matches CI. Manual audio-capture checks need a stable Apple Development
signature; see [ADR-0002](docs/adr/0002-personal-team-code-signing.md).

## Codebase map

| Area | Start here | Boundary |
|---|---|---|
| Capture | `AppTape/AppTape/CaptureRun.swift`, `CaptureAdapters.swift` | One run accepts capture, disk and reporting dependencies; its clock is passed to `tick(now:)`. |
| Audio I/O | `AppTape/AppTape/CaptureEngine.swift`, `ProcessTap.swift`, `CAFMasterWriter.swift` | Core Audio tap, realtime buffers and the master writer. |
| Library | `AppTape/AppTape/LibraryStore.swift`, `RecordingReader.swift`, `RecordingMetadata.swift`, `EnvelopeCache.swift` | Folder reconciliation, file facts, persisted edits and derived waveform data. |
| Editor | `AppTape/AppTape/EditorModel.swift`, `EditorView.swift`, `TrimTimeline.swift`, `TimelineGeometry.swift` | Selection, playback and Trim; views accept their state. |
| Export | `AppTape/AppTape/ExportReadiness.swift`, `ExportCoordinator.swift`, `ExportEncoder.swift`, `LoudnessMeter.swift` | Shared refusal rules, cancellable work, encoding and Loudness measurement. |
| App lifecycle | `AppTape/AppTape/MenuBarController.swift`, `EditorPresenter.swift`, `ActivationPolicyController.swift` | Menu-bar transport, editor windows and activation policy. |
| Tests and CI | `AppTape/AppTapeTests/`, `.github/workflows/ci.yml` | Swift Testing with capture/recording doubles and real-file integration checks. |

The shared `AppTape` scheme builds `AppTape` and tests `AppTapeTests`.

## Constraints

- macOS only, and **not sandboxed**: process taps need the System Audio Recording entitlement, which
  the App Sandbox does not grant. Do not set `ENABLE_APP_SANDBOX`.
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, default actor isolation `MainActor`
  on both targets. Anything off the main actor says `nonisolated` explicitly.
- Tests are Swift Testing only (`import Testing`, `@Test`, `#expect`). Never add XCTest, and never
  add a UI-test target — see `docs/adr/0018-no-xcuitest-layer.md`.
- The `.caf` xattr keys (`com.apptape.source`, `.trim`, `.gain`, `.seams`) are persisted on users'
  files. Never rename a key string, whatever the Swift identifier is called.

## Comments

One sentence, and only where the name and signature do not already say it. Rationale,
measurements, alternatives considered and history belong in an ADR under `docs/adr/`, never in a doc
comment. Do not cite ADRs or issue numbers from source — `docs/adr/README.md` is the index.

## Agent skills

### Issue tracker

Track issues and specs in GitHub Issues for `SamWongML/macos-audio-recording`.
Before fetching or publishing tickets, read [docs/agents/issue-tracker.md](docs/agents/issue-tracker.md).

### Triage labels

Use the five default triage roles. Before triaging, read
[docs/agents/triage-labels.md](docs/agents/triage-labels.md).

### Domain docs

Use a single context: root `CONTEXT.md` and `docs/adr/`. Before exploring a work area, read
[docs/agents/domain.md](docs/agents/domain.md), the glossary and the relevant ADRs from the index.

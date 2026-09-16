# AppTape

macOS menu-bar app that records one running application's audio via Core Audio process taps, then
trims and exports it. One Xcode project, two targets, no package manager.

## Commands

```sh
xcodebuild test -project AppTape/AppTape.xcodeproj -scheme AppTape \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
$(xcrun --find swift-format) format -i --recursive AppTape
$(xcrun --find swift-format) lint --strict --recursive AppTape
```

`AppTape/AppTape/` uses a synchronised folder group — adding a `.swift` file needs no project edit.

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

## Decisions

49 records in `docs/adr/`, indexed by `docs/adr/README.md`. Read the ones touching the area you are
changing. If a change contradicts one, say so and amend that ADR rather than silently overriding it.

## Vocabulary

Defined in `README.md`. The load-bearing ones: **Source**, **Recording**, **Dropout** (silence
standing in for audio that never arrived), **Library**, **Trim** / **Trimmed-away**, **Export**,
**Quality Preset**, **Runway** (capture time left before the disk runs short), **Loudness**,
**Gain**, **Ceiling**.

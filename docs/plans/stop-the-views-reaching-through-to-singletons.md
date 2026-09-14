---
status: delivered
source: architecture review, 12 Sep 2026 — candidate 3, "Stop the views reaching through to singletons"
record: docs/adr/0045-the-views-accept-their-state-they-do-not-reach-for-it.md
---

# Stop the views reaching through to singletons

## Context

ADR-0043 closed with the sentence this change answers: *"The views were left alone. All five still read
`RecordingController.shared` … Moving them onto an injected interface is a separate change with a
separate argument."* This is that change, and the argument is below.

Nine view-side reaches at `.shared`, across seven view types and one AppKit controller:

| file:line | declaration | singleton |
|---|---|---|
| `EditorView.swift:17` | `@State private var model = EditorModel.shared` | EditorModel |
| `EditorView.swift:20` | `@State private var recorder = RecordingController.shared` | RecordingController |
| `EditorView.swift:605` (`RecordingBrief`) | `@State private var recorder = …` | RecordingController |
| `EditorView.swift:734` (`LibraryRow`) | `@State private var recorder = …` | RecordingController |
| `ExportInspector.swift:16-19` | four singletons, four consecutive lines | Preference · Coordinator · Controller · EditorModel |
| `TrimTimeline.swift:27` | `@State private var recorder = …` — the 5th property on a view whose other four are accepted | RecordingController |
| `PanelView.swift:25` | `private var recorder: RecordingController { .shared }` | RecordingController |
| `MenuBarController.swift:52` | `private var recorder: RecordingController { .shared }` | RecordingController |
| `AppTapeApp.swift:152` (`LibraryRowCommands`) | `private var model: EditorModel { .shared }` — the one the review missed | EditorModel |

Plus `EditorWindowLifecycle.swift:78,91-92`, a `NSViewRepresentable` inside `EditorView` reaching
`ExportCoordinator.shared` and `ActivationPolicyController.shared`.

**What the editor side actually reads is four members**: `isCapturing(_:)`, `isStillArriving(_:)`,
`elapsed`, `masterByteCount`. Five views, read-only, no commands — `EditorView:478/530/531/547/562`,
`RecordingBrief:607/648/649`, `LibraryRow:738/739/845`, `ExportInspector:39/451`,
`TrimTimeline:50/55`. The shell publishes fifteen, two of which (`currentLevel`, `capturingURL`) are
read by nothing at all.

The consequence is stated plainly by the repo itself: there is exactly one `#Preview` in the codebase
(`EditorView.swift:950`), it takes no parameters, and so it silently boots `EditorModel.shared` →
`LibraryStore` → the real Library folder, and `RecordingController.shared` → `CoreAudioCaptureBuilder`
→ Core Audio and a `statfs`. `ExportInspector`, `TrimTimeline` and `RecordingBrief` have no preview at
all, because each needs a live capture controller, and the inspector additionally needs an
`EditorModel` — whose `init()` is `private` (`EditorModel.swift:42`), so a second one cannot be built.
`EditorView` has churned 12 times in three days with nothing able to hold any of it still.

**Be clear about the payoff, because ADR-0018 bounds it.** The suite instantiates no view and never
will — there is no XCUITest layer and no view-testing library. So this change does not buy view
tests. It buys three things: **previews for capture states the real app can only reach through Core
Audio**, **one place per root where a global is named**, and **an interface that states what the
editor may know about capture** — the boundary ADR-0021 and ADR-0031 are about. The tests it does buy
are `EditorModel`'s, which has none and holds `reconcileSelection` (Phase 5).

---

## As built

Seven commits on `refactor/the-views-accept-their-state`. The suite went from 288 cases to **297**,
green, with no warning of its own in either target, and both targets build clean.

| file | change |
|---|---|
| `CaptureState.swift` | +66: the protocol, the derived rule, `extension CaptureRun: CaptureState {}` |
| `PreviewFixtures.swift` | +178: `PreviewCapture`, the moved `Recording.stub`, `Envelope.preview`, `PreviewLibraryReader`, `EditorModel.preview` |
| `EditorView.swift` | +93/−29: three views accept `capture`, the window accepts `model`, four previews |
| `ExportInspector.swift` | +117/−15: four accepted collaborators, six dock previews |
| `TrimTimeline.swift` | +60/−12: the fifth property is accepted like the other four, three lane previews |
| `EditorModel.swift` | +51/−14: five collaborators, two initializers, two global reads gone |
| `EditorModelTests.swift` | +180: nine cases over a type that had none |
| `RecordingController.swift` | +16/−16: five forwards deleted, and what is left says who it is for |
| `CaptureRun.swift`, `ExportCoordinator.swift`, `EditorWindowLifecycle.swift`, `MenuBarController.swift`, `PanelView.swift`, `AppTapeApp.swift`, `AppDelegate.swift` | ±90 between them |

Five things differ from the plan below, each because writing the code showed the plan was wrong.

- **The model came before the inspector.** §4 ordered them the other way, which would have needed
  `EditorView` to name `ExportPreference.shared` and `ExportCoordinator.shared` for one commit and
  then delete them in the next. Doing Phase 3 first meant the inspector's four collaborators came off
  an already-injected model with no stopgap at all.
- **`ExportCoordinator.park(in:subject:)` had to exist, and is a method rather than an initializer.**
  The plan did not anticipate it. A coordinator constructed in `.running` is *idle again* before any
  case begins, because opening the editor on a Recording is itself a selection change and ADR-0012
  cancels on one. Both the previews and the tests therefore need to set the phase after the surface
  exists. Debug-only, and the app's own path is still `export`.
- **`EditorWindowLifecycle` took the Export coordinator and kept `ActivationPolicyController.shared`.**
  The coordinator earns its injection: `EditorModel` now owns the instance every other surface
  renders, so a bridge cancelling whichever one `.shared` returned would be a cancel nobody could see.
  The activation controller is the app's own `.regular`/`.accessory` state, nothing renders it, and
  there is no second one to want — so §6's grep has exactly that one exemption, stated at the
  declaration.
- **The editor-level preview renders only its empty state.** §5's Phase 5 promised the whole window
  over a 44-Recording fake Library. With any rows in the sidebar the preview host dies inside
  SwiftUI's own outline diffing (`TableViewListCore_Mac2.swift:5538`, through
  `OutlineListCoordinator.recursivelyDiffRows` → `NSOutlineView.expandItem`) — measured with three
  rows in one day and twelve across three, listing before the view mounts and from its own `.task`.
  The running app renders that `List` fine and nothing here touches it. So the populated editor is
  previewed a component at a time: the lane ×3, the brief ×2 and the dock ×6, each verified in the
  canvas rather than by the compiler.
- **`Recording.stub` moved with no fallback needed.** The suite's 288 call sites are unchanged and the
  app's Release build carries none of it.

### What bit us, so it does not bite you again

- **Implicit member syntax does not work through an existential**: `capture: .capturing(recording)` is
  `type 'any CaptureState' has no member 'capturing'`. Spell the conformance out.
- **A default argument is evaluated in a nonisolated context** — the trap `LibraryStore` and
  `EditorModel` each have two initializers for. It bit twice more here, in a preview helper
  (`coordinator: ExportCoordinator = ExportCoordinator()`) and in `EditorModel.preview(recordings:)`,
  the second time only as a warning, which this repo treats as an error anyway. Two overloads, not a
  default.
- **A `#Preview` body compiles in Release**, so anything it touches that lives under `#if DEBUG` has to
  be guarded where it is *used* as well as where it is defined.
- **Adding any initializer to a class removes the implicit one**, which is how `static let shared =
  ExportCoordinator()` briefly stopped compiling. The `park` method avoids the question entirely.
- **A memberwise initializer survives `private` wrapped properties**: `EditorView(model:capture:)`
  compiles from another file even though every other stored property is `@State private`. The
  `TrimTimeline` call site had already proved this; it was worth not believing until the build said so.

---

## 0 · Four decisions to take before any code

### The name is `CaptureState`, and it is a noun on purpose

The five protocols this repo already has are gerunds — `Capturing`, `CaptureBuilding`,
`RunwayProbing`, `RunTelling`, `RecordingReading` — because each is a *doing* interface: something
performs an action on the run's behalf. This one is the opposite direction. The editor reads what
capture is doing and cannot command it (only `PanelView` and `MenuBarController` call `start`/`stop`),
so a gerund would misname it. `CaptureReading` is unavailable: it would sit one letter from
`RecordingReading`, which means *reads a Recording's facts off disk* and is a different thing
entirely. `CONTEXT.md` lists *capture* under _Avoid_ as a synonym for **Recording** — this names the
activity, which `CaptureRun` and `CaptureEngine` already do.

### `isStillArriving` becomes a protocol extension, not a requirement

Today the rule lives once, on `CaptureRun.swift:167` (`recording.isEmpty || isCapturing(recording)`),
and the five view sites are one-line forwards of it. That is worth saying plainly: the review's
"re-derived at five sites" is five forwards, not five copies, and this change must not turn them into
copies. A protocol *requirement* would do exactly that — every conformance, the preview stub included,
would restate the rule and nothing would check that they agreed. So it is a default implementation in
an extension, and **`CaptureRun`'s own copy is deleted**.

This is load-bearing rather than tidy: if the conformance keeps a member of the same name, calls on
the concrete type take the member and calls through `any CaptureState` take the extension, and issue
#80's two halves could then disagree by dispatch. `CaptureRunTests:450/452/456/544` call it on the
concrete run and keep passing through the extension.

### `CaptureRun` conforms, not `RecordingController`

The state's owner is the tested tier. `RecordingController` is the shell, and its editor-side forwards
exist only because the views reach for it — so they are deleted rather than retyped as a conformance.
Views are handed `RecordingController.shared.run`.

### The roots stay two, and the shell may still name a global

`AppTapeApp` (SwiftUI) and `AppDelegate` (AppKit) are two roots because ADR-0004 and ADR-0017 made
them two. A third object owning both would be a new global with a name nobody agreed to. The rule this
change enforces is narrower and checkable: **the view tier stops reaching; the shell is where globals
are named.** `EditorPresenter`, `ShellTelling` (`CaptureAdapters.swift:192`), `FaultNotifier` and
`AppDelegate` keep naming them, as ADR-0043 already decided for the telling adapter.

---

## 1 · Target shape

```
                    before                                          after

EditorView        ─┐                              AppTapeApp ─── EditorModel.shared
RecordingBrief     │                                   │      └── RecordingController.shared.run
LibraryRow         ├─▶ RecordingController.shared      ▼
ExportInspector    │   (15 members published,      EditorView(model:capture:)
TrimTimeline      ─┘    4 of them read)                │
                                                       ├─▶ RecordingBrief(recording:capture:)
ExportInspector ──▶ ExportCoordinator.shared           ├─▶ LibraryRow(recording:model:capture:)
                ──▶ ExportPreference.shared            ├─▶ TrimTimeline(…, capture:)
                ──▶ EditorModel.shared                 └─▶ ExportInspector(recording:capture:
                                                              preference:coordinator:
PanelView       ──▶ RecordingController.shared                correction:player:)
MenuBarController ▶ RecordingController.shared
LibraryRowCommands ▶ EditorModel.shared        AppDelegate ─── RecordingController.shared
                                                     ├─▶ MenuBarController(recorder:)
                                                     └─▶ PanelView(recorder:presenter:)

                              any CaptureState
                 elapsed · masterByteCount · isCapturing(_:)
                     + isStillArriving(_:), derived once
                                    │
                       ┌────────────┴────────────┐
                  CaptureRun                PreviewCapture
                  (production)              (#if DEBUG, the previews)
```

Two conformances, which is the bar `CaptureAdapters.swift:11-15` sets for an interface to exist here.
The panel and the status item get the concrete `RecordingController` instead, because their read
surface is nine and eleven members plus the two commands — an interface there would be a layer, not a
seam, and its only second consumer would be a preview the panel cannot have anyway until
`SourceModel`'s `NSWorkspace` scan has a seam of its own.

---

## 2 · The interface

New file **`AppTape/AppTape/CaptureState.swift`** — protocol, derived rule and conformance together,
so the seam is one file to read (`CaptureAdapters.swift`'s shape).

```swift
/// What the editor is allowed to know about the capture in flight.
///
/// Three reads and one derivation, which is the whole of what five views ask: the transport, the
/// brief, the sidebar row, the lane and the Export dock. Read-only by construction — `start` and
/// `stop` are the panel's and the status item's, and they hold the shell itself (ADR-0004).
///
/// A noun where this repo's other five protocols are gerunds, because those are *doing* interfaces
/// and this one is a reading. `@MainActor` is the target default (ADR-0022) and correct here: every
/// member is read from a view body.
@MainActor
protocol CaptureState {
    /// Master duration so far, published on the run's 4 Hz clock gate — 0 through the armed window
    /// before the first sound (ADR-0016). The sidebar row's live clock and the transport's readout.
    var elapsed: TimeInterval { get }

    /// What the master weighs **right now**, on the same 4 Hz gate (ADR-0031, ADR-0044). Nil before
    /// the first sound and at rest; a file merely arriving in the Library has no figure to be
    /// current about.
    var masterByteCount: Int64? { get }

    /// Whether this Recording is the one being written right now, and so not exportable (ADR-0012).
    func isCapturing(_ recording: Recording) -> Bool
}

extension CaptureState {
    /// Whether this Recording's audio is **still arriving** … (the doc moves here verbatim from
    /// `CaptureRun.swift:158-166`, issue #80 and ADR-0021 included).
    ///
    /// An extension rather than a requirement: the rule then exists exactly once and no conformance
    /// can hold a second opinion of it.
    func isStillArriving(_ recording: Recording) -> Bool {
        recording.isEmpty || isCapturing(recording)
    }
}

/// The production conformance. Every member is already there — `CaptureRun.swift:106`, `:113`, `:154`
/// — which is the sign the interface was cut in the right place.
extension CaptureRun: CaptureState {}
```

New file **`AppTape/AppTape/PreviewFixtures.swift`**, all of it inside `#if DEBUG` so nothing here
ships:

```swift
/// The second conformance, and the reason the protocol exists: capture states the real app can only
/// reach through Core Audio, a live tap and a Source making noise.
struct PreviewCapture: CaptureState {
    var capturingURL: URL?
    var elapsed: TimeInterval = 0
    var masterByteCount: Int64?

    func isCapturing(_ recording: Recording) -> Bool { capturingURL == recording.url }

    static let settled = PreviewCapture()
    static func capturing(_ recording: Recording, elapsed: TimeInterval = 93,
                          bytes: Int64 = 44_000_000) -> PreviewCapture
}
```

A `struct`, not an `@Observable` class: a preview does not change state, and a value that *states*
what capture is doing is the honest shape for one. The same file holds the `Recording` fixture and an
`Envelope` a lane can draw — see Phase 2.

---

## 3 · What each view accepts

Replace `@State private var recorder = RecordingController.shared` with `var capture: any
CaptureState` and rename the usages. `@State` is not carrying anything here: none of the five ever
writes to it, and each already holds non-`Equatable` class references (`Recording`, `AudioPlayer`), so
view diffing does not change either. `LibraryRow` (`EditorView.swift:727` `var model: EditorModel`)
and `TrimTimeline` (`:18-21`) are the precedent — this is the fifth property on `TrimTimeline` and the
only one it was creating.

| view | accepts | reads |
|---|---|---|
| `EditorView` | `model:` `capture:` | `isStillArriving` :478, `isCapturing` :530-531, `elapsed` :547/:562 |
| `RecordingBrief` | `recording:` `capture:` | `isStillArriving` :607, `isCapturing` :648, `masterByteCount` :649 |
| `LibraryRow` | `recording:` `model:` `capture:` | `isCapturing` :738, `isStillArriving` :739, `elapsed` :845 |
| `TrimTimeline` | `…` `capture:` | `isStillArriving` :50, `isCapturing` :55 |
| `ExportInspector` | `recording:` `capture:` `preference:` `coordinator:` `correction:` `player:` | `isStillArriving` :39, `isCapturing` :451, and the three singletons' members |
| `PanelView` | `recorder:` `presenter:` | the nine-member transport surface, `start(_:)` |
| `MenuBarController` | `recorder:` (init) | seven members, `stop()` |
| `LibraryRowCommands` | `model:` | `selection`, `renamingURL`, `beginRename`, `reveal`, `trash` |

`RecordingController` then loses five forwards: `masterByteCount`, `isCapturing`, `isStillArriving`
(now the interface's) and `currentLevel`, `capturingURL` (read by nothing). `elapsed` and `elapsedText`
stay — `MenuBarController:100/127` reads both.

The inspector's four singletons resolve without touching `EditorModel`'s `private init()`: it uses
only `editor.correction` (`:77`, `:190`, `:392`, `:408`, `:427`) and `editor.player.setGlobalGainDB`
(`:193`), so it accepts those two directly and the whole coordinator drops out of its interface.
`preference` needs write access — `:59` assigns `preset` and `:348` binds `$preference.normalizeLoudness`
— so it is `@Bindable var preference: ExportPreference` (concrete, not an existential; `@Bindable`
does not work through one).

---

## 4 · Implementation phases

### Phase 1 — the plan
Commit this file as `docs/plans/stop-the-views-reaching-through-to-singletons.md`. No open issue covers
candidate 3 (checked: #1, #70, #91, #127 are the open set).

### Phase 2 — `CaptureState`, and the five editor views accept it
- `CaptureState.swift` as §2. Delete `CaptureRun.isStillArriving` (`:158-169`), its doc moving to the
  extension.
- `RecordingController.swift`: delete the five forwards named in §3.
- The five views take `capture:`; `EditorView` passes it to `RecordingBrief` (`:383`), `LibraryRow`
  (`:79`), `TrimTimeline` (`:375`) and `ExportInspector` (`:336`); `AppTapeApp.swift:23` becomes
  `EditorView(capture: RecordingController.shared.run)`.
- `PreviewFixtures.swift`: `PreviewCapture`, plus **move `Recording.stub` here from
  `AppTapeTests/RecordingDoubles.swift`** so app-target previews and the suite share one definition —
  tests keep calling `Recording.stub(…)` unchanged (`@testable import`, and the scheme's test action
  builds Debug). If that proves awkward, the fallback is a separate `Recording.preview(…)` in the app
  target and the suite's `stub` left where it is. Add a hand-built `Envelope` (its stored arrays are
  settable; `Envelope.normalised` already exists) so a lane has something to draw.
- First two previews: `TrimTimeline` in three states (settled with an envelope, empty/arriving,
  capturing) and `RecordingBrief` in two (settled, capturing with a growing size).

### Phase 3 — `EditorModel` accepts its world
- `init(store:player:correction:coordinator:preference:)` plus `convenience init()` for the production
  wiring — `LibraryStore.swift:38-58`'s exact shape, including why it is two initializers rather than
  one with defaults.
- `coordinator` and `preference` become accepted collaborators. The coordinator is already used here
  (`:65`, `:119`); the preference belongs for the same reason `correction` does — ADR-0017 reuses the
  window, so the editor's state cannot live in a view.
- `EditorView(model:capture:)`, `LibraryRow(recording:model:capture:)`,
  `LibraryRowCommands(model:)`; `EditorWindowLifecycle`'s `.editorActivationPolicy()` takes the
  coordinator so `windowWillClose`'s ADR-0012 cancel is not a global read.
- `AppTapeApp` names `EditorModel.shared` and `RecordingController.shared.run` once each, in the scene
  body. `EditorPresenter` keeps `EditorModel.shared` — it is shell, and the shell is where a global is
  named.

### Phase 4 — the inspector accepts its four collaborators
`ExportInspector(recording:capture:preference:coordinator:correction:player:)`, fed from
`EditorView`'s injected model at `:336`. `editor.correction` → `correction`, `editor.player` →
`player`. Then its preview: idle, running, succeeded, failed, refusing (nothing in the Trim), and
capturing — six states, none of which can be seen today without an actual Export.

### Phase 5 — the tests the seam buys, and the fake-Library preview
`EditorModel` has no tests and holds `reconcileSelection` (`:111-134`), which is ADR-0021's mechanism.
With `init(store:player:…)` and the suite's existing `StubRecordingReader` + `Recording.stub`, these
become writable with no disk:
- a pending URL is selected once it lists, and only once;
- the open Recording re-adopted rebinds the selection to the fresh object (`current !== selection`);
- the open Recording vanishing bumps `vanishedTick`, stops the player and cancels the Export;
- an empty Library does **not** bump `vanishedTick` (the distinction `:28-30` documents);
- the newest Recording is selected on first open, and not re-selected after the user picks another;
- selecting a different Recording cancels a running Export; re-selecting the same one does not
  (`:62-65`).
Then `#Preview { EditorView(model: …, capture: …) }` over a stub reader holding ~44 stub Recordings —
a fake Library, no disk, no Core Audio, replacing the live one at `EditorView.swift:950`.

### Phase 6 — the panel and the status item
`PanelView(recorder:presenter:)` and `MenuBarController(recorder:)`, wired from `AppDelegate` (`:14`,
`:21`, `:38`) and `MenuBarController.swift:227`'s `NSHostingController(rootView:)`. Concrete, not an
interface — §1's reason. `PanelView.swift:50`'s `EditorPresenter.shared.bind(openWindow)` becomes
`presenter.bind(openWindow)`. `PanelView`'s `@State private var model = SourceModel()` stays: it is a
view creating state, but not a singleton, and the seam under it is `NSWorkspace`'s, not this change's.

### Phase 7 — the record
`docs/adr/0045-…md` — **0045 is the next free number.** Follow ADR-0043 and ADR-0044's shape: an H1
that is a declarative sentence, unlabelled context prose, `## Consequences` naming what pins each one,
`## Considered and rejected`. What is a decision rather than a refactor: the four in §0; that the
payoff is previews and a stated boundary rather than view tests, and ADR-0018 is why; that the panel
and the status item got the shell concretely; and the two members nobody was reading. Amend ADR-0043's
"The views were left alone" bullet in place to point here, the way ADR-0022's last bullet was edited to
say "closed by ADR-0043". Set this plan's front-matter to `delivered` and add the `As built` sections.

---

## 5 · Behaviour that must not change

No test can catch a regression in this tier — that is the condition being worked on — so this is the
review checklist.

| Behaviour | Why it is fragile |
|---|---|
| Nothing re-renders more often than it does today | observation must still track through to `CaptureRun`'s stored properties; reading through `any CaptureState` calls the same getter, but a snapshot `struct` handed to the *views* would break it |
| `MenuBarController`'s `withObservationTracking` still re-arms on the same five members | Phase 6 changes how it gets the object, never what it reads (`:125-130`) |
| `elapsed` and `masterByteCount` still publish at 4 Hz, the meter at 20 Hz | ADR-0043's cadence split, ADR-0028's ban on ambient motion |
| `isStillArriving`'s two halves both survive | zero frames alone did not catch issue #80's stretched slab |
| `correctionKey` keeps `isStillArriving` as a **key component**, not a guard | `ExportInspector.swift:67-71`: Stop has to be a key change or the figure never arrives |
| ADR-0031's four surfaces keep their figures | sidebar clock, brief's `Master`/`Captured`, the Export ladder, the ruler |
| `preference` writes still reach `UserDefaults` | the `$` binding at `:348` and the assignment at `:59` |
| The editor window gets the **same** `EditorModel` across open/close cycles | ADR-0017: the window is reused, and a fresh model per open would lose the selection |
| `sincePress` stays the shell's, computed from `ProcessInfo` | ADR-0043: the run reads no clock |
| The panel still raises itself on a blocking message, and Escape still belongs to the app | `MenuBarController:147`, ADR-0011 |

---

## 6 · Verification

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```
288 cases plus Phase 5's, green, with no new warning in either target. New files under
`AppTape/AppTape/` and `AppTape/AppTapeTests/` join their targets automatically
(`PBXFileSystemSynchronizedRootGroup`).

**The acceptance criterion that is a grep, because it cannot be a test:**
```
grep -n "\.shared" AppTape/AppTape/{EditorView,ExportInspector,TrimTimeline,PanelView,EditorWindowLifecycle}.swift
```
leaves only AppKit's own (`NSWorkspace.shared`, `NSApplication.shared`). `AppTapeApp.swift` and
`AppDelegate.swift` are the two places an app singleton is named.

**Previews** (`mcp__xcode__RenderPreview`, or the canvas): each new `#Preview` renders with no Library
folder and no Core Audio. Check the states that were unreachable — the brief reading "44 MB and
growing", the lane saying "Still capturing" versus "No audio yet", the dock refusing with "This
Recording is still capturing", the four Export phases at one height (ADR-0012).

**By hand, once, after Phase 6** — the parts no test and no preview can stand in for: record → the
sidebar row's clock ticks and its silhouette stays hidden, the `Master` row counts up at 4 Hz, the
status item clocks and the panel's pressed row meters; stop → the editor opens on the new Recording;
Export → runs, and cancels when the window closes; the normalize Toggle survives a relaunch;
File ▸ Rename / Reveal / ⌘⌫ still act on the sidebar's selection.

---

## 7 · Out of scope

- **Candidates 4, 5 and 6** (the dock's refusal, the timeline's two mappings, the format's four
  renderings). Each is a pure decision inside a view body and each gets easier once the view accepts
  its state, which is the sense in which this unblocks them. `ExportInspector.refusal` (`:471-480`) is
  deliberately left exactly as found.
- **A seam under `SourceModel`'s `NSWorkspace` scan.** It is what panel previews would additionally
  need, and it is a different finding.
- **`ExportCoordinator(preference:)`** (`ExportCoordinator.swift:97` reaches
  `ExportPreference.shared`). A non-view leak, and injecting it buys little while the save panel keeps
  the instance untestable (`ExportCoordinatorTests` says so at `:9-13`).
- **View tests.** ADR-0018 has no UI layer and this change does not propose one.
- **`LibraryStore.reconcile`'s four `stat`s per url**, left as found by ADR-0044 for reasons that still
  hold.
- **The layout numbers outside `Metrics`** and the six bare `"—"` literals (review candidate 6's
  "smaller kin"). Not this change's business, even though this change touches the same lines.

---

## 8 · Size

| Phase | Files | Net lines |
|---|---|---|
| 1 · the plan | +1 | +~300 |
| 2 · `CaptureState` + the five views + the stub | +2 ~4 | +180 |
| 3 · `EditorModel` accepts its world | ~4 | ±60 |
| 4 · the inspector's four collaborators + its preview | ~2 | +60 |
| 5 · `EditorModel`'s first tests + the fake-Library preview | +1 ~2 | +180 |
| 6 · the panel and the status item | ~4 | ±30 |
| 7 · the record | +1 ~3 | +90 |

Roughly +600 lines, of which ~300 are tests, previews and the stub. Two of the twelve coordinating
modules gain a seam (`EditorModel`, and the view tier's read of `CaptureRun`); nine still have none,
and the argument for each of them is this one.

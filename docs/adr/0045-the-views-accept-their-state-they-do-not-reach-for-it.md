---
status: accepted
---

# The views accept their state; they do not reach for it

Nine lines across seven view types read an app singleton out of thin air. Five of them were
`@State private var recorder = RecordingController.shared`; four more were `EditorModel.shared`,
`ExportPreference.shared` and `ExportCoordinator.shared`, the last three of them consecutive lines at
the top of `ExportInspector`. ADR-0043 left them there deliberately — *"Moving them onto an injected
interface is a separate change with a separate argument"* — and this is that argument.

The cost was not coupling in the abstract. It was that **no view could be rendered without the real
world behind it**. There was exactly one `#Preview` in the app, `EditorView()`, and it took no
parameters, so it bound to `EditorModel.shared` — which lists the real Library folder — and to
`RecordingController.shared`, which builds a `CoreAudioCaptureBuilder`, a `statfs` probe and a
notification centre. `ExportInspector`, `TrimTimeline` and `RecordingBrief` had no preview at all:
each needed a live capture controller, and the inspector also needed an `EditorModel`, whose `init()`
was `private`. So the states this app is mostly *about* — a Recording still arriving, a master growing
on disk, an Export running, an Export refused — could be looked at only by recording something and
watching it happen.

**The decision: a view is handed what it renders. The two roots name the app's singletons, once each,
and nothing below them reaches.** `AppTapeApp` names `EditorModel.shared` and
`RecordingController.shared.run` for the SwiftUI side; `AppDelegate` names the transport and the
presenter for the AppKit side. The editor reads capture through one small interface,
`CaptureState`; every other collaborator is passed as itself.

## Consequences

**`CaptureState` is three reads and one derivation, and the editor cannot command capture.** `elapsed`,
`masterByteCount`, `isCapturing(_:)`, plus `isStillArriving(_:)` derived in an extension. Five views
asked for exactly this and nothing else, which is why the interface is small enough to be worth
having: the shell publishes fifteen members and the editor reads four of them. `start` and `stop`
are absent by construction, not by convention — they belong to the two surfaces that press them.

**The name is a noun where this repo's five other protocols are gerunds.** `Capturing`,
`CaptureBuilding`, `RunwayProbing`, `RunTelling` and `RecordingReading` are all *doing* interfaces:
something acts on the run's behalf. This one is a reading in the other direction. `CaptureReading` was
the gerund available and was rejected for sitting one letter from `RecordingReading`, which means
*reads a Recording's facts off disk* (ADR-0044) and is a different thing entirely.

**The arriving rule moved to the protocol extension, and that is what keeps it one rule.** As a
protocol *requirement*, `isStillArriving` would have been restated by every conformance with nothing
checking that they agreed — and a conformance that kept a member of that name would be reached by
calls on the concrete type while calls through `any CaptureState` took the extension. Issue #80's two
halves (`recording.isEmpty || isCapturing(recording)`) now exist in exactly one place, and
`CaptureRun`'s copy is gone.

**`CaptureRun` conforms, not `RecordingController`.** The state's owner is the tested tier; the shell's
forwards existed only because the views reached for it. Five of them are deleted — three the interface
carries, and `currentLevel` and `capturingURL`, which **nothing in the app was reading**. A forward
added back there for the editor's benefit is a reach-through with an extra step in it.

**The panel and the status item were handed the shell concretely, and that is not an inconsistency.**
They read nine and seven members between them and are the only two surfaces that command capture. An
interface over that surface would have one production conformance, a branch of its own, and a second
conformance whose only consumer is a preview — which is ADR-0043's definition of a layer rather than a
seam. They are capture's own face; the editor is a reader of it.

**`EditorModel` accepts five collaborators and got its first nine tests.** Store, player, correction,
Export coordinator and preference. The coordinator was already being reached for twice *inside* the
model, so accepting it removed a global read as well as enabling the tests; the preference sits there
for the same reason `correction` does — ADR-0017 reuses the window, so editor state cannot live in a
view. The nine cases are over `reconcileSelection`, which is ADR-0021's mechanism and had nothing
holding it: a pending selection spent exactly once, the re-adopted Recording rebinding to the fresh
object, the vanish that closes the window versus the empty Library that must not, and ADR-0012's
cancel on navigating away versus the re-selection that must leave a finished telling standing.
Verified by mutation: dropping the `current !== selection` rebind fails exactly the re-adoption case,
and dropping the vanish cancel fails exactly the vanish case.

**The window-lifecycle bridge takes the Export coordinator but keeps `ActivationPolicyController`.**
The coordinator matters because `EditorModel` now owns the instance every other surface renders, and a
bridge cancelling whichever one `.shared` returned would be a cancel nobody could see. The activation
controller is the app's own `.regular`/`.accessory` state: nothing renders it, and there is no second
one for a preview or a test to want.

**Eleven previews where there was one, and they are the second conformance that justifies the
interface.** `PreviewCapture` is a `struct` — a preview does not change state, and *what capture is
doing at this instant* is a value. The lane draws a synthesized envelope and says "Still capturing"
with no tap; the brief reads "44.6 MB and growing" with no file; the dock's four Export phases render
at the one declared height (ADR-0012) with no save panel, which is how issue #78's moving dock got
shipped in the first place. `ExportCoordinator.park(in:subject:)` is what parks a phase, and it is a
method rather than an initializer because both callers need it *after* the surface exists: opening the
editor is itself a selection change, which cancels, so a coordinator born running is idle before the
case begins.

**The editor-level preview renders only its empty state, and that is a framework limit, not a
shortfall of the seam.** With any rows in the sidebar the preview host dies inside SwiftUI's own
outline diffing — `TableViewListCore_Mac2.swift:5538`, through
`OutlineListCoordinator.recursivelyDiffRows` → `NSOutlineView.expandItem` — with three rows in one day
as surely as with twelve across three days, and whether the store lists before the view mounts or from
the view's own `.task`. The running app renders that `List` correctly and this change does not touch
it. So the populated editor is previewed one component at a time.

**`Recording.stub` moved into the app target under `#if DEBUG`.** One definition of "an ordinary
Recording", shared by the previews and the 288 cases that already used it, rather than two that drift.
Nothing about its call sites changed.

**What a `.shared` in a view file may now be.** AppKit's own — `NSWorkspace`, `NSApplication` — and
nothing else. That is a grep, and it is the only enforcement this has: no test can stand here, because
ADR-0018 has no UI layer and this change does not propose one. Which is the honest summary of the
whole thing: it buys previews, one root per side, and an interface that states what the editor may
know — not test coverage of the views.

## Considered and rejected

**One interface for all five views**, as the review sketched it. The editor's four members and the
transport's eleven do not intersect: `isCapturing(_:)` takes a Recording, which the panel does not
have, and `sincePress` needs the clock read the shell owns. One interface would have been the union,
which is the shell's whole surface with extra steps.

**A `Transport` protocol for the panel and the status item**, so the panel's five unpreviewable states
could be rendered. Rejected on ADR-0043's bar, and because it would not have been enough on its own:
`PanelView` also creates its own `SourceModel`, which scans `NSWorkspace`, so previewing the panel
needs a seam this change does not have an argument for.

**Handing the inspector the whole `EditorModel`**, which is the shape `LibraryRow` already has. It was
reaching through the model for exactly two things — the correction and the player — so it takes those,
and the dock's interface now says what the dock may touch. This also kept the inspector's phase
independent of `EditorModel`'s.

**A composition object owning both roots.** The two roots are AppKit's and SwiftUI's because ADR-0004
and ADR-0017 made them two. A third object owning both would be a new global with a name nobody agreed
to, and it would name the same singletons the same number of times.

Prompted by the architecture review of 12 September 2026, candidate 3.

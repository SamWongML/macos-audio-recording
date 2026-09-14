---
status: delivered
source: architecture review, 12 Sep 2026 — candidate 4, "The Export dock's refusal is a view property"
record: docs/adr/0046-an-export-refuses-once-and-both-callers-ask.md
---

# Decide an Export's refusal once

## Context

Whether an Export may start is a pure, ordered decision. It was written out in **four places, in three
vocabularies, with three different strings, and tested nowhere** — and two of its rules were not rules
at all, only side effects of arithmetic in other files.

| rule | the view | the coordinator | the encoder |
|---|---|---|---|
| the file can't be decoded | not checked — enforced structurally, `EditorView.swift:336` declines to render the whole column (ADR-0034) | **absent**; protected only by `frameCount == 0` | — |
| the Recording is being captured | `ExportInspector.swift:461-465` — `This Recording is still capturing.` | **absent** | — |
| the Trim holds nothing | `:486` — `Nothing in the Trim to export.`, in **seconds** | `ExportCoordinator.swift:94-98` — `There is nothing in the Trim to export.`, in **frames** | `ExportEncoder.swift:67,73,85` — a third copy of the sentence |
| the Quality Preset can't encode this file | `:487` — `This quality can't encode this file.` | `:99-107` — `encodability.reason ?? "This quality can't encode this file."` | — |
| an Export is already running | `:488` — `An Export is already running.` | `:92` — `guard case .idle`, a **silent** return | — |
| an adopted file with no audio | unstated — falls into the Trim rule only because `Trim(duration: 0).length == 0` | same, via `trimmedFrameRange == (0, 0)` | — |

Three consequences, all live:

1. **The wording had already diverged** — `Nothing in the Trim…` against `There is nothing in the
   Trim…`, twice.
2. **The units disagreed, and the disagreement was reachable.** `Recording.stub(seconds: 0,
   storedTrim: Trim(duration: 90))` gives `trimmedDuration == 90` with `trimmedFrameRange == (0, 0)`:
   the dock offered `Export…`, the click reached the coordinator, and the user got a **failure
   telling** where ADR-0042 promised a sentence. Frames is the correct unit — it is what the encoder
   reads.
3. **The coordinator's own comment was untrue.** `ExportCoordinator.swift:99-101` called itself *"the
   belt-and-suspenders gate so no caller can bypass it"*; it had no opinion on two of the six rules.

ADR-0045 was the precondition — the dock now *accepts* `capture`, `preference`, `coordinator`,
`correction` and `player` rather than reaching for them, so the decision had nameable inputs for the
first time. Candidate 3's plan left this one alone on purpose: *"`ExportInspector.refusal` is
deliberately left exactly as found."*

### What was checked and found **not** duplicated

- **`QualityPreset.encodability(for:)`** — already one pure function with 8 test cases. The
  unencodable rule consumes it; it is not restated.
- **`QualityPreset.PresetPick`** — the precedent this change follows: a pure decision lifted out of
  the inspector's binding *because* it could then be tested.
- **`isStillArriving`** — already derived once (`CaptureState.swift:59`); its ten view-side reads are
  forwards, not copies. ADR-0045 settled that.
- **`ExportSizeEstimate`, `DiskSpace.hasRoom`, `Trim`** — each already the one place that knows its
  own rule.

---

## As built

Green at every step. The suite went from **297 cases to 313**, and the test target's
`#IsolatedConformances` warning count went **down** from 73 to 48.

| file | change |
|---|---|
| `ExportReadiness.swift` | **+124, new**: the enum, five `Reason` cases, `sentence`, `symbolName`, `refusal`, `evaluate` |
| `ExportReadinessTests.swift` | **+138, new**: 10 cases over a decision that had none |
| `ExportInspector.swift` | +56/−30: `readiness` replaces `refusal` and `effectiveEncodability`; `dockSentence` takes a `Reason`; two new previews |
| `ExportCoordinator.swift` | +27/−15: `export(recording:preset:capture:)`, one readiness gate replacing two guards |
| `ExportCoordinatorTests.swift` | +95: a nested `@MainActor struct Refusals` with 6 cases |
| `ExportEncoder.swift` | +4/−1: `Failure.emptyRange` sources the app's one wording |
| `QualityPreset.swift` | +8/−1: `nonisolated enum QualityPreset` |
| `.gitignore`, `AppTape/default.profraw` | +3/−1 file: a 0-byte tracked coverage artefact, and the rule that stops the next one |

Four things differ from the plan below, each because writing the code showed the plan was wrong.

- **The isolation fix landed on `QualityPreset`, not on `SourceFormat`.** The plan predicted the
  checkpoint and guessed the wrong type. `nonisolated struct SourceFormat` did not clear the warning
  and neither did `nonisolated enum Encodability`; the method itself was main-actor because
  `Sendable` does not lift a type's *members* out of ADR-0022's default. Marking the whole enum is
  both the fix and the honest annotation — nothing in it touches UI or disk, and `ExportEncoder`
  already read it from a `.utility` queue. It also removed 25 pre-existing warnings from the suite.
- **The `.unopenable` rule was found during planning, not in the review.** The review listed four
  rules; the map found six. `EditorView.inspectorColumn` was enforcing the can't-decode rule
  structurally and the coordinator was enforcing it only by arithmetic — and the arithmetic case that
  breaks it (`isOpenable: false` with a positive frame count) is now a test.
- **`ExportCoordinatorTests` gained a nested suite rather than a `@MainActor` on the whole file.** The
  existing three cases are nonisolated file-handling tests and had no reason to move onto the main
  actor; `ExportCoordinatorTests/Refusals` carries the annotation instead.
- **The preview for `already running` parks on a synthetic third URL.** `park(in:subject:)` already
  existed (ADR-0045 added it); what the plan did not say is that reaching this refusal needs a subject
  that is *neither* the rendered Recording nor nil, which is exactly issue #127's shape.

### What bit us, so it does not bite you again

- **`Sendable` is not `nonisolated`** under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A `Sendable`
  type's members can still be main-actor isolated, and *which ones are* depends on their signatures —
  `fileFormat(for:)` was fine and `encodability(for:)` was not, in the same enum, with nothing in the
  source to tell them apart. Only the compiler knows; mark the type.
- **SourceKit's live diagnostics are useless for a brand-new file in a synchronized group.** Every
  type in the file reads as *"cannot find type in scope"* until a build re-indexes. `xcodebuild` is
  the authority; ignore the editor until it agrees.
- **Count the baseline warnings before you change isolation.** 73 `#IsolatedConformances` warnings
  pre-existed on a clean tree. Without that number, the 48 remaining after this change would have
  looked like 48 new ones.

---

## 0 · Four decisions taken before any code

### The name is `ExportReadiness`, and the outcome type *is* the module

`enum ExportReadiness { case ready; case refused(Reason) }` with a nested `Reason` and a static
`evaluate`. This is `QualityPreset.Encodability`'s exact shape and `RowRecordGlyph`'s exact idiom — a
pure namespace over scalars with a factory and derived presentation helpers, unit-tested in full.
`DiskGuardRefusal` and `PermissionRecovery` are the precedent for refusal copy pinned by a test rather
than buried in a view. `CONTEXT.md` has no term for *refusal* and this does not coin one: **Export** is
the term, and readiness is a property of it.

### Frames, never seconds

`trimmedFrameCount` is what the encoder reads and what consequence 2 above is about.

### `.unencodable` carries the specific reason; `sentence` prints the generic line

ADR-0042 argues the split — *"the dock names the situation and leaves the specifics to the rung"* —
because ADR-0041 states the rung's own reason at full strength beside it. Carrying the payload means
the coordinator's `encodability.reason` is not thrown away.

### `.unopenable` has a sentence no surface renders

ADR-0034 removed `AppTape can't decode this file` from the column on purpose, and
`EditorView.inspectorColumn` implements that by not rendering the dock at all. The case exists so the
coordinator's gate has something to present rather than returning silently, and its sentence is the
exact string ADR-0034 measured and removed.

---

## 1 · Target shape

```
                    before                                     after

ExportInspector.refusal          ExportInspector ─ renders ──┐
  3 rules, seconds, 0 tests                                  │
  + a 4th inline at :461         ExportCoordinator ─ refuses ┤
                                                             ▼
ExportCoordinator.export                            ExportReadiness
  2 of the 6 rules, frames,                    .ready | .refused(Reason)
  0 tests, 1 silent return                              │
                                    ┌───────────────────┴──────────────────┐
ExportEncoder.Failure.emptyRange   .unopenable · .stillCapturing · .emptyTrim ·
  a 3rd copy of one string          .unencodable(String) · .alreadyRunning
                                          each with .sentence, .symbolName
                                                       │
                                        ExportEncoder.Failure.emptyRange
                                          reads .emptyTrim.sentence
```

Six inputs, and they are the honest six — the review's list, corrected by the map:

| input | why not the review's version |
|---|---|
| `isOpenable` | absent from the review entirely |
| `isCapturing` | the review folded this into `isStillArriving`; it must **not** be, or an empty adopted file (for which `isStillArriving` is true) would be told *"This Recording is still capturing."* about a file nothing is capturing |
| `trimmedFrameCount` | the review said `trimmedDuration`; frames is what the encoder reads |
| `preset` + `format` | the review said `SourceFormat` alone; `encodability` needs both, and the *effective* preset is the view's per-file display-over, not the sticky |
| `isExporting` | unchanged |

---

## 2 · The module

`AppTape/AppTape/ExportReadiness.swift`, `nonisolated` like `Trim` (ADR-0022) so
`ExportEncoder.Failure.description` can read `emptyTrim.sentence` from a `.utility` queue.

```swift
nonisolated enum ExportReadiness: Equatable {
    case ready
    case refused(Reason)

    enum Reason: Equatable {
        case unopenable
        case stillCapturing
        case emptyTrim
        case unencodable(String)
        case alreadyRunning

        var sentence: String     // ADR-0042's table, verbatim
        var symbolName: String   // record.circle for .stillCapturing, square.and.arrow.up otherwise
    }

    var refusal: Reason? { … }

    static func evaluate(isOpenable: Bool, isCapturing: Bool, trimmedFrameCount: Int64,
                         preset: QualityPreset, format: SourceFormat,
                         isExporting: Bool) -> ExportReadiness
}
```

Rules in declaration order; first match wins.

## 3 · The three call sites

**`ExportInspector`** gets a computed `readiness`. `exportControl` keeps its exact precedence — the
still-capturing branch still wins over the `subjectURL` phase switch — but the branch no longer carries
a sentence, only the ordering:

```swift
if case .refused(.stillCapturing) = readiness { dockSentence(.stillCapturing) }
else if coordinator.subjectURL == recording.url { switch coordinator.phase { … } }
else { exportControlOrRefusal }
```

with `exportControlOrRefusal` becoming `if let reason = readiness.refusal { dockSentence(reason) }
else { exportButton }` and `dockSentence(_ reason:)` reading both halves off the reason. Deleted:
`refusal`, `effectiveEncodability`, and `dockSentence(_:icon:)`'s two-argument form.

**`ExportCoordinator`** becomes `export(recording:preset:capture: any CaptureState)` — `capture` at the
call site, not at `init`, because `static let shared = ExportCoordinator()` would otherwise name
`RecordingController.shared.run` at static-init time and cost the dock previews and `EditorModelTests`
the bare coordinator they all build. `guard case .idle` **stays and is not `.alreadyRunning`**: it also
guards `.succeeded`/`.failed`, which are tellings awaiting dismissal, and the retry path depends on
that difference.

**`ExportEncoder`**: `case .emptyRange: return ExportReadiness.Reason.emptyTrim.sentence`. The
`frameCount > 0` guard stays — it is the off-main last word and the only gate a direct `ExportRequest`
caller meets.

---

## 4 · Phases

1. **The plan and the ticket.**
2. **The module and its tests, with nothing calling it** — green on its own, which is the point of the
   ordering: the decision gets tested before it gets moved.
3. **The dock renders it**, plus two previews that had never been renderable: `refused · unencodable`
   (ADR-0041 needed a doctored Library and a `defaults write` for it) and `refused · already running`
   (#127's state, never seen).
4. **The coordinator refuses on it; the encoder speaks one wording**, plus six coordinator cases that
   could not exist before, using `PreviewCapture` — the app target's `#if DEBUG` `CaptureState`
   conformance, until now unused by the suite.
5. **Blast-radius cleanup**: `AppTape/default.profraw` and a `.gitignore` rule.
6. **The record**: ADR-0046, and ADR-0042 amended in place — its table goes from three sentences to
   five, and its still-capturing note gains a line saying the two idioms are one call now.

---

## 5 · Behaviour that must not change

ADR-0018 has no UI test layer, so the dock's render is a review checklist, not a test.

| behaviour | why it is fragile |
|---|---|
| the dock keeps one declared height across all nine states | `.frame(height: exportControlHeight)` sits on the `.safeAreaBar` wrapper, **outside** `exportControl`, so this holds by construction — a pixel diff at `1200 × 680` should still be confined to the control's own box (ADR-0025, ADR-0042) |
| the sentence always says *something* | ADR-0042: an empty slot collapses the dock |
| still-capturing still wins over a matching `subjectURL` | a capturing Recording must never render a phase control |
| `guard case .idle` still swallows during `.succeeded`/`.failed` | the retry button's `cancel()`-then-`export()` depends on it |
| the rungs still state their own specific reasons at full strength | ADR-0041 — the generic dock sentence is only correct *because* the rung is specific |
| an unencodable rung still states no size | ADR-0031/-0041 |
| the dock sentences stay in ink | ADR-0042 measured `.secondary` at 3.89 : 1 in Light |
| `effectivePreset`, not `preference.preset`, feeds the encodability rule | the per-file display-over (ADR-0015) is what the dock is refusing about |
| `.motion` stays keyed on `coordinator.phase` only | a refusal changing does not cross-fade today and must not start (ADR-0028) |
| the save panel still never opens on a refusal | every coordinator guard precedes `presentSavePanel` |

## 6 · Verification

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```
**313 cases, green.** New files under `AppTape/AppTape/` and `AppTape/AppTapeTests/` join their targets
automatically (`PBXFileSystemSynchronizedRootGroup`); no pbxproj edit.

**The acceptance criterion that is a grep, because it cannot be a test** — one wording, one place:
```
grep -rn "nothing in the Trim\|can't encode this file\|already running\|still capturing\|can't decode" \
  AppTape/AppTape --include="*.swift"
```
Every surviving hit is a comment, a `#Preview` name, or `EditorView`'s `cantOpenDetail` copy — which is
the detail pane speaking, and ADR-0034 is why that one is a different sentence on a different surface.
The only **string literals** for these five facts are in `ExportReadiness.swift`.

**Previews**: the four renderable refusals beside the four Export phases, all at one height.

**By hand, once**: export a normal Recording end to end; drag the Trim to its minimum and back; pick an
unencodable rung on a 96 kHz adopted file and confirm the dock's generic sentence sits below the rung's
specific one; start a Recording and confirm the dock refuses it; drop a `.wma` in the Library and
confirm the column is still blank (ADR-0034) rather than newly explaining itself.

## 7 · Out of scope

- **Issue #127's fix** — `subjectURL` following a relocate is the coordinator's *identity*, not this
  decision. `.alreadyRunning` being a named case is what #127 will need in order to delete it cleanly.
- **Review candidates 5 and 6** — the timeline's two pixel↔time mappings; the six bare `"—"` literals
  and the four repeated `isStillArriving` gates in the inspector.
- **`ExportCoordinator(preference:)`** — still a non-view leak, still not worth it while the save panel
  keeps the instance untestable. ADR-0045 scoped it out.
- **The disk pre-flight's refusal.** It refuses *after* the save panel, against a destination volume, on
  an input none of these six scalars carry.

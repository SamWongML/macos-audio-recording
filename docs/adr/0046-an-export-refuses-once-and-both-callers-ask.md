---
status: accepted
---

# An Export refuses once, and both callers ask

Whether an Export may start was a pure, ordered decision written out in four places. `ExportInspector`
held a three-rule `refusal` computed property plus a fourth rule inline one function up;
`ExportCoordinator.export` held two of those rules with wordings of its own, and a third as a silent
`return`; `ExportEncoder.Failure` held a third copy of one of the sentences; and two further rules
were not written anywhere — an adopted file with no audio in it was refused only because
`Trim(duration: 0).length` happens to be 0, and a file the decoder cannot open only because
`EditorView.inspectorColumn` declines to render the pane at all.

Nothing tested any of it, because none of it was reachable without a window.

The wording had already drifted — `Nothing in the Trim to export.` against `There is nothing in the
Trim to export.` — and so had the **unit**: the dock tested `trimmedDuration` in seconds where the
coordinator tested `trimmedFrameRange` in frames. That is not a tidiness complaint. A Recording whose
Trim is `isFixed` can report a positive length in seconds with zero frames behind it, and for that
Recording the dock offered an `Export…` button whose click produced a *failure telling* — where
[ADR-0042](0042-the-dock-states-the-refusal-it-does-not-wear-one.md) promises a sentence.

**The decision: one module holds all five rules, in one order, with one set of wordings.
`ExportInspector` renders its reason; `ExportCoordinator` refuses on it; `ExportEncoder` speaks its
sentence.** `ExportReadiness.evaluate` takes six scalars — `isOpenable`, `isCapturing`,
`trimmedFrameCount`, the preset, the `SourceFormat`, `isExporting` — and returns `.ready` or
`.refused(Reason)`. No `Recording`, no file, no AppKit, no actor.

## Consequences

**The unit is frames, and the seconds test is gone.** Frames are what the encoder reads. This is the
one user-visible fix in the change: the Recording described above is now refused with a sentence
rather than offered a button that fails.

**Two rules that were accidents are now rules.** An adopted file with no audio reaches `.emptyTrim`
because the rule says so, not because of an invariant three files away. A file the decoder cannot
open reaches `.unopenable` **first** — ahead of everything else, with a positive frame count, which
is the case the old arrangement could not have survived: it was told *"Nothing in the Trim to
export."* for the wrong reason whenever it was told anything at all.

**The coordinator gained two rules it never had**, and its own comment is true for the first time.
It called itself *"the belt-and-suspenders gate so no caller can bypass it"* while having no opinion
on either. It now refuses a Recording still being captured — which
[ADR-0012](0012-export-is-non-blocking-and-cancels-on-navigation.md) forbids exporting and only the
dock was enforcing — and one the decoder cannot open.

**`.unopenable` carries a sentence no surface renders, and that is deliberate.**
[ADR-0034](0034-an-empty-state-is-spoken-once.md) took `AppTape can't decode this file` *out* of the
trailing column — *"the trailing column holds the Export ladder or nothing, and never explains
itself"* — and `EditorView.inspectorColumn` implements that by not rendering the dock for such a
Recording, so neither a refusal nor a failed telling has anywhere to appear. The case exists so the
coordinator's gate has something to present rather than returning silently, and the sentence kept is
the exact one ADR-0034 measured and removed, against that ADR's own closing note that *"a fourth pane
could re-open this"*.

**`.unencodable` carries the rung's specific reason and prints the generic line.** ADR-0042's trade is
that the dock names the situation and leaves the specifics to the rung, because
[ADR-0041](0041-the-reason-is-not-part-of-the-control.md) already states
`AAC can't encode above 48 kHz — this file is 96 kHz.` beside it at full strength. The coordinator used
to print the specific reason instead; it now prints what the dock prints, and the specific reason
rides in the case's payload rather than being discarded.

**`guard case .idle` stayed, and is not the one-at-a-time rule.** It also holds a `.succeeded` or
`.failed` telling in place until it is dismissed, which is what the inspector's `Retry…` relies on —
it calls `cancel()` first. `.alreadyRunning` is the separate rule, and in the dock it is reachable
only through [#127](https://github.com/SamWongML/macos-audio-recording/issues/127)'s rename.
*(Amended by [ADR-0048](0048-an-exports-subject-is-the-recording-not-its-path.md): #127 closed that
route and the case was kept, for the compound one that survives it. The claim that the coordinator
reaches it as "the plain one-at-a-time rule" was never true — `guard case .idle` returns first.)*

**`Reason` owns its SF Symbol, so the dock draws every refusal through one call.** The still-capturing
sentence needed a branch of its own in `exportControl` purely because its glyph differed;
`RowRecordGlyph.symbolName` is the precedent for a pure module owning a name. ADR-0042's rule that the
glyph keeps no colour of its own is untouched — this moves a name, not a treatment. The one thing
that branch still does is **outrank the phase switch**: a Recording being written must never render a
progress bar, whatever `subjectURL` says.

**`capture` is a parameter of `export(recording:preset:capture:)`, not a stored dependency.** The
still-capturing rule has to reach the coordinator, and the coordinator cannot see capture. Storing it
would mean `static let shared = ExportCoordinator()` naming `RecordingController.shared.run` at
static-init time, and would cost the dock previews and `EditorModelTests` the bare `ExportCoordinator()`
they all build. ADR-0045 declined `ExportCoordinator(preference:)` on the same grounds.

**`QualityPreset` is now explicitly `nonisolated`, and that was a latent trap rather than a cost.**
[ADR-0022](0022-background-work-is-explicitly-nonisolated.md) makes an unannotated type in this target
main-actor isolated, and a `Sendable` conformance does not lift a type's *members* out of that — so
`encodability(for:)` was main-actor while `fileFormat(for:)` beside it was not, and which was which
could not be read off the source. `ExportEncoder` already reads the type from a `.utility` queue. The
annotation also removed 25 of the test target's `#IsolatedConformances` warnings.

**The decision is tested for the first time: 16 cases where there were none.** Ten over the module
itself — every rule, every adjacent pair of the order, all five true at once, the empty-adopted-file
rule, the seconds↔frames divergence, and ADR-0042's carry-the-detail-print-the-generic split — and six
over the coordinator's gate, none of which could exist before, because reaching it meant getting past
`presentSavePanel`. Every refusal returns before any AppKit is touched, which is what each one asserts.

**Three of the four refusals can now be seen in the canvas.** `unencodable` needed a doctored Library
and a `defaults write` to photograph when ADR-0041 was written; `alreadyRunning` has never been seen at
all, being reachable only through #127's rename mid-encode — and after
[ADR-0048](0048-an-exports-subject-is-the-recording-not-its-path.md) not even through that, so its
preview is where it is looked at.

## Considered and rejected

**Keeping the coordinator's own wordings.** They were the ones that had drifted, and ADR-0042's table
is the accepted record of what the user reads. The coordinator's telling renders in the same dock slot
as the dock's own sentence; two wordings for one fact in one slot is an authored inconsistency.

**Dropping the specific encodability reason** to get one wording. It is what ADR-0041 prints on the
rung, and throwing it away to simplify a sentence the dock does not print would have been a loss for
no gain. It is carried in the payload.

**`isStillArriving` as the capturing input**, which is how the review sketched it. It would have been
wrong: an empty adopted file reports `isStillArriving == true` (`recording.isEmpty ||
isCapturing(recording)`), so it would have been told *"This Recording is still capturing."* about a
file nothing was capturing.

**Injecting `capture` into `ExportCoordinator`**, and passing a bare `isCapturing: Bool`. The first for
the static-init reason above; the second because it asks the coordinator to trust a boolean a caller
computed, which is the arrangement this whole change is undoing.

**Folding in a `Reason` for the disk pre-flight.** It refuses *after* the save panel, against a
destination volume, on an input none of these six scalars carry. It would make `ExportReadiness` a
two-phase thing, and it is not one.

**Fixing [#127](https://github.com/SamWongML/macos-audio-recording/issues/127) here.** `subjectURL`
following a relocate is the coordinator's *identity*, not this decision. `.alreadyRunning` being a
named case rather than a branch in a view body is what #127 will need in order to delete it cleanly.
*(Done in [ADR-0048](0048-an-exports-subject-is-the-recording-not-its-path.md), which deleted the
route and kept the case — the named case is what made that a one-line docstring change rather than a
view edit, which was the point.)*

Prompted by the architecture review of 12 September 2026, candidate 4.

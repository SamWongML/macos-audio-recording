---
status: accepted
---

# An Export's subject is the Recording, not the path it had at launch

`ExportCoordinator` held `subjectURL: URL?`, copied from `recording.url` when the encode began, and
the Export dock rendered the running phase only while `coordinator.subjectURL == recording.url`.
[ADR-0006](0006-the-library-is-a-folder.md) and [ADR-0020](0020-a-rename-refuses-rather-than-fixes.md)
both promise the opposite of a stable path: a rename or move is **followed silently**, and the store
does that by relocating the *same object* — `LibraryStore.rename` for the app's own rename,
`LibraryStore.reconcile` for Finder's. Neither goes through `EditorModel.select`, so neither reaches
`ExportCoordinator.cancel()`.

So a rename during an Export left the coordinator naming a file that no longer existed. The
comparison failed, the dock's `else` branch rendered, and the Recording being exported lost its own
progress bar and Cancel button — while `isExporting` was still true, so what replaced them was
`An Export is already running.` about the Export it *was* running. The encode itself was never
affected: it is snapshotted at launch ([ADR-0012](0012-export-is-non-blocking-and-cancels-on-navigation.md))
and reads a file it already has open, so it ran to completion invisibly and wrote the right bytes to
the right destination. **Only the telling lost its subject**, which is why the fix is the
coordinator's identity and not the view's comparison. Found by code-tracing in
[#125](https://github.com/SamWongML/macos-audio-recording/issues/125), filed as
[#127](https://github.com/SamWongML/macos-audio-recording/issues/127).

## The decision

**The coordinator holds the `Recording`. `subjectURL` is derived from it and stays the dock's
question.**

```swift
private var subject: Recording?
var subjectURL: URL? { subject?.url }
```

The object is what the store relocates, so holding it is what makes the telling follow a rename — and
it follows **both** rename routes at once, the app's own and Finder's, because both end at
`Recording.relocate`. The surface is unchanged: `phase` and `subjectURL`, exactly as before.

## The comparison stays on the path, and that is the half worth writing down

Holding the object invites the next step — have the dock ask `coordinator.subject === recording` and
delete the url entirely. That would trade this bug for its mirror image.

The Recording on screen is not always the object the Export was launched on.
[ADR-0021](0021-a-recording-that-grew-is-re-adopted.md) re-adopts a file whose length changed, and
`EditorModel.reconcileSelection` rebinds the selection to the fresh object — a *different object at
the same path*, reached without the user navigating anywhere. Identity would take the progress bar
away from that Recording exactly as the stored url took it away from a renamed one.

So the two questions are split: **the object is how the subject is kept current; the path is how the
subject is recognised.** A rename changes the path and keeps the object, and the object carries the
new path in. A re-adoption changes the object and keeps the path, and the path still matches.

## Considered and rejected

**Telling the coordinator from the store.** `LibraryStore.rename` and `.reconcile` are the two
relocate sites, so both would have to call it, and the store — *"the one thing that touches the
folder"* — would grow an Export dependency it has no other use for. A rule enforced at two call sites
is the arrangement [ADR-0046](0046-an-export-refuses-once-and-both-callers-ask.md) has just finished
undoing one file away.

**Posting from `Recording.relocate`.** `Recording` reads no files and knows nothing about the shell;
having it reach `ExportCoordinator.shared` would make a model object name a singleton, and the
previews and tests that build a bare `ExportCoordinator()` would be talking to the wrong one anyway.

**Cancelling the Export on a rename**, which would make the state unreachable rather than correct.
ADR-0012 cancels on **navigation** — closing the editor, selecting another Recording, quitting — and a
rename is none of those; the Recording stays open, keeps its envelope and its live Trim
(ADR-0020), and throwing away its encode for a metadata edit is a tax ADR-0012 declined to levy even
where the user *had* navigated away.

**Keying on `fileIdentity` (dev+inode)** — the thing `reconcile` itself matches renames by. It is nil
for a file that could not be stat'd and for every `Recording.stub`, so the dock would silently fall
back to showing nothing in exactly the previews and tests that exist to show the phases.

## Consequences

**`.alreadyRunning` keeps its case and loses its named route.** ADR-0046 wrote it as *"reachable in
the dock only through #127's rename"* and anticipated that #127 would let it be deleted cleanly. It is
kept, because that was not its only route — **looking for the others is what decided this**, and two
stand:

- **A modeless save panel.** `presentSavePanel` falls back from a sheet to `panel.begin` when there is
  no key window, and a modeless panel leaves the editor live behind it. Select another Recording while
  it is up and `cancel()` runs, but the panel's completion is not guarded by it, so `begin` starts an
  encode on the Recording the user has navigated away from — with the dock now on a different one.
- **A re-adoption, then a rename.** ADR-0021 re-adopts a file whose length changed and the editor
  rebinds to the fresh object; the telling stays on the object that was dropped, and a rename after
  that parts the two paths.

The rule is what stops the dock offering an `Export…` button whose click `export`'s `guard case .idle`
would swallow in silence, which is worse than a sentence. Its docstring now says where it stands,
including that the coordinator's own gate returns before the rule can fire there — which ADR-0046's
*"in the coordinator it is the plain one-at-a-time rule"* did not.

**The Quality Preset display-over was the same defect, and is fixed with it.** `ExportInspector` reset
its per-file preset on `.onChange(of: recording.url)`, so renaming an adopted 96 kHz Recording threw
away the rung the user had picked for it (ADR-0015) and dropped the dock back to a sticky that cannot
encode it. It keys on the Recording now, which also keeps the ADR-0021 behaviour right: a fresh
reading of the same path *is* a new object, and its format may have changed with its bytes.

**The Loudness measurement still re-measures on a rename, and that is left alone.**
`LoudnessCorrectionModel`'s key is `url.path|start|count`, so a rename re-keys and the readout blanks
to `Measuring…` for a pass it did not need. The url is load-bearing there in a way it is not here: the
detached pass *opens the file by url*, so a rename that races the open fails to a `.undefined`
correction, and re-keying is what heals it. Paying one redundant measure to keep that is the better
trade.

**Three cases where there were none**, and the ticket's own is one of them: a parked telling follows a
`relocate`; a fresh reading of the same path still finds its telling, which is the rule the
paragraph above is about and would otherwise be a comment nothing enforced; and a `cancel` lets the
subject go. Plus the end-to-end case through `LibraryStore.rename` with a real `moveItem`, which is
the wiring between the store's relocate and the coordinator's subject.

**Still not photographed.** Reaching the state in the running app needs a save panel completed
synthetically and then a sidebar rename mid-encode, and
[#116](https://github.com/SamWongML/macos-audio-recording/issues/116) is a standing warning about
driving renames with synthetic clicks. ADR-0018 gives the app no UI test layer, so what is verified is
the coordinator's identity and the store's wiring, not the picture.

## Found by the same scan, not fixed here

**A save panel that is not a sheet outlives the navigation that should have cancelled it.** The route
above is not only a way to reach a sentence: ADR-0012's *navigating away cancels* is broken on it, in
the encode and not just the telling. `cancel()` bumps `jobID`, and the panel's completion closure does
not read it, so a destination chosen after the user moved on still launches a job. The fix is small —
capture `jobID` before presenting and drop the completion if it has moved — but it is ADR-0012's
navigation rule rather than this ADR's identity, and it wants its own ticket and its own test.

**`CaptureRun.capturingURL` is the same copied path, one domain over.** `isCapturing(_:)` asks
`capturingURL == recording.url`, and nothing gates Rename on the Recording being captured — the
sidebar's context menu offers it on every row. A rename mid-capture would leave that comparison false,
which loses [ADR-0012](0012-export-is-non-blocking-and-cancels-on-navigation.md)'s *the capturing
Recording is not exportable* and ADR-0031's *no claims about a length still arriving*, and would send
`telling.openEditor(selecting:)` to a path that no longer exists at Stop. It is a capture-side
decision with its own shape — follow, or refuse the rename outright — and it does not belong in a
change to the Export's telling.

Settled in issue #127.

---
status: accepted
---

# A Recording is read once, at one seam

`Recording`'s only initializer was `init?(url:)`, so **a Recording could not exist without a file on
disk**. Every test that wanted one wrote a real 440 Hz CAF first, and that is the mechanical reason
the tier that *consumes* a Recording had no tests at all: `RecordingDay` had zero references in the
suite, `Envelope` zero, and the twelve coordinating modules between them zero. The type was not
hard to test; it was impossible to construct.

Under that sat three reads nothing cached. `source` was two `getxattr` calls — the read primitive
probes the length, then fetches — `recordedAt` was a `resourceValues`, and `Recording.byteCount(of:)`
a bare `stat`. All three were read from view bodies. The sidebar filters on `displayName` (so:
`source`) per row per keystroke and then groups the result through `RecordingDay.group`, which reads
`recordedAt` per row, so a 44-Recording Library of captured Recordings cost 44 × (2 `getxattr` +
1 `resourceValues`) = 132 syscalls per sidebar body pass, on every keystroke in the search field.
`windowSubtitle` was the worst single member: `displayName` read the Source xattr, `== source` read
it a second time, and `recordedAt` stat'd — five syscalls per evaluation of one property. The
`Master` row went further and carried a discarded read, `_ = recorder.elapsed`, used deliberately as
an invalidation trick because the `stat` on the line below it was not observable. And `refresh()`
sorted the folder by re-reading each file's dates **inside the comparator**, which is O(N log N)
syscalls to list N files rather than O(N).

Adoption was never the cost. ADR-0015 measured that: `AVAudioFile`'s `sampleRate` and `channelCount`
come from the container header with no decode, "so the gate costs nothing". The cost was reading the
same facts again, from a view body, at SwiftUI's cadence.

**The decision: a Recording's facts are read once, by one module, and `Recording` itself opens no
files.** `RecordingReader` — behind `RecordingReading` — is the only thing in the app that opens a
file to answer a question about a Recording. `Recording` gains a memberwise initializer and holds
what it was handed.

## Consequences

**A Recording is one line, and the tier that consumes one has tests.** `Recording.stub(…)` in the
suite needs a url, a frame count and a sample rate; everything else defaults. That bought
`RecordingDayTests` (9 cases over a type that had none) and `RecordingFactsTests` (19), plus three
bookkeeping cases in `LibraryStoreTests` that could not be written while every reconcile case had to
write real audio. The suite went from 251 cases to 288.

**The facts are read once, and the leak tests say so.**
`renderingTheLibraryOverAndOverReadsNothingFurther` evaluates `displayName` and `windowSubtitle` a
hundred times and reads back zero further reads from the stub;
`groupingTheLibraryTwiceReadsNothing` groups a 44-Recording Library twice and adopts nothing and
stats nothing. These are the claim itself, not a proxy for it.

**The reader reads whole files, never single fields, and the type can no longer express otherwise.**
There is no `refreshSource(of:)` and no `rereadDate(of:)`, because ADR-0021 already rejected
re-reading a Recording field by field — everything else read at open would have to be re-read with
it and the Trim re-clamped, which "is re-adoption with extra steps". That was a rule a reviewer had
to remember; it is now the shape of the interface. The two probes `RecordingReading` does carry,
`byteCount(of:)` and `identity(of:)`, exist to decide *whether* to re-adopt, never to patch an
object in place. This is worth stating plainly because the next person wanting a live figure will
reach for exactly the rejected thing.

**`Recording` stays a reference type.** The review's sketch said *plain value*; two of those three
words were available and the third was not. Object identity is load-bearing in three places, all of
them ADR-0021's: `EditorModel`'s `if current !== selection { select(current) }`, which is how the
editor notices the store re-adopted the open Recording; `AudioPlayer.load`, which keys on identity
rather than the url "or it would decline to reload and keep playing the old, short segment"; and
`reconcile`, which claims matched objects in a `Set<ObjectIdentifier>` so two urls cannot both
follow one Recording. `trim`, `gain`, `envelope` and `envelopeState` are also observed mutable state
a drag writes live, which a struct would have to thread back through `LibraryStore` on every frame.
Pinned by `aSurvivingURLKeepsItsSameRecordingObject`, `oneRecordingCannotBeFollowedByTwoURLs` and
`persistingTheTrimAndGainDoesNotCostTheRecordingItsObject`. "Plain value" here means *does no I/O*,
and that is the half that mattered.

**`source` splits: the xattr is cached, the filename parse is not.** Caching the whole property
would have changed behaviour. A hand-adopted file with no xattr, renamed from
`Chrome 2026-09-13 at 21.51.caf` to `Interview.caf`, re-parses the new name and reports `Interview`,
so `windowSubtitle`'s origin correctly drops out; a cached `Chrome` would print a stale origin
forever. So `storedSource` is a `let` read once and `source` is `storedSource ?? parsedSource(from:
name)`, which also made the parse a testable static for the first time.
`aRenamedFileWithNoXattrRederivesItsSource` and `aRenamedFileKeepsTheSourceItsXattrRecorded` are the
two halves.

**One notion of a Recording's date, so ADR-0031's agreement is structural.** `LibraryStore.modified(_:)`
is gone. It existed only because the store had to sort urls before any Recording existed, so it
re-derived `recordedAt`'s creation-then-modification rule on its own — and its doc comment said out
loud that the two spellings must not disagree. `refresh()` now adopts first and sorts the Recordings
by a stored `let`, which costs no syscall at all and cannot disagree with what `RecordingDay.group`
reads. `theStoreOrdersRecordingsNewestFirst`, `aRecordingWithNoDateSortsLast` and
`aRecordingThatRanAcrossMidnightIsFiledUnderTheDayItBegan` pin it. This also closed a latent
inconsistency the file documented against itself: `byteCount` deliberately avoided `resourceValues`
because they are cached on the bridged `NSURL`, while `recordedAt` used `resourceValues` and was
therefore already serving a cached answer of unpredictable age.

**The growing master's `stat` stayed, and moved.** ADR-0031 decided the `Master` row states a
current figure rather than an em dash, so the read is a decision, not an accident — but a view body
performing it once per evaluation, with a discarded `elapsed` read above it to force the
recomputation, is not. `CaptureRun` publishes `masterByteCount` through the reader on the same 4 Hz
gate as `elapsed`: one gate, because the reason is the same twice over — the menu bar observes
`elapsed`, and a byte count arriving twenty times a second is ambient motion, which ADR-0028
forbids. `theMastersSizePublishesAtFourHertzEvenWhenTickedAtTwenty` and
`theMastersSizeCostsOneStatPerClockTickRatherThanOnePerTick` hold the cadence;
`theMasterHasNoSizeBeforeTheFirstSoundOrAfterTheEnd` and `onlyTheFileBeingCapturedHasACurrentFigure`
hold ADR-0031's two em-dash cases — the armed window before the first sound (ADR-0016), and a file
merely *arriving* in the Library, which nothing is watching and so has no figure to be current about.

**Writes stayed on `Recording`, deliberately.** `persistTrim` and `persistGain` still call
`RecordingMetadata` from the Recording itself. None of the three reasons the reads had to move
applies to them: they fire once per gesture-end rather than at UI cadence, they are not in a view
body, and they never gated construction. Moving them would buy a symmetry and cost a seam.

**Two conformances, and no more.** `RecordingReader` in the app and `StubRecordingReader` in the
suite — the bar ADR-0043 set for an interface to exist here at all. Eight cases in
`LibraryStoreTests` still use a real file, each because the file is the subject: the
`st_size`-versus-xattr claim ADR-0021 names, a real file growing in place, the `public.audio` gate,
`AVAudioFile` refusing a broken CAF, the folder listing and its missing-directory case, and the two
rename cases whose impure half is
`FileManager.moveItem`. What left the disk is the bookkeeping — which object survives, which is
re-read, which drops out. `AudioFixtures.writeCAF` call sites fell from 40 to 23 against `main`, and
all 23 are now in suites where real audio is the subject.

**ADR-0022's line is not crossed.** `RecordingMetadata` and `LibraryLocation` stay `nonisolated`,
because the capture writer thread drives them — `CAFMasterWriter` writes the Source xattr and
`CaptureEngine` the Seams. The reader *calls* them; it does not absorb them. The reader itself is
`@MainActor`, because it produces a `Recording`, and calling `nonisolated` code from the main actor
is free.

## Considered and rejected

**Making `Recording` a struct.** The three identity call sites above are ADR-0021's mechanism, not
an implementation detail, and the observed mutable state a drag writes would have to be threaded
back through `LibraryStore` on every frame. Every win the review claimed follows from the
initializer, not from value semantics.

**A per-field reader.** `refreshSource(of:)`, `rereadDate(of:)`, `refreshFrameCount(of:)` — the
shape a module named `RecordingReader` invites. ADR-0021 rejected it on its merits and this makes it
unexpressible, which is the stronger form of the same decision.

**Caching the whole of `source`.** One property, one `let`, and a stale origin in the window
subtitle for every hand-adopted file the user ever renames. The split is not a rounding of the same
thing.

**Memoizing the `Master` row's length instead of moving it.** ADR-0031 asks for a figure that is
*current*; a memoized one is stale by construction, and the cache would need the same invalidation
the discarded `elapsed` read was standing in for. The run already publishes on a gate, so the figure
goes where the gate is.

**`var masterByteCount` on `Capturing`**, so the capture — which owns the file it is writing — is
the one that weighs it. Attractive, and not available: `CaptureEngine.writer` is documented
writer-thread-only state, "reached by the main thread only after `finished` is signalled", so
`CoreAudioCapture` has no main-actor-safe path to the url it would stat, and manufacturing one means
a URL box threaded through the builder's hooks. The run already holds `capturingURL` on the main
actor, so it takes the reader as a fourth dependency instead — which also gives `RecordingReading`
its second consumer, and that is the honest justification for it being an interface rather than a
closure.

**Cutting `reconcile`'s syscalls.** It still costs up to four `stat`s per url on the growing-master
path. Every behaviour-preserving fix either adds memoization or moves the cost onto first adoption,
and the obvious one — gating the rename branch on a `byURL` miss — breaks the case where a
*different* Recording is renamed onto a tracked path. Left as found, and not made worse. If it is
ever worth fixing, the shape is a single combined probe on `RecordingReading` returning length and
identity from one `stat`.

## Notes

This ADR uses ADR-0021's own word, *a reading*, for a fact read off a file at a moment in time.
`CONTEXT.md` has no term for it, and no term for `Master` either, though both are load-bearing here
and in ADR-0003 and ADR-0031. Noted for `/domain-modeling` rather than filled in: inventing a noun
in an ADR is how a glossary acquires words nobody agreed to.

Prompted by the architecture review of 12 September 2026, candidate 2.

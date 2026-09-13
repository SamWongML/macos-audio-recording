---
status: delivered
source: architecture review, 12 Sep 2026 — candidate 2, "Separate a Recording's facts from reading them"
record: docs/adr/0044-a-recording-is-read-once-at-one-seam.md
---

# Separate a Recording's facts from reading them

## Context

`Recording`'s only constructor is `init?(url:)` (`Recording.swift:173`), so **a Recording cannot exist
without a file on disk**. Every test that wants one writes a real 440 Hz CAF through
`AudioFixtures.writeCAF` first, and that is the mechanical reason the tier that *consumes* a
Recording has no tests: `RecordingDay` has zero test references, `Envelope` has zero, and the 12
coordinating modules between them have zero.

Under that sit three reads nothing caches:

| `Recording.swift` | member | cost per access |
|---|---|---|
| `:133` | `source` | 2 `getxattr` (the read primitive probes the length, then fetches) |
| `:149` | `recordedAt` | one `resourceValues` |
| `:230` | `static byteCount(of:)` | one bare `stat` |

They are read from view bodies. `EditorView.swift:35-40` filters the sidebar on `displayName`
(→ `source`, for every Recording still carrying capture's own filename) per row per keystroke; `:42`
then groups the result through `RecordingDay.group`, which reads `recordedAt` per row
(`Recording.swift:335`). A 44-Recording Library of captured Recordings therefore costs 44 ×
(2 `getxattr` + 1 `resourceValues`) = 132 syscalls per sidebar body pass, on every keystroke in the
search field. `windowSubtitle` (`:162`, the window's `.navigationSubtitle`) is the worst single
member: `displayName` reads the Source xattr, `== source` reads it a second time, and `recordedAt`
stats — 5 syscalls per evaluation of one property.
And `EditorView.swift:644` carries a discarded read, `_ = recorder.elapsed`, used deliberately as an
invalidation trick because the `stat` on the line below it is not observable.

The cost is not in *adopting* a file. ADR-0015 measured that: `AVAudioFile`'s `sampleRate` and
`channelCount` come from the container header with no decode, "so the gate costs nothing". The cost
is in reading the same facts again, from a view body, at SwiftUI's cadence — and in a refresh that
sorts the folder by re-reading each file's dates **inside the comparator** (`LibraryStore.swift:118`),
which is O(N log N) syscalls rather than O(N).

The change is one seam: `Recording` becomes a value that does **no I/O** and gains a memberwise init,
and every read moves behind one module that produces it.

The review ranks this second of six and calls it the enabler for the rest — candidates 3, 4, 5 and 6
all want to test a module that takes a `Recording`. Candidate 1 landed last week
(`docs/plans/give-the-capture-run-a-seam.md`), and its §5 test 26 is already written against a real
CAF with a note to delete the fixture when this lands.

---

## As built — Phases 2 and 3

They landed as **one** commit, because the code forced it: making `stillDescribes` pure means
`reconcile` must be handed a byte count, which means the reader must be injected — which was most of
Phase 3's diff. The suite went from 251 cases to 252, and both targets build with no warning of their
own.

| file | lines | planned |
|---|---|---:|
| `RecordingReader.swift` | 109 | ~150 |
| `Recording.swift` | 326 (was 339) | smaller |
| `LibraryStore.swift` | 206 (was 207) | ~±40 |

Four things differ from the plan below, each because writing the code showed the plan was wrong:

- **There is no `RecordingReading` protocol yet.** With only `RecordingReader` conforming, it failed
  the bar `give-the-capture-run-a-seam.md` §1 set for an interface to exist at all — two
  conformances, the production adapter and the test double. It comes back in Phase 4, in the same
  commit as `StubRecordingReader`, which is where the sibling plan put all four of its protocols.
  `LibraryStore` holds the concrete reader until then; the swap is five lines.
- **`adopt` builds one `Recording`, not two.** The plan's move-it-verbatim instruction carried the
  old init's two branches across, and they duplicated five of thirteen arguments. Optional-derived
  values collapse them, and the undecodable file still reads no metadata — nothing can have written
  any.
- **`RecordingBrief` is handed the store's reader.** The plan had `EditorView` untouched until Phase
  5, but removing `Recording.byteCount(of:)` breaks the `Master` row immediately. It takes
  `model.store.reader` as a parameter rather than minting a second production reader, so Phase 5
  deletes a parameter instead of a property that reads as permanent.
- **`audioFiles(in:)`'s ordering test became a store test.** The listing is unsorted now, so
  `audioFilesSkipsSubdirectoriesAndHiddenFilesNewestFirst` split: the filter is still the reader's
  case, and `theStoreOrdersRecordingsNewestFirst` is the new one over `refresh`. Its `setModified`
  helper went with it — it never affected the order, because creation date wins.

One thing the plan asked for and did not get: `reconcile` still costs up to four `stat`s per url on
the growing-master path. Every behaviour-preserving way to cut it either adds memoization or moves
the cost onto first adoption — and gating the rename branch on a `byURL` miss, the obvious fix,
breaks the case where a *different* Recording is renamed onto a tracked path. Left as it was found;
this diff did not make it worse.

---

## As built — Phase 4

The suite went from 251 cases to 283. `RecordingReading` is back, with
`StubRecordingReader` as the second conformance that justifies it, and `LibraryStore` holds it as
`any RecordingReading` again — five lines, as predicted.

Three things differ from the plan below:

- **The split is not "four real-file cases".** Nine survive on disk, and each earns it: the
  `st_size`-versus-xattr claim ADR-0021 names, a real file growing in place, the `public.audio`
  gate, `AVAudioFile` refusing a broken CAF, the folder listing and its missing-directory case,
  and the two rename cases, whose impure half is `FileManager.moveItem`. What left the disk is the
  bookkeeping: which object survives, which is re-read, which drops out.
- **`Recording.stub` needs a sentinel for an unreadable length.** `byteCount: Int64? = nil` cannot
  tell *unstated* from *could not be stat'd*, and a bare `nil` argument binds to the outer optional
  of an `Int64??`, so `lengthFromFrameCount` stands for unstated and `nil` means what it means on a
  real file.
- **`RecordingSeamsTests` and `CaptureRunTests` lost their fixtures too.** The seam-surfacing rule
  is about Seams a Recording already has, and candidate 1's §5 test 26 said in as many words to
  delete its CAF when this landed. `writeCAF` call sites fell from 26 to 23, all in suites where
  real audio is the subject.

New coverage, by file: `RecordingDayTests` (9 cases, over a type that had none),
`RecordingFactsTests` (19), `RecordingSeamsTests` (+2 scale cases), `LibraryStoreTests` (+3
bookkeeping cases the stub made expressible).

---

## Handoff — Phases 5 and 6 *(delivered; kept for the reasoning)*

**Start here if you are picking this up fresh.** Branch `refactor/a-recording-is-read-once`, four
commits on top of `main`, nothing pushed. Phases 1-4 are delivered; 5 and 6 are not. The suite is
283 cases, green, and both targets build with no warning of their own.

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```

Read §5's "Phase 5" and "Phase 6" below for intent; this section is what the code actually looks
like now and where the decisions are.

### Phase 5 — the view body stops stat'ing

One call site is left. `EditorView.swift`, in `RecordingBrief`:

```swift
var reader: any RecordingReading          // passed in from `RecordingBrief(recording:reader:)`

private var masterText: String {
    if recorder.isCapturing(recording) {
        _ = recorder.elapsed                                      // ← the invalidation trick
        let size = reader.byteCount(of: recording.url)?...        // ← the syscall in a body
        return size.map { "\($0) and growing" } ?? "—"
    }
    ...
}
```

ADR-0031 **decided** that this row states a current figure from a bare `stat`, so the read stays;
what moves is who performs it, onto something observable. `CaptureRun.publishElapsed(from:now:)`
already gates on `Self.clockInterval` (4 Hz) inside `tick(now:)` — publish the byte count in the
same place, on the same gate, and the brief reads a published property. Then delete `_ =
recorder.elapsed`, delete the `reader` parameter, and delete `model.store.reader` from the call
site at `EditorView.swift`'s `RecordingBrief(recording:reader:)`.

**Two ways to get the number, and the second is the thinner one.**

- **A — inject the reader into `CaptureRun`** as a fourth dependency, calling
  `reader.byteCount(of: capturingURL)`. Costs a stored property, a change to
  `CaptureRun.init(builder:runway:telling:)`, the production wiring in `RecordingController.init()`,
  and a fourth double in `CaptureRunTests.Rig` — though `StubRecordingReader` already exists and
  would serve.
- **B — add `var masterByteCount: Int64? { get }` to `Capturing`** (recommended). The capture owns
  the file it is writing, so it is the honest owner of "what does it weigh right now".
  `CoreAudioCapture` stats the writer's url; `FakeCapture` gets a settable property. One member on
  a protocol that already has its two conformances, no new dependency, no change to the run's
  initializer or the `Rig`. ADR-0031 asks for a bare `stat` — it does not say who calls it.

Either way `capturingURL` (`CaptureRun.swift`, set in the `onMasterCreated` hook) is the url in
question, and it is nil through the armed window before the first sound (ADR-0016), which is
already the em-dash case.

**Tests to add**, in `CaptureRunTests`, alongside the cadence cases already there:

- the master's size publishes at 4 Hz when ticked at 20, the same rule
  `theClockPublishesAtFourHertzEvenWhenTickedAtTwenty` pins for `elapsed`;
- it is nil before the first sound, and nil again after a return to idle;
- a Recording that is merely *arriving* in the Library — not the one being captured — still gets
  nothing, which is ADR-0031's "no figure to be current about".

**Must not change:** the figure is 4 Hz, never 20 — a byte count ticking twenty times a second is
ambient motion, which ADR-0028 forbids; a file merely arriving in the Library keeps the em dash; and
the settled case still reads `openedByteCount`, not a fresh `stat`.

### Phase 6 — the record

`docs/adr/0044-a-recording-is-read-once-at-one-seam.md`. **0044 is the next free number** (0043 is
the capture-run seam). Follow ADR-0043's shape, which is this repo's own precedent for putting a
seam under a spine: an H1 that is a declarative sentence naming the decision, unlabelled context
prose, `## Consequences` naming the test that pins each one, `## Considered and rejected`.

What is a decision rather than a refactor, and so belongs in it, is listed in §5's Phase 6. Two
additions the work surfaced:

- **Writes stayed on `Recording`.** `persistTrim`/`persistGain` still call `RecordingMetadata`.
  That is deliberate and worth stating: they fire once per gesture-end, never repeat at UI cadence,
  and never gated construction — none of the three reasons the reads had to move.
- **The reader reads whole files, never single fields.** ADR-0021 already rejected the per-field
  version ("re-adoption with extra steps"); 0044 should say that the type can no longer express it,
  because the next person wanting a live figure will reach for exactly that.

Amend rather than add: ADR-0021 and ADR-0031 each get a one-line pointer to 0044. Editing an ADR in
place is established here — ADR-0022's last bullet was edited to say "closed by ADR-0043". Also
update this plan's front-matter `status:` to `delivered` and add the last `As built` section.

### What bit us, so it does not bite you again

- **The test target does not set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the app target does.**
  Any suite or nested type touching `Recording`, `LibraryStore` or the reader needs an explicit
  `@MainActor`, and a nested type does not inherit its enclosing suite's isolation.
- **A default argument is evaluated in a nonisolated context**, so a main-actor value cannot be
  constructed in one. That is why `LibraryStore` and `RecordingController` each have two
  initializers rather than one with a default.
- **`#require` warns when it can prove the value is never nil**, and the warning is an error in
  review. Prefer indexing a known-count array over `#require(...first)`.
- **`try` cannot appear to the right of a non-assignment operator** inside `#expect` — bind the
  value to a `let` first.
- New files under `AppTape/AppTape/` and `AppTape/AppTapeTests/` join their targets automatically
  (`PBXFileSystemSynchronizedRootGroup`); no project-file edit.

### Deliberately left alone

`reconcile` still costs up to four `stat`s per url on the growing-master path. Every
behaviour-preserving fix either adds memoization or moves cost onto first adoption, and the obvious
one — gating the rename branch on a `byURL` miss — breaks the case where a *different* Recording is
renamed onto a tracked path. It was not made worse here. If it is ever worth fixing, the shape is a
single combined probe on `RecordingReading` returning length and identity from one `stat`.

---

## 0 · Three decisions to take before any code

### `Recording` stays a class, and "plain value" means "does no I/O"

The review's after-diagram says *plain value · no I/O · memberwise init*. Two of those three are the
change. The third is not available: **object identity is load-bearing in three places**, and all
three are ADR-0021's.

- `EditorModel.swift:128` — `if current !== selection { select(current) }`. This is how the editor
  notices the store re-adopted the open Recording, which is the whole of ADR-0021's selection
  consequence.
- `AudioPlayer.load` keys on object identity rather than the url, "or it would decline to reload and
  keep playing the old, short segment" (ADR-0021, Consequences).
- `LibraryStore.reconcile` (`:154`) claims matched objects in a `Set<ObjectIdentifier>` so two urls
  cannot both follow one Recording.

`trim`, `gain`, `envelope` and `envelopeState` are also observed mutable state that a drag writes
live and the window renders. A struct would have to be threaded back through `LibraryStore` on every
drag frame.

So: `@Observable final class Recording` stays. What goes is every file read inside it. That is what
makes the fixture unnecessary, which is the point — the review's wins all follow from the init, not
from the value semantics.

### The reader reads once, and never per field — ADR-0021 already rejected the other thing

ADR-0021's first rejected alternative is **"make `frameCount` mutable and re-read it"**: everything
else read at open would have to be re-read with it and the Trim re-clamped, which "is re-adoption
with extra steps". A module named `RecordingReader` invites exactly that shape, so state the line
now: the reader's `adopt` reads a file **once, completely**, and hands back an immutable set of
facts. It gets no `refreshSource(of:)`, no `rereadDate(of:)`, no per-field anything. The only way a
Recording's facts change is re-adoption, which is ADR-0021's rule, and the two probes the interface
does carry (`byteCount`, `identity`) exist to *decide whether to re-adopt* rather than to patch an
object in place.

This plan therefore does not contradict ADR-0021; it makes the ADR's rule the only thing the type
can express. Worth saying in ADR-0044 explicitly, because the next person to want a live figure will
reach for a per-field re-read.

### Naming: `adopt`, and one glossary gap to note rather than fill

`CONTEXT.md`'s **Recording** entry already supplies the verb — a file the user places in the Library
"is **adopted** as a Recording" — and ADR-0015 is "the adoption gate", ADR-0021 says "re-adopted".
So the construction method is `adopt(_:)`, not `load` or `make` or `open`.

What the glossary has no word for is the thing this whole candidate is about: **a fact read off a
file at a moment in time**. ADR-0021 invents "a *reading*" inline; ADR-0031 says "the listing" versus
"the engine's figures"; `Master` — the word on the brief's own row and in ADR-0003 — is not a glossary
term either. `docs/agents/domain.md` says an absent term is a signal: either invented language, or a
real gap to note for `/domain-modeling`. This is the second. **Note it; do not widen this change into
a glossary edit.** The plan uses ADR-0021's own word, *reading*, in prose and commits no new noun to
the codebase.

---

## 1 · Target shape

```
                  before                                          after

EditorView.days ──► RecordingDay.group                EditorView.days ──► RecordingDay.group
                      └─► recordedAt ─► resourceValues                      └─► recordedAt (a let)
EditorView.matches ─► displayName                     EditorView.matches ─► displayName
                      └─► source ─────► getxattr ×2                         └─► source (a let + a parse)
RecordingBrief ─────► Recording.byteCount ─► stat     RecordingBrief ─────► run.masterByteCount
                      (plus `_ = recorder.elapsed`)                         (published at 4 Hz)

Recording · init?(url:) · 6 syscalls · the only       Recording · @Observable · no I/O at all
  way to make one                                       init(url:frameCount:sampleRate:…) memberwise
                                                                     ▲
                                                        ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─  RecordingReading
                                                                     │
                                                      ┌──────────────┴──────────────┐
                                                 RecordingReader           StubRecordingReader
                                                 (the one module             (the suite —
                                                  that opens a file)          url → Recording)
```

Two conformances and no more — the production reader and the test double. That is the bar
`docs/plans/give-the-capture-run-a-seam.md` §1 set for an interface to exist, and this clears it.

---

## 2 · The interface

New file **`AppTape/AppTape/RecordingReader.swift`** — the protocol and the production reader
together, so the seam is one file to read.

```swift
/// Everything that reads a Recording's facts off the disk. `Recording` itself does none of it, so
/// this is the only module in the app that opens a file to answer a question about one.
///
/// `adopt` carries ADR-0015's gate; the other three are the store's reconcile inputs (ADR-0006,
/// ADR-0021). Exactly two conformances — `RecordingReader` in the app, `StubRecordingReader` in the
/// suite — which is the whole reason the protocol exists.
@MainActor
protocol RecordingReading {
    /// Every playable-looking file directly in `directory`, unsorted. Hidden files and
    /// subdirectories are skipped: ADR-0006 lists the folder, not a tree. The order is the
    /// caller's business — the store sorts by `recordedAt` once the facts are read (§4).
    func audioFiles(in directory: URL) -> [URL]

    /// The adoption gate (ADR-0015), and the one `AVAudioFile` open in the app. Nil when the file
    /// is not audio at all; a typed-but-undecodable file still yields a Recording, in its
    /// `isOpenable == false` state.
    func adopt(_ url: URL) -> Recording?

    /// The file's data length. A bare `stat`, never `URL.resourceValues(forKeys: [.fileSizeKey])` —
    /// resource values are cached on the bridged `NSURL` and would hand back the length from before
    /// the file grew, which is exactly the staleness ADR-0021 exists to catch.
    func byteCount(of url: URL) -> Int64?

    /// `dev`+`inode`, so the store can follow a rename (ADR-0006).
    func identity(of url: URL) -> FileIdentity?
}
```

`RecordingReader` is the production conformance, and `Recording.init?(url:)` moves into its `adopt`
**verbatim** — the reads do not change, only where they live. One improvement falls out for free:
the old init stats the same path twice (`FileIdentity(url:)` at `:176`, then `Self.byteCount(of:)`
at `:181`); the reader takes one `struct stat` and derives both.

`audioFiles(in:)` belongs on it because the folder listing is the same concern by the same rule —
it is a read of the Library, it is the other half of what `LibraryStore.refresh` needs, and putting
it here is what lets the store be tested with no disk at all. `LibraryStore.audioFiles(in:)`
(`:110-119`) moves across unchanged but for its sort, which §4 removes.

**`RecordingMetadata` does not move, and the reader is `@MainActor`.** `RecordingMetadata` and
`LibraryLocation` are explicitly `nonisolated` and ADR-0022 (closed by ADR-0043) makes those
annotations load-bearing: the capture writer thread drives them — `CAFMasterWriter.swift:62` writes
the Source xattr, `CaptureEngine.swift:284` the Seams. The reader *calls* them; it does not absorb
them, and calling `nonisolated` code from the main actor is free. The reader itself must be
`@MainActor` because it produces a `Recording`, which is unannotated in a target whose default
isolation is `MainActor`. Nothing in the capture spine needs the reader, so no part of this change
crosses ADR-0022's line. Verify the usual way: a clean build of the app target, with
*"main actor-isolated … cannot be called from outside of the actor"* treated as an error.

---

## 3 · The three facts that stop being re-read

### `source`: cache the xattr, keep the parse

```swift
/// The Source xattr, read once at open (ADR-0006). Nil when the file has none — a hand-adopted
/// file the app never captured — which is what the filename fallback below is for.
let storedSource: String?

/// The Source rides in an xattr written at capture (ADR-0006); the filename is the fallback.
/// Only the xattr is a *read*: the fallback is a parse of the current `name`, so it still follows a
/// Finder rename exactly as it did when this was one computed property.
var source: String { storedSource ?? Self.parsedSource(from: name) }

/// The date pattern capture's generated names carry, and what is left when you strip it.
static func parsedSource(from name: String) -> String { … }
```

Caching the *whole* property would change behaviour. A hand-adopted file with no xattr, renamed
from `Chrome 2026-09-13 at 21.51.caf` to `Interview.caf`, currently re-parses the new name and
reports `Interview`, so `windowSubtitle`'s origin correctly drops out. A cached `Chrome` would print
a stale origin. Splitting it keeps today's behaviour and makes the parse a testable static, which it
has never been.

### `recordedAt`: a stored `let`

```swift
/// When this Recording was made — its creation, not its last write (ADR-0031). Read once at open;
/// a creation date does not change under a rename, and a file that *grew* is re-adopted rather than
/// followed (ADR-0021), so a fresh read is a fresh object.
let recordedAt: Date?
```

This also closes a latent inconsistency the file documents against itself: `byteCount` deliberately
avoids `resourceValues` because it is cached on the bridged `NSURL` (`:227-229`), while `recordedAt`
used `resourceValues` and was therefore already serving a cached answer of unpredictable age. A fact
read once in `adopt` has no staleness question to get wrong.

### `stillDescribes`: pure

```swift
/// Whether this Recording's reading still describes the file — whether it still has the length
/// this object read (ADR-0021). Takes the count rather than reading it, because the rename path
/// asks about the *new* path while this object still holds the old one, and because a Recording
/// does not open files.
func stillDescribes(byteCount: Int64?) -> Bool { byteCount == openedByteCount }
```

With that, `Recording` does **zero** I/O. `static byteCount(of:)` and `conformsToAudio` leave the
file; `FileIdentity.init?(url:)` moves to the reader as `identity(of:)` and `FileIdentity` keeps only
its memberwise init, so the suite can mint one.

### The memberwise init

```swift
/// A Recording, fully read. Nothing here touches the disk: `RecordingReader.adopt` does the reading
/// and hands the facts over, and a test hands them over directly.
init(url: URL,
     frameCount: AVAudioFramePosition,
     sampleRate: Double,
     channelCount: Int = 2,
     sourceBitsPerChannel: Int = 32,
     isOpenable: Bool = true,
     openedByteCount: Int64? = nil,
     fileIdentity: FileIdentity? = nil,
     storedSource: String? = nil,
     recordedAt: Date? = nil,
     storedTrim: Trim? = nil,
     gain: Double = 0,
     seams: [Seam] = [])
```

The body is assignment plus the two derivations the old init did after the decode, both pure:
`trim = storedTrim ?? Trim(duration: duration)` and `envelope = Envelope(sampleRate: sampleRate)`.
`duration` is already `frameCount / sampleRate` (`:128`), unchanged.

A fixture is then one line, which is the review's leverage claim:

```swift
let recording = Recording(url: URL(filePath: "/L/Chrome 2026-09-13 at 21.51.caf"),
                          frameCount: 48_000 * 90, sampleRate: 48_000)
```

---

## 4 · What the store does instead

`LibraryStore` is already "the one thing that touches the folder" (`:10-26`) with a pure core — but
its core is not pure: `reconcile` (`:148`) calls `Recording(url:)`, `FileIdentity(url:)` and
`stillDescribes`, which is three reads per url. With the reader injected, all three become interface
calls and the core is pure in fact rather than in the doc comment.

```swift
@MainActor @Observable final class LibraryStore {
    private let reader: any RecordingReading

    /// The production wiring: the real folder and the real reader. Written as its own initializer
    /// rather than a default argument, because a default argument is evaluated in a nonisolated
    /// context and the reader is main-actor isolated — the same reason `RecordingController` has
    /// two (`RecordingController.swift:26-33`).
    convenience init() { self.init(directory: LibraryLocation.directory, reader: RecordingReader()) }

    /// For a test: a scratch folder, or a reader with no disk behind it at all.
    init(directory: URL, reader: any RecordingReading) { … }

    static func reconcile(existing: [Recording], urls: [URL],
                          reader: any RecordingReading) -> [Recording]
}
```

`init(directory: URL? = nil)` goes, so the 14 `LibraryStore(directory: dir)` calls in
`LibraryStoreTests` each name a reader — which is the point of the phase.

**`LibraryStore.modified(_:)` (`:125-128`) is deleted.** It exists only because the store had to sort
urls before any Recording existed, so it re-derived `recordedAt`'s creation-then-modification rule on
its own — and its doc comment (`:121-124`) says out loud that the two must not disagree. Once
`recordedAt` is a fact read at adoption, `refresh()` adopts first and sorts the Recordings:

```swift
func refresh() {
    let urls = reader.audioFiles(in: directory)
    recordings = Self.reconcile(existing: recordings, urls: urls, reader: reader)
        .sorted { ($0.recordedAt ?? .distantPast) > ($1.recordedAt ?? .distantPast) }
    …
}
```

One notion of a Recording's date, one read, and the sort/group agreement ADR-0031 asked for becomes
structural rather than a comment asking two functions to stay in step.

It is also the largest single saving here, because `modified` is called **inside the comparator**
(`:118`): the sort re-reads each file's dates on every comparison, so listing the folder costs
O(N log N) `resourceValues` calls, not O(N). Sorting `Recording`s by a stored `let` costs none.

Ordering is load-bearing and must not change: `RecordingDay.group` sorts its *buckets* but takes
within-day order from its input, so the sidebar's newest-first-within-a-day ordering comes from the
store. Sorting after reconcile preserves it; `reconcile`'s output order stops mattering.

---

## 5 · Implementation phases

Each phase is one commit that leaves the app building and the suite green.

### Phase 1 — the plan
*New:* `docs/plans/separate-a-recordings-facts-from-reading-them.md` (this file).

### Phase 2 — `Recording` does no I/O; the reader does it all
*New:* `RecordingReader.swift` (~150). *Changed:* `Recording.swift` (−60/+40), `LibraryStore.swift`
(the one app call site, `:168`), and the 22 test sites.

Write the protocol and `RecordingReader`, moving `init?(url:)`, `conformsToAudio`,
`static byteCount(of:)` and `FileIdentity(url:)`'s stat across verbatim. Apply §3 to `Recording`.
Keep every doc comment — they carry the ADR citations and they are why the file is readable; a move
that drops them costs more than the move gains.

The 22 test sites are mechanical: `Recording(url: x)` → `reader.adopt(x)` with one
`let reader = RecordingReader()` per suite. They keep their CAFs in this phase; Phase 4 decides which
of them should.

**Check:** app and test targets build; suite green; no app file but `RecordingReader.swift` and
`LibraryStore.swift:168` names a file-reading API on `Recording`, because there is none left.

### Phase 3 — the store goes through the interface
*Changed:* `LibraryStore.swift` (~±40).

Inject the reader (§4), route `reconcile`'s three reads through it, delete `modified`, sort after
adoption. `audioFiles(in:)` moves to the reader and loses its sort.

**Check:** builds; suite green; **and one real end-to-end pass by hand** — open the editor on a
Library of several days, confirm the sidebar's order and day grouping are unchanged, rename a
Recording in Finder and confirm the row follows rather than blinking out.

### Phase 4 — the double, and the tests the seam buys
*New:* `AppTapeTests/RecordingDoubles.swift` (~90), `AppTapeTests/RecordingFactsTests.swift` (~200),
`AppTapeTests/RecordingDayTests.swift` (~120). *Changed:* `LibraryStoreTests.swift`.

```swift
/// A reader over an in-memory Library: the test says what is in the folder and what each file
/// reads as, and reads back how often it was asked. No disk, no CAF.
@MainActor final class StubRecordingReader: RecordingReading {
    var files: [URL] = []
    var recordings: [URL: Recording] = [:]
    var byteCounts: [URL: Int64] = [:]
    var identities: [URL: FileIdentity] = [:]
    private(set) var adoptCount = 0, byteCountCount = 0
}
```

`LibraryStoreTests` (14 cases, 298 lines, every one of them writing a CAF into a scratch directory)
splits in two. Most move to the stub — the reconcile cases are about *bookkeeping*, not about audio:
unchanged path keeps its object, a rename is followed by device+inode, a grown file is re-adopted, a
vanished file falls out, a non-audio url yields nothing, one object cannot be claimed twice. Four
keep a real file because the file is the subject: the xattr round-trip
(`persistingTheTrimAndGainDoesNotCostTheRecordingItsObject`, which ADR-0021 names as the test pinning
"xattrs stay outside the data length"), the can't-open adopted file, the in-place growth via
`growInPlace` (`:281-293`), and the `writeCAF` → `adopt` path itself, which is the only place
`AVAudioFile`'s reading is exercised at all.

New cases, none of which needs a file (≈26):

**`RecordingDay.group` — today entirely untested**
1. Newest day first.
2. Newest Recording first within a day, taken from the input order the store set.
3. `title` is `Today` / `Yesterday` / a wide weekday inside 7 days / day-and-month beyond it.
4. A Recording whose `recordedAt` is nil buckets at `.distantPast` rather than being dropped.
5. A Recording that ran across midnight is filed under the day it **started**, which is the
   consequence ADR-0031 claimed and nothing checked.
6. An empty Library groups to no days.

**`source`, `displayName`, `windowSubtitle` (ADR-0006/0020/0031)**
7. The Source xattr wins over the filename.
8. With no xattr, a generated name parses to its Source.
9. With no xattr and a user's name, `source` is the name, so `displayName` is the name too.
10. `parsedSource(from:)` returns the whole name when the date pattern is absent.
11. `displayName` is the Source while the name is capture's, the name once the user has renamed it.
12. `windowSubtitle` omits the origin when `displayName == source`, and carries it once they differ.
13. `windowSubtitle` with a nil `recordedAt` is the origin alone, not a dangling separator.

**Facts read once (the leak tests — this is the candidate's own claim)**
14. Evaluating `displayName` and `windowSubtitle` a hundred times costs the stub zero further reads.
15. Grouping a 44-Recording Library twice adopts nothing and stats nothing.

**`stillDescribes` and the staleness rule (ADR-0021)**
16. Equal lengths still describe; a greater or smaller one does not.
17. Two unreadable lengths (nil == nil) compare equal, so an unstattable file is left alone.
18. A Recording adopted with no `openedByteCount` is not churned by a readable one appearing.

**Reconcile, over the stub (moved from `LibraryStoreTests`)**
19. An unchanged path keeps the same object.
20. A new path with the same identity relocates the existing object instead of dropping it.
21. A grown file yields a different object at the same url — ADR-0021's rule.
22. Two urls cannot both claim one Recording.
23. A url the reader declines to adopt yields no row.
24. `refresh()` orders newest-first by `recordedAt`, not by the reader's file order — the sort
    `modified` used to do.

**The rest of `Recording`, now one-liners**
25. `seamSummary`'s four branches — none, surfaced, sub-threshold only, and the ms-vs-seconds
    scale — which `RecordingSeamsTests` pays five CAFs for today.
26. `trimmedFrameRange` rounds and clamps, and is `(0, 0)` at `sampleRate == 0`.

**Check:** suite green and materially larger; `RecordingSeamsTests`'s five `writeCAF` calls gone.

### Phase 5 — the view bodies stop doing syscalls *(separable)*
*Changed:* `CaptureRun.swift`, `CaptureAdapters.swift` or `RecordingReader.swift`,
`RecordingController.swift`, `EditorView.swift`, `CaptureRunTests.swift`.

`RecordingBrief.masterText` (`EditorView.swift:638-650`) states the growing master's size from a bare
`stat`, and that is ADR-0031's decision, not an accident — so the `stat` stays; what moves is *who*
does it. `CaptureRun` already publishes `elapsed` at 4 Hz inside `tick(now:)`; it publishes
`masterByteCount` on the same cadence, through the reader's `byteCount(of:)`. The brief then reads an
observable figure, and `_ = recorder.elapsed` (`:644`) — a discarded read whose only job was to
invalidate a body around a syscall — is deleted.

This gives `RecordingReading` its second consumer, which is the honest justification for it being an
interface rather than a closure. It is deliberately last and separately revertable: if publishing a
figure from the run turns out to fight the cadence rules candidate 1's §6 pins, drop this phase and
keep the seam. Phases 2-4 do not depend on it.

Also here, and small: `CaptureRunTests.swift:435-440`'s two real CAFs (candidate 1's §5 test 26,
written with a note to delete the fixture when this lands) become two one-line `Recording`s.

### Phase 6 — the record
*New:* `docs/adr/0044-a-recording-is-read-once-at-one-seam.md`. *Changed:* ADR-0021 and ADR-0031
get a one-line pointer; this plan gets its `As built` section.

0044 is the next free number. Follow ADR-0043's shape, which is the repo's own precedent for putting
a seam under a spine: an H1 that is a declarative sentence naming the decision, unlabelled context
prose, `## Consequences` naming the tests that pin each one, `## Considered and rejected`. Amending
an existing ADR in place is established here (ADR-0022's last bullet was edited to say "closed by
ADR-0043"), so ADR-0021 and ADR-0031 get a pointer rather than a new ADR each.

One ADR, covering what is a decision rather than a refactor:

- a Recording's facts are read **once, by one module**, and the Recording itself opens no files;
- the reader reads whole files and never single fields, which is ADR-0021's rejected alternative (a)
  made unexpressible rather than merely unwise;
- `Recording` stays a reference type, and why (§0) — identity is ADR-0021's mechanism;
- `source` splits so the xattr is cached and the filename parse is not, and why that is not a
  rounding of the same thing;
- one notion of a Recording's date, so ADR-0031's sort/group agreement is structural;
- the reader is the only module in the app that opens a file to answer a question about a Recording.

---

## 6 · Behaviour that must not change

The suite cannot catch a regression in most of this yet — that is the condition being fixed — so this
is the review checklist for Phases 2 and 3.

| Behaviour | Why it is fragile |
|---|---|
| The length is read with a bare `stat`, never `resourceValues` | resource values cache on the bridged `NSURL` and would defeat ADR-0021's staleness check; the first implementation of it used `resourceValues` and a test caught it |
| `openedByteCount` is read **before** the decode | a file growing under the read must record a length no greater than the one `frameCount` came from, or a stale reading freezes in place (`Recording.swift:176-181`) |
| A typed-but-undecodable file is still adopted, `isOpenable == false` | ADR-0015: the user must see why their file will not play, and be able to delete it |
| A non-audio file is not adopted at all | the gate is `UTType` conformance to `public.audio`, read from content type, not extension |
| An xattr write never re-adopts the open Recording | xattrs sit outside `st_size`; if that broke, every gesture-end would destroy the live Trim ADR-0006 protects |
| A renamed, xattr-less file re-derives its Source from the new name | §3; the reason only half of `source` is cached |
| `recordedAt` is creation, with modification as the fallback | ADR-0031 changed this deliberately; a Recording across midnight files under the day it started |
| The sidebar's order is newest-first, and within a day too | `RecordingDay.group` takes within-day order from its input (§4) |
| A growing master's `Master` row states a current figure, not an em dash | ADR-0031; a file merely *arriving* in the Library keeps the em dash, because nothing is watching it |
| `RecordingMetadata` stays `nonisolated` | the capture writer thread drives it (ADR-0022); the reader calls it rather than absorbing it |
| The selection rebinds when the store re-adopts | `EditorModel.swift:128`'s `!==`, which §0 is about |

---

## 7 · Verification

```
xcodebuild -project AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' test
```

The test target does **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` while the app target
does (`project.pbxproj:348`, `:418-420`), so new suites touching `Recording`, `LibraryStore` or the
reader carry an explicit `@MainActor` on the struct, as `LibraryStoreTests.swift:13` and
`CaptureRunTests.swift:18` already do.

By hand, once, after Phase 3: open the editor on a multi-day Library and check the sidebar's order,
its day headers and the window subtitle; type in the search field; rename a Recording in Finder and
confirm the row follows; record → stop and confirm the editor opens on the new Recording with a
correct `Captured` row and a growing `Master` row.

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:34-48`), so new files
under `AppTape/AppTape/` and `AppTape/AppTapeTests/` join their targets with no project-file edit.

## 8 · Out of scope

- **Views reaching through to singletons** (candidate 3). `RecordingBrief` keeps
  `RecordingController.shared`; Phase 5 changes what it *reads*, not how it gets it. The same
  candidate owns `isStillArriving`, which is re-derived at seven sites in `ExportInspector` alone
  (`:39, :71, :189, :266, :292, :391, :424`) — a single decision each of those sites forwards. It is
  a real finding and it is not this change.
- **`EnvelopeLoader.load` runs for every Recording on every refresh** (`LibraryStore.swift:66`), not
  only for new ones. Worth an issue; not worth folding in here.
- **ADR-0010's Seams xattr key still disagrees with the shipped one** (`com.samwongml.apptape.seams`
  versus `com.apptape.seams`, which `RecordingMetadata.swift:26-27` documents). The reader does not
  centralize key names — `RecordingMetadata` keeps them — so this change is not the occasion to fix
  the ADR.
- **The Export dock's refusal** (candidate 4) and **the timeline's two mappings** (candidate 5).
  Both get easier once a `Recording` is one line, and neither is touched here.
- **`Envelope`/`EnvelopeLoader`.** It reads audio, asynchronously, and it has no tests either — but
  it is a scan, not a fact, and it is its own seam.
- **`AudioPlayer`, `ExportEncoder`, `LoudnessAnalyzer`.** They open the file to *use* the audio.
  "The one module that opens a file" means the one module that opens a file to answer a question
  about a Recording.
- **`AudioFixtures` itself.** It stays: Phase 4 leaves four cases that genuinely need a real CAF,
  and `CAFMasterWriterTests`, `ExportEncoderTests` and `LoudnessExportTests` all need real audio.

## 9 · Size

| Phase | Files | Net lines |
|---|---|---|
| 1 · the plan | +1 | +~350 |
| 2 · `Recording` + `RecordingReader` | +1 ~3 | +130 |
| 3 · the store over the interface | ~1 | ±40 |
| 4 · the double + the tests | +3 ~1 | +350 |
| 5 · view bodies stop stat'ing | ~5 | ±60 |
| 6 · the record | +1 ~3 | +90 |

Roughly +600 lines of app and test code, of which ~440 are tests and the double, against a type
whose consumers have none. The suite's 251 cases gain ~26, all of them over logic that has been
shipped and churning for weeks — `EditorView` alone changed 12 times in three days — with nothing
able to hold it still.

---

## As built — Phases 5 and 6

The suite went from 283 cases to 288, green, with no warning of its own in either target.
`docs/adr/0044-a-recording-is-read-once-at-one-seam.md` is written; ADR-0021 and ADR-0031 each carry
a pointer to it, in place, as ADR-0022's "closed by ADR-0043" bullet did.

| file | change |
|---|---|
| `CaptureRun.swift` | +42/−15: `masterByteCount`, a fourth dependency, `publishElapsed` → `publishFigures` |
| `EditorView.swift` | +11/−10: the `stat`, the discarded `elapsed` read and the `reader` parameter go |
| `RecordingController.swift` | +6/−4: the production reader, and one forward |
| `LibraryStore.swift` | ±1: `reader` is `private` again, as Phase 4 predicted |
| `CaptureRunTests.swift` | +93/−1: five cases, and a `StubRecordingReader` in the `Rig` |

**The handoff recommended option B and the code refused it.** `Capturing.masterByteCount` — the
capture weighing the file it is writing — needs `CoreAudioCapture` to hold that file's url, and the
only place it exists is `CaptureEngine.writer`, which is documented writer-thread-only state
("reached by the main thread only after `finished` is signalled"). Reading it from the main actor is
a data race, and the honest workarounds all end in a URL box threaded through the builder's hooks so
that the capture can learn its own path after construction — more machinery than option A's one
stored property. So the run takes the reader as a fourth dependency, which is also what §5's own
Phase 5 said before the handoff second-guessed it. `RecordingReading` gets its second consumer
either way.

**One publish, not two.** `publishElapsed` became `publishFigures` rather than gaining a sibling:
the 4 Hz gate is shared, so the two figures cannot drift into different cadences, and the reason is
the same twice over — the menu bar observes `elapsed`, and ADR-0028 forbids a byte count ticking
twenty times a second.

**Five cases, not three.** The three the handoff asked for, plus
`theMastersSizeCostsOneStatPerClockTickRatherThanOnePerTick` — which counts the stub's probes over a
second of 20 Hz ticks, and is the only one that pins *the syscall moved* rather than what it
returns — and `aMasterThatCannotBeStattedPublishesNoFigureRatherThanZero`, because `nil` and `0`
render as different sentences in the `Master` row.

**The by-hand pass was run, and it holds.** §7's real-app checklist — record → stop, and watch the
`Master` row count up — needs the System Audio Recording grant, a Source making noise and a human
looking at the window, so no test can stand there. The figure reads right on screen at 4 Hz.

**One inherited number was wrong.** Phase 4's as-built says `writeCAF` call sites "fell from 26 to
23". Measured against the branch: `main` has 40, the Phase 2/3 commit 42 — the mechanical
`Recording(url:)` → `reader.adopt(_:)` rewrite added two — and Phase 4 cut them to 23. ADR-0044
states 40 → 23; the sentence above is left as it was written.

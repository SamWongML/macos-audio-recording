---
status: accepted
---

# 0049. The envelope cache is derived data, and is keyed on the file

Opening the editor decoded every master in the Library, every launch. Three things compounded:
`EnvelopeLoader.scan` was silently main-actor isolated (see
[ADR-0022](0022-explicit-nonisolated-background-work.md)), `LibraryStore.refresh()` scanned every
file it listed rather than the ones a row was showing, and nothing was ever kept — `envelopeState`
dedupes within one process, which is exactly why the symptom was worst on the first open after a
restart. The first two are bugs and were fixed as bugs. The third is this decision: the picture is
worth keeping between launches.

[ADR-0021](0021-growing-recording-re-adopted.md) named the shape in advance — *"If that ever becomes
a real cost, the fix is an incremental envelope, not a return to keeping a reading past its truth."*
This is the weaker, sufficient half of that note: not an envelope built incrementally as a file
grows, but a finished one filed where a later launch can find it.

**The decision: a Recording's envelope is cached under
`~/Library/Caches/com.samwongml.AppTape/peaks/`, keyed on the file's device, inode and length, and a
cache hit supplies an `Envelope` and nothing else.**

[ADR-0006](0006-library-is-a-folder.md) refuses the app an index of its own, and neither of its two
objections reaches this. The `Library.json` objection is that a rename in Finder reads as one
Recording vanishing and another appearing, which *silently drops a Trim* — a fact the user created
and cannot get back. The location objection is that `~/Library/Application Support` is invisible,
and at 1.4 GB/hour the user must be able to see and reclaim what this app puts on the disk. A
throwaway picture cache is neither: nothing in it is a fact, losing the whole folder costs one
rescan per Recording, and it is a few megabytes against a Library measured in gigabytes. It is also
rename-proof by construction, because it is keyed on the inode rather than the path — the same
identity `reconcile` already follows a rename with.

## Consequences

- **The key is ADR-0021's invalidation rule, reused rather than reinvented.** `dev`+`inode` survives
  a rename or a move within the volume; `st_size` changes the moment the audio does. A file that
  grew therefore keys differently, misses, and is rescanned — which is the same condition, on the
  same number, that decides whether `reconcile` keeps a Recording's object or re-adopts it. There is
  no second notion of staleness to keep in agreement with the first.
- **A corrupt cache degrades to a rescan, never to a wrong picture.** A wrong magic, an unknown
  version, a length that disagrees with the header's bucket count, or a file shorter than the header
  all read as a miss. `aCorruptCacheFileFallsBackToAScan` drives all four.
- **A hit supplies the picture and nothing else.** Duration, frame count, Trim, Gain, Dropouts and
  Source keep coming from `RecordingReader`, so
  [ADR-0044](0044-single-recording-read-point.md)'s single read point is untouched. This is worth
  stating plainly because a cache file that already knows the sample rate is an inviting place to
  put the rest, and the moment it holds a fact it is the index ADR-0006 refused.
  `aCachedEnvelopeCostsNoAudioRead` deletes the audio before the second load, so the test can only
  pass if the cache answered — and only the picture is asserted on.
- **The cache is purged against the folder, not swept on a timer.** `LibraryStore.refresh()` drops
  every key no current Recording claims, on a background task, because nothing is waiting on it. The
  store takes the cache directory as a dependency and the test-facing initializer defaults it to
  nil, so a suite that lists an imaginary folder cannot delete the developer's real cache.
- **Listing the folder is debounced, because the purge rides on it.** The folder watch fires on
  every write in the directory, which during a capture is continuous, and app activation fires on
  top of it. Listing per write was already wasteful; with a purge hanging off each listing it would
  spawn a background task per buffer flush. `refreshSoon()` collects a burst into one listing, and
  both triggers go through it — the unconditional listing on editor open does not, because that one
  is the guarantee [ADR-0021](0021-growing-recording-re-adopted.md) asks for and must not be
  deferred behind a window. `aBurstOfFolderWritesRelistsOnce` pins the coalescing.
- **Scans are admitted three at a time.** Starting one per file competed for the same cores and the
  same disk and finished the set no sooner, while making the first row later. The queue is plain
  main-actor state because `load` is main-actor, so it needs no lock, and `EnvelopeState` gained a
  `queued` case so the cap is observable rather than inferred.
- **The folder is listed lazily and the rows ask for themselves.** `LibraryStore.refresh()` no
  longer scans what it lists; `LibraryRow.onAppear` loads the envelope for a row that is actually on
  screen, and `EditorModel.select` still loads the selected one. The `onAppear` is the one line of
  this work no test covers, which [ADR-0018](0018-no-xcuitest-layer.md) is the reason for — the
  model-level halves are pinned by `theStoreDoesNotScanEveryRecordingItLists` and
  `loadingOneRecordingLeavesTheOthersIdle`.

## Considered and rejected

**A sidecar next to the master**, `Recording.caf.peaks`. It would ride the rename for free without
an inode key, and it fails ADR-0006's own test harder than anything else here: the Library is a
folder the user reads in Finder, and doubling its file count with files they did not make and cannot
interpret is the opaque store that ADR-0006 exists to refuse.

**An xattr on the master.** Attractive, because Trim, Gain, Source and Dropouts already live there
and it would survive `cp` and a rename with no key at all. Rejected on size: xattrs are the store for
facts a user created, measured in bytes, and a 20-minute master's envelope is megabytes. It would
also put derived data inside the thing ADR-0003 calls immutable.

**Keying on the path.** Free to compute and wrong in exactly the way ADR-0006 warns about: a Finder
rename would miss, and the old entry would linger until a purge. The inode was already being read
for `reconcile`, so the better key cost nothing.

**Purging on a schedule, or never.** Never is unbounded growth over a Library the user edits in
Finder. A schedule needs a trigger this app does not otherwise have. Listing the folder is already
the moment the set of live keys becomes known, so the purge goes where the knowledge is.

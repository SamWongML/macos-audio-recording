# A Recording that grew is re-adopted, not followed

`LibraryStore.reconcile` keeps the **same `Recording` object** for a file that survives a refresh, and
[ADR-0006](0006-the-library-is-a-folder.md) is why: the Library is an ordinary folder that Finder may
rearrange at any moment, so a refresh must not throw away a live Trim, a built envelope, or the open
editor's window. That rule is about *identity* — this is the same file — and it was quietly doing a
second job it was never fit for: preserving a *reading*.

A `Recording` reads its file once, in `init`. `frameCount`, `sampleRate`, the channel count, the bit
depth and the Seams are all `let`s taken at that moment. For a finalized master that is exactly right,
because [ADR-0003](0003-immutable-lossless-caf-master.md) makes it immutable. For a file **still being
written** it is wrong, and the same-object rule then made it permanently wrong: a master is created at
the first sound ([ADR-0016](0016-a-recording-begins-at-the-first-sound.md)) and grows for the rest of
the capture, so the Library adopts it at ~0 frames and every later refresh dutifully hands back that
first, empty reading. The symptom was that a Recording you had just made showed `Whole Recording ·
0:00`, `Length 0:00` and an empty lane until the app was relaunched, while the file on disk was a
minute long (issue #80).

**The decision: reconcile keeps a Recording's object only while the file still has the data length
that Recording read.** A file that has grown or shrunk since is re-adopted — a fresh `Recording`,
freshly read — rather than followed. The condition rides on both keep-the-object paths, the unchanged
path and the device+inode rename match, and the rename path asks about the *new* path because the
surviving object still holds the old one.

Re-adoption is safe precisely where following was not. A re-read Recording picks its Trim and Gain
back up from the extended attributes, which is where they live anyway; what it discards is an
envelope scanned from audio that has since changed and a Trim computed against a length that was
wrong. Nothing worth keeping is lost, because a reading of a file that is still being written is not
worth keeping.

## Consequences

- **Extended attributes must stay outside the data length, and they are.** Trim, Gain, the Source and
  the Seams are all xattrs, and writing one leaves `st_size` untouched (measured, including a 2 KB
  Seams blob). If that were not so, every gesture-end would silently re-adopt the open Recording and
  destroy the very live Trim ADR-0006 exists to protect. A test pins it:
  `persistingTheTrimAndGainDoesNotCostTheRecordingItsObject`.
- **The length is read with a bare `stat`, not `URL.resourceValues`.** Resource values are cached on
  the bridged `NSURL`, so asking the same URL twice can return the length from before the file grew —
  exactly the staleness being tested for. `FileIdentity` already reached for `stat` for the same
  reason. This was not a theoretical worry: the first implementation used `resourceValues` and the
  test caught it.
- **The selection has to rebind.** `EditorModel` holds the selected `Recording` by object reference,
  so a re-adopt would otherwise leave the editor rendering the object the store just dropped.
  `reconcileSelection` now rebinds when the store holds a different object at the same url, which also
  reloads the player and rebuilds the envelope. `AudioPlayer.load` likewise keys on object identity
  rather than the url, or it would decline to reload and keep playing the old, short segment.
- **Opening the editor re-lists the folder.** `store.start()` re-lists only on its first call, and the
  folder watch fires on directory writes, which the last seconds of a growing master do not produce.
  Without an unconditional refresh in `EditorModel.activate` the just-finalized Recording would still
  be read at its creation length.
- **It fixes a case capture does not know about.** A large file still being copied into the Library by
  hand is adopted part-written today ([ADR-0015](0015-an-adopted-file-is-faithful-or-refused.md)) and
  was stuck the same way. Telling the store "re-read *this* path" from capture-end — the obvious
  narrower fix — would have left that one broken.
- **A growing file is re-scanned each time it is re-listed, and that is the price.** The old rule
  kept the object, and with it the envelope `EnvelopeLoader` had already built, so a refresh cost
  nothing. Re-adoption throws that away, so opening or activating the app repeatedly during a long
  capture rescans the master each time. It buys a waveform that matches the audio actually there
  instead of a stale one, and refreshes during a capture are rare — the folder watch fires on
  directory writes, which a file merely growing does not produce, leaving app activation as the only
  trigger. If that ever becomes a real cost, the fix is an incremental envelope, not a return to
  keeping a reading past its truth.
- **A Recording whose audio is still arriving is drawn as such, not drawn wrongly.** The lane always
  fits the Recording to the width, so a reading of a file still being written gets stretched across
  it as though it were the whole thing — which is how a fraction of a second read as a solid slab.
  The condition is `RecordingController.isStillArriving`: no frames, **or** this is the Recording
  being captured right now. Both halves are needed, and driving the real app is what proved it — a
  master is adopted moments after the first sound creates it, so it has a *tiny* frame count rather
  than none (51 frames, ~409 bytes, measured), and a zero-frames test missed it entirely. The lane
  says `Still capturing` or `No audio yet`, Play is disabled with it, and the transport stops
  claiming a length it has not read. A live growing waveform is a real thing to want, but it needs
  an incremental envelope and a live length; it is not this.

## Considered and rejected

- **Make `frameCount` mutable and re-read it.** Everything else read at open — `sampleRate`, the
  channel count, the bit depth, the Seams, the Trim clamped against the duration — would have to be
  re-read with it and the Trim re-clamped. That is re-adoption with extra steps, and it keeps an
  object identity whose only remaining value is avoiding an envelope rescan the growth has invalidated
  anyway.
- **Have capture-end tell the store to re-adopt that one path.** Narrow, imperative, and it couples
  `RecordingController` to `LibraryStore` to fix one of the two ways a part-written file gets adopted.

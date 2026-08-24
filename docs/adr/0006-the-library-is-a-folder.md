---
status: accepted
---

# The Library is an ordinary folder, and a Recording's metadata rides in extended attributes

The Library is `~/Music/AppTape/`, a **visible folder the user may edit in Finder**, and the app keeps **no index of its own**: the folder is the truth, a Recording's **filename is its name**, and its Trim, Gain and Source are stored as **extended attributes on the file itself**. The forcing fact is the master's size — [ADR-0003](./0003-immutable-lossless-caf-master.md) puts a Recording at 1.4 GB/hour, which makes the Library by far the largest thing this app puts on the disk, and an opaque store would leave the user unable to see or reclaim that space without going through our UI.

## Considered options

**The location** was decided on permission cost and visibility. The only folder-scoped TCC services on macOS 27 are `kTCCServiceSystemPolicyDesktopFolder`, `…DocumentsFolder` and `…DownloadsFolder`, plus the network- and removable-volume services and `AllFiles` — verified by enumerating them out of `tccd`. So `~/Music` and `~/Movies` cost an unsandboxed app **zero prompts**, while `~/Documents` would cost one on top of the audio-capture grant this app already has to ask for, and would ride iCloud Desktop & Documents sync where it is enabled. `~/Movies` is where the system's own screen recordings land, but our output is audio. **`~/Library/Application Support/AppTape`** is the conventional answer for app-managed data and was rejected precisely *because* it is invisible: at 1.4 GB/hour the user's disk fills with no visible cause.

**The metadata store** had three real candidates. A **`Library.json` index** keyed by filename is simple and inspectable, but a rename in Finder reads as "one Recording vanished, a new one appeared" and silently drops its Trim. A **package directory per Recording** (`… .apptape/` holding `audio.caf` plus `meta.json`) carries metadata perfectly and renames atomically, at the cost of a declared UTI and of the user no longer being able to drag the audio straight out. **Extended attributes** won because they are the only option that keeps "the filename is the name" honest without inventing a document type: verified on this machine, they survive `mv`, a move into another directory, plain `cp` (macOS `cp` preserves them by default, unlike GNU `cp`) and an APFS clone.

**Writing Trim into the CAF's own `info` chunk** is possible and is the official Core Audio mechanism, and it was rejected for a specific reason: it would mutate a file [ADR-0003](./0003-immutable-lossless-caf-master.md) promises never to mutate, and that promise is exactly what buys the crash-safety story. Extended attributes leave the file's bytes untouched, so write-once stays literally true.

**A user-relocatable Library** was rejected for v1. It is a genuine want — 1.4 GB/hour on a small internal SSD is a real reason to prefer an external drive — but a movable Library drags in relocating existing Recordings and handling an absent volume mid-Recording. A symlink at `~/Music/AppTape` is a fair v1 escape hatch and costs nothing.

## Consequences

**Finder is a legitimate second UI, so the app cannot assume it owns the folder.** It watches the directory with a `DispatchSource` and re-reads on activation. A file that vanishes from disk vanishes from the Library, and if it was open in the editor the editor says so and closes rather than holding a stale window. A rename is followed silently, because the xattr identity travels with the file.

**Any playable audio file dropped into the folder is adopted** as a Recording with default metadata — no Trim, no Gain. Showing it plainly beats hiding a file the user deliberately put there. This widens what a Recording can be: the app will open, Trim and Export audio it never captured, whose sample rate and channel count it therefore did not choose. The limits of that are settled separately.

**Losing the xattrs degrades gracefully rather than corrupting anything**: a Recording copied to a FAT volume or round-tripped through a network share arrives with its Trim reset to the full length and its Gain at zero. The audio is never at risk, because the audio is the file.

**The CAF is written in place at its final path from the first sample**, named from the **start** time. Temp-then-move was rejected because it would waste ADR-0003's crash guarantee: a Recording killed by an app crash is already a well-formed file, and it should already be *in the Library* rather than orphaned in a temp directory the Library never scans. The visible consequence is that a `.caf` is seen growing in Finder mid-Recording. Name collisions cannot arise in practice — one Source at a time, second resolution — but resolve by appending ` 2` rather than overwriting, since overwriting a master is unrecoverable.

**Deletion is `FileManager.trashItem(at:)` with no confirmation**, because the Trash *is* the undo and a confirm sheet is the wrong tax to charge someone trying to reclaim disk. Masters are marked `isExcludedFromBackup`: a 1.4 GB/hour immutable intermediate has no business in Time Machine when the Export is the artifact worth keeping.

**Exports do not live in the Library at all.** Export puts up a standard save panel, name pre-filled from the Recording and extension from the Quality Preset, defaulting to the last directory used. The master is an intermediate and the Export is the deliverable; filing them side by side would make the user sort a 1.4 GB `.caf` from a 12 MB `.m4a` by extension. Deleting a Recording never touches a file already Exported from it.

Settled in issue #10.

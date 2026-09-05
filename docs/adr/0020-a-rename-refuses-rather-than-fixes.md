---
status: accepted
---

# The Library shows the name you chose, and a rename refuses rather than fixes

[ADR-0006](./0006-the-library-is-a-folder.md) made the Library an ordinary folder, a Recording's **filename its name**, and a rename something the app **follows silently** when Finder does it. This is the other half: the app doing the rename itself, from a row action in the sidebar. Two things had to be decided that ADR-0006 never had to face, because it was only ever *watching* a rename someone else made — **what the Library then shows**, and **what happens to a name it cannot use**.

## The Library shows the Source until you name a Recording yourself

A sidebar row shows `displayName`: the **Source** while the filename still matches the one capture generated, the **user's own name** once it does not.

The forcing fact is that a captured Recording's Source rides in an xattr, not in its filename. The row has always shown the Source, because the rest of a generated name is the date and time the row already prints in its own column — but that means renaming `Google Chrome 2026-08-27 at 20.05.03.caf` to `Interview.caf` would change nothing the Library shows. Four rows would still read *Google Chrome*, which is exactly the confusion the rename was reaching for. A rename nobody can see is not a feature.

**Showing the filename always** was rejected because it puts the date and time on the row twice and loses the one thing the Source column is good at. **Rewriting the Source xattr to match the new name** was rejected outright: the Source is a fact about where the audio came from, not a label, and a Recording that has forgotten which app made it cannot get that back. It stays untouched and remains the window's subtitle, so both facts are visible at once — *this is the interview*, and *it came from Chrome*.

The predicate is `LibraryLocation.baseName`'s own pattern, optionally carrying `uniqueFileName`'s ` 2` suffix. A hand-adopted file never matched it in the first place, so it has always shown its filename and continues to.

## Refuse, don't fix

Four names are rejected rather than corrected: **empty** (or nothing but whitespace), one containing **`/` or `:`**, one **beginning with a dot**, and one that **collides** with another file in the Library. The field stays open with what was typed still in it, and a popover on the row says which of the four it was.

This is the opposite of what capture does two functions away, where `uniqueFileName` resolves a collision by silently appending ` 2`. The same question gets two answers for a reason worth writing down: **capture has nobody to ask.** A rename does. Turning the `Interview` someone typed into `Interview 2` without saying so is a lie about what they asked for, and they are right there to be told.

Two of the four are not manners but safety, and they are why this ADR exists at all:

- **A leading dot** would hide the file, and `LibraryStore.audioFiles(in:)` lists with `.skipsHiddenFiles`. The Recording would drop out of the Library and the editor would close on it as a vanish — a rename that reads as a deletion.
- **An edited extension** would fail `Recording.init?`'s `public.audio` adoption gate ([ADR-0015](./0015-an-adopted-file-is-faithful-or-refused.md)) with the same result, so the extension is **never the user's to edit**. They type the base name; the extension is carried over.

## Consequences

**Leading and trailing whitespace is trimmed, not refused.** Whitespace at the ends carries no meaning, so trimming it changes nothing the user meant — unlike suffixing a collision or dropping a character. A name that is *only* whitespace is empty, and refused.

**A case-only rename is allowed.** `podcast.caf` → `Podcast.caf` is the same file and cannot collide with itself, so the current file is excluded from the collision scan case-insensitively. The scan itself is case-insensitive because the default APFS volume is.

**The open Recording survives its own rename.** The store relocates the same object and lets ADR-0006's device+inode reconcile follow the file, so the envelope, the live Trim and the editor window are all kept — the same guarantee a Finder rename already had.

**The File menu grows past Close ⌘W.** A context menu alone is undiscoverable and unreachable from the keyboard, so Rename, Reveal in Finder ⇧⌘R and Move to Trash ⌘⌫ are mirrored there. Finder is the model throughout: Rename carries no key equivalent, because Return does it in the list. **Move to Trash is gated on the sidebar having focus** and the other two are not — ⌘⌫ moves a file to the Trash, and firing that out of a search field someone is typing into is the one outcome worth spending a focus value on.

**The row-action set is exactly three.** `Duplicate` is deliberately absent: a master is 1.4 GB/hour ([ADR-0003](./0003-immutable-lossless-caf-master.md)), and the other reading — one master carrying a second Trim — has nowhere to live under ADR-0006, which makes the folder the only truth.

Settled in issue #75.

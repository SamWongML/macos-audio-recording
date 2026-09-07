# ADR-0031: A growing Recording states the engine's figures, or nothing

**Status**: Accepted
**Date**: 2026-09-07
**Issue**: [#98](https://github.com/SamWongML/macos-audio-recording/issues/98)

## Context

[ADR-0021](0021-a-recording-that-grew-is-re-adopted.md) settled that a `Recording` describes the
file *as it was when it was read*, and that a file which has since grown is re-adopted rather than
followed. [#80](https://github.com/SamWongML/macos-audio-recording/issues/80) applied that to the
lane and the transport: while audio is still arriving the lane says `Still capturing`, Play is
disabled, and **no length is claimed**.

It stopped there, and the rest of the window did not get the message. Driving a real capture and
looking at it, five surfaces were stating numbers they had taken from the last folder listing:

| surface | what it said | against |
|---|---|---|
| sidebar row's duration | `0:00`, frozen | a 2:18 capture |
| brief's `Master` | `—` | 53.1 MB on disk |
| brief's `Captured` | ticking forward as you watched | one moment of capture |
| Export ladder's four estimates | `≈ 630 KB` | a master past 60 MB |
| ruler | `0:00 0:01 0:02 0:03` | a lane drawing nothing |

Two mechanisms are behind all of it, and neither is obvious from the code that suffers:

**The Library is not re-listed while a master grows.** `LibraryStore` watches the folder with a
`DispatchSource` on `.write`, and **appending to a file does not touch its directory's mtime** —
measured, not assumed. So the folder is listed once at the first sound and then not again until the
app is activated. Every figure derived from that listing is not merely stale, it is *fixed* for the
duration of the capture.

**`contentModificationDate` on a growing file is now.** The `Captured` row read it, so it advanced
every time the Recording was re-adopted — and a Recording that ran across midnight was filed by
`RecordingDay` under the day it *stopped*.

The premium reading of this ticket was a live growing waveform. Three lane treatments were built
into the running app behind a switcher and judged against a real capture of QuickTime Player
(`prototype/editor-during-capture`): today's `Still capturing`; the panel's rolling level monitor
moved into the lane; and a growing whole-capture picture.

## Decision

**While a Recording's audio is still arriving, the editor states the engine's own figures, or it
states nothing. It never draws a picture of it.**

The engine already knows what the listing does not: `RecordingController.elapsed` is the master's
real frame count, published at 4 Hz. That is an honest length, and everywhere the window wanted one
it now uses that:

- the **transport** states what has been captured so far, in the Trim readout's reserved slot so
  the bar does not reflow when the capture ends;
- the **sidebar row** counts up in its duration slot;
- the brief's **`Master`** row states what the file weighs right now, from a bare `stat`.

Everywhere a *picture* or an un-derivable number was being drawn, nothing is drawn:

- the **lane** keeps `Still capturing`;
- the **ruler** draws no ticks — no duration means no ticks, not one tick at zero;
- the **sidebar silhouette** is withheld, because the envelope is a scan of a prefix drawn as
  though it were the whole Recording — [#80](https://github.com/SamWongML/macos-audio-recording/issues/80)'s
  lie, still living in the sidebar;
- the **Export ladder's estimates** read `—`, because the dock two rows below already refuses the
  export ([ADR-0012](0012-export-is-non-blocking-and-cancels-on-navigation.md)) and a confident
  size for an impossible export is the inspector disagreeing with itself.

And `recordedAt` becomes **creation, not last write**, with modification as the fallback.
`LibraryStore`'s sort key moves with it, so the folder's order and `RecordingDay`'s grouping cannot
disagree about what a Recording's date is.

## Why not the growing waveform

It was built, and it looks good — at 2:18 it reads as a proper dense envelope. Two things ruled it
out, and the first is the one that matters:

**The lane is the Trim surface, and there is nothing to trim.** The Trim's end is undefined until
Stop (ADR-0012); there is nothing to scrub, nothing to play, no handles to place. A real waveform
there makes an inoperable surface look operable, which is a worse lie than a blank one.

**It is ambient motion, and this app has a rule about that.** `TrimTimeline`'s contract is *the
Recording always fits the width*, so a growing picture shifts and compresses continuously. Judged
live rather than argued: the compression is gentle — `1/elapsed` per tick, 0.04% at 2:18 — but a
new column arrives at the right edge twenty times a second and everything already drawn slides
left, forever, without the user having done anything.
[ADR-0028](0028-motion-is-feedback.md) says motion is feedback: something moves to confirm an
action the user took, or to mark a state change they must notice. A waveform growing because time
is passing is neither, and the ADR's forbid-list has no exception for the lane.

The live level monitor (the panel's rolling meter, moved into the lane) was rejected for the first
reason alone: it is a meter in the Trim surface, and it duplicates what the panel's own row already
shows a click away.

**What was rejected is the picture, not the liveness.** Every number in the window is live now;
that is the whole decision. The blankness the map was chartered against is answered by the figures
around the lane, not by filling the lane.

## Consequences

- A capturing Recording is legible from the editor without the panel: the row counts up, the
  transport says how far in, the brief says what it weighs.
- **Two number formats in one column was a real risk and is closed by construction.** The engine's
  `elapsedText` is the menu bar's zero-padded `mm:ss` (`00:27`); every figure in the editor is
  `Format.time`'s `m:ss` (`0:30`). The sidebar showed both at once before this was one function.
- The `Captured` row's meaning changes for **existing** Recordings too — from when capture stopped
  to when it started. For a long Recording that is a real difference, and for one made across
  midnight it changes which day it is filed under. This is the correct meaning of the word and was
  taken deliberately, not as a side effect.
- The four Export estimates are the one place a live figure was *available* and deliberately not
  used. `elapsed` would make them true, but they would still be estimates for an export ADR-0012
  refuses; withholding is the smaller claim.
- A file merely arriving in the Library — a large copy in progress — keeps the em dash rather than
  the live figure. Nothing is watching it, so there is no current number to state.
- **[ADR-0027](0027-the-transport-reserves-its-widest-readout.md) can be undone one control to the
  right of where it was applied, and it was.** Written as two sibling branches — one for capturing,
  one for the Trim — the bar looked correct in both states and *jumped by the width of `Reset`* at
  the instant capture ended, because `Reset` was only in the second branch. Reserving the readout's
  width is not enough on its own: the whole trailing group has to be one group, with `Reset` in the
  layout while capturing too, disabled, as it already is when there is no Trim to reset. Caught by
  screenshotting the bar either side of a real Stop and comparing the glyph's position, which is
  the only way it shows up — a still of either state alone looks right.

## Notes

Judging this needed the level meter to work, and it did not: `CaptureEngine.drainOnce` published
the level on every drain, so ~30 empty drains stamped zero over each real peak and the meter read
silence on audio peaking at −2.0 dBFS. Fixed separately, in
[#100](https://github.com/SamWongML/macos-audio-recording/issues/100) — it lives in the capture
spine and surfaces first in the menu bar panel, which this map rules out of scope.

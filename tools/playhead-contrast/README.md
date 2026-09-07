# Playhead contrast harness — issue #105 / ADR-0033

The primary source for every number in
[ADR-0033](../../docs/adr/0033-the-playhead-is-an-instrument-not-content.md). This branch is
**not for merging**; it is the evidence, kept where it can be re-run.

## What was shot

The 1:30 Spotify Recording (`Spotify 2026-08-23 at 14.02.55.caf`, 34.6 MB, loud and continuous),
editor at `1200 × 680`, **Release** — in Debug every `Correction` row reads `Measuring…` (#80).
Both appearances, before and after.

| file | |
|---|---|
| `01-dark-before.png` | playhead `Signal`, over `Signal` peaks |
| `02-dark-after.png` | white @ 0.75 |
| `03-dark-after-loud.png` | the same, playhead crossing dense loud material |
| `04-light-before.png` | the half nobody had measured |
| `05-light-after.png` | black @ 1.0 |

## Re-running it

The playhead moves, so it is located by **differencing two frames 1.2 s apart** — everything else
in the window is static. `measure.py` prints the moving runs; the two narrow 3 px runs are the
playhead's old and new columns (the wide run at the right is the Trim boundary, not the playhead).

```sh
screencapture -x -o -l <windowID> A.png ; sleep 1.2 ; screencapture -x -o -l <windowID> B.png
python3 measure.py A.png B.png                       # find the playhead column
python3 rows.py B.png <cx> <peaks> <body> <ground>   # per-row contrast vs each fill
```

`rows.py` compares each row of the playhead column to its neighbours **at that row**, which is the
only correct way to do it: the ink composites differently over each fill, so a single "playhead
colour" is meaningless. Measuring it the wrong way is what first suggested `Color.primary` passed.

`winid.py <pid>` lists window ids; `click.py x y [n]` posts synthetic clicks.

## Two things that cost time

**Never click into the lane to move the playhead.** A click within 2% of the span of a Trim handle
grabs the handle instead of scrubbing, and the drag commits to the master's `com.apptape.trim`
xattr. Drive playback with the transport button instead.

**`Color.primary` is not ink.** It is `labelColor` — 85% ink — so a playhead built from it measures
3.13 : 1 (Dark) and 2.93 : 1 (Light) against the peaks where full-strength white and black give
4.07 and 3.17. Predicting from the token rather than the render is exactly what ADR-0032 forbids.

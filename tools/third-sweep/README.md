# Third-sweep harness (issue #108)

Throwaway. Drives the shipping Release build and photographs it; **never merged**. The one change
to app code is `SweepFlags` in `AppTapeApp.swift`, carried forward unchanged from
[`prototype/editor-after-sweep`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-after-sweep) (#103):
Reduce Transparency and Reduce Motion cannot be toggled from a script, so the six sites that read
them OR in a process-local flag. Every flag is off unless `APPTAPE_SWEEP_A11Y` names it, so every
other shot here is the shipping path.

## Scripts

| | |
|---|---|
| `launch.sh <WxH> <dark\|light> [a11y]` | Kill, write `NSWindow Frame editor`, set the appearance, launch, open the editor from the panel, dismiss the panel, raise. Prints the pid. |
| `shoot.sh <out.png>` | `screencapture -x -o -l <windowID>`; prints id and frame. |
| `loupe.sh <out> <grab-x> <to-x> <release-x> [lane-y]` | Drag a Trim handle and shoot **with the button held**. |
| `play.sh <prefix> <transport-x> <transport-y>` | Play, shoot twice 1.2 s apart, pause. |
| `scrub.sh <out> <lane-x> <lane-y>` | The one click into the lane, for the playhead over the trimmed-away region. |
| `pick.sh <row-y>` | Click a sidebar row. |
| `empty.sh <WxH:appearance:out> …` | Library aside, shoot, restore, counted both ways. |
| `cantopen.sh <WxH:appearance:out> …` | One undecodable fixture in, shoot, out, counted both ways. |
| `export-fail2.sh …` | 2 MB HFS+ image, narrow the Library, export onto it, shoot the failed dock. |
| `measure.py` / `lane.py` / `playhead.py` / `inkrows.py` / `probe.py` / `crop.py` | Contrast and fill measurement in **logical points**, so the same numbers work at any backing scale. |

## Rules this harness obeys

- **Shoot in Release.** In Debug the BS.1770 pass is ~82× slower and every `Correction` row reads
  `Measuring…` (#80, #103).
- **Launch fresh at a saved frame; never resize programmatically.** A `setFrame` before first
  layout produces a convincing artefact that is not a defect (#103).
- **Never click into the lane** without doing the arithmetic first: a click within 2% of the span
  of a Trim handle grabs the handle, and the drag commits to `com.apptape.trim`. #105 lost a real
  Recording's Trim that way. `loupe.sh` only ever drags an already-at-zero lower bound and releases
  at a hard-left clamp; `scrub.sh` targets a point many multiples of the tolerance clear of both
  handles. Every Trim in the Library was backed up before the run and re-read after: identical.
- **`AXRaise` before any synthetic click into the editor** — with the panel dismissed it is often
  not frontmost (#104).
- **Address the process by `unix id`**, never `process "AppTape"`: a second AppTape can be running
  and invisible (#111).

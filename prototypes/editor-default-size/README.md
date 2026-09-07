# Editor default size — measurement harness (issue #97)

**Throwaway.** Drives the *shipped* Release build through candidate window sizes and
measures the two things that actually constrain the number. Nothing here ships.

Run the app, open the editor, then:

- `win.sh` — the editor window's frame, via System Events.
- `open-editor.sh` — clicks the status item, then the panel's *Open Editor*.
- `sweep.sh <W> <H…>` — resize to each height, screenshot, report the lane's band.
- `lane.py <png> <W>` — the waveform lane's top/bottom/height, by pixel colour
  (lane ground is `(55,55,55)`, window ground `(48,48,48)`).
- `scroller.py <png> <W>` — is the trailing column drawing an overlay scroller?
  Looks for a long light-neutral run 3–14 pt in from the window's right edge.
- `libsweep.sh <H>` — arrow through all 39 Recordings at height `H` and report how
  many scroll the trailing column. **Run it twice**: the first pass over a freshly
  launched app under-reports, because a Recording whose BS.1770 pass has not landed
  still reads `Measuring…` with no caption, and the caption is what overflows.

## What it measured

| | |
|---|---|
| lane reaches its 340 cap | **620** — above this, extra height is air below the brief |
| trailing column stops scrolling | **642**, and **645** across the whole Library |
| window's real height floor | **552** — the content's, not the declared 500 |
| window's real width floor | **960** — the declared one |
| first open, nothing stored | **1120 × 640, centred** |

Forcing the longer of the app's own two captions (`amplificationCapped`'s
"limited to keep the noise floor down" in place of `ceilingReached`'s "peak ceiling
reached") moves the no-scroller height from 645 to **670** — the row goes two-line and
full-width. The number is a property of the strings, not of the layout.

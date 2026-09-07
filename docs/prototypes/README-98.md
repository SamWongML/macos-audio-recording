# Prototype: what the editor shows while a capture is in progress (#98)

Throwaway. Three lane variants behind a switcher (⌥← / ⌥→ or the pill's chevrons), judged by
driving a real capture of QuickTime Player playing 108 s of generated speech.

- `vA_crop.png` — **A**, today's `Still capturing`, at 0:25.
- `vB2_crop.png` — **B**, the panel's rolling level monitor in the lane, at 0:27.
- `d45_crop.png` / `d130_crop.png` — **C**, the growing whole-capture picture, at 0:48 and 2:18.
- `vC_final.png` — **C before it was made fair**: dB-scaled fills, unreduced, at 2:41. Kept
  because it is the prototype's own artefact and shows what nearly got the design rejected.

`drive.sh` + `click.py` + `statusclick.applescript` drive the whole thing. Two harness facts
they encode: AppTape's panel does not accept first mouse, so **every synthetic click has to be
sent twice**; and the status item's menu-bar index moves, so it is found by description.

## What varies and what does not

Only the lane. Every *number* going live is the shared base under all three: the transport's
readout, the sidebar row's duration slot and the brief's `Master` row read the engine's own
figures instead of the last folder listing.

## Fidelity limits, stated rather than buried

C stands in for the incremental envelope by accumulating `LevelMeter` fills at 20 Hz. Two
corrections were needed before it was a fair test, and both were the prototype lying, not the
design failing: the columns must be **peak-reduced to the lane's width** (as `Envelope.columns`
does) and the amplitudes must be **linear** (as `Envelope` is), not `LevelMeter`'s dB ramp.
Uncorrected, C saturated into a solid indigo slab inside two minutes.

What C still cannot show is the motion, because a still cannot: the newest column arrives at the
right edge ~20×/s and everything already drawn shifts left and compresses by `1/elapsed` per tick.

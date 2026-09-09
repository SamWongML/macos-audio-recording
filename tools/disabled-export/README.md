# Disabled Export button prototype (issue #125)

Throwaway. Drives the shipping Release build with five candidate shapes for the **blocked** Export
control, behind `APPTAPE_XBTN`, and measures each off a screenshot in **four** cells: both
appearances × window key / not key. **Never merged.** Forked from the
[unencodable-rung harness](https://github.com/SamWongML/macos-audio-recording/tree/prototype/unencodable-rung/tools/unencodable-rung)
(#119), whose rules all still apply — shoot in Release, launch fresh at a saved frame, centre the
window, `AXRaise` before any click, never click a sidebar row.

## Reaching a blocked state without a click

`ZZZ Zero Frame.caf` — a **valid, openable, zero-frame** `.caf` written by `AVAudioFile` with no
frames — gives `duration == 0`, so `Trim(duration: 0)` makes `trimmedDuration <= 0` and the control
blocks. Its creation date is pinned to **2028** so it always sorts newest and
`EditorModel.reconcileSelection` selects it on first open with no click. **Pin the date**: a real
capture landed in the Library mid-run once and outsorted an un-pinned fixture, silently voiding a
whole ladder — every variant measured the *enabled* figures.

A **can't-open** file also gets `Trim(duration: 0)` but can never show this: `inspectorColumn`
gives it `Color.clear`, so the dock is not rendered at all.

## Variants (`AppTape/AppTape/ExportButtonVariant.swift`)

| | | Dark key | Dark nokey | Light key | Light nokey |
|---|---|---|---|---|---|
| `a` | baseline — `.borderedProminent` + `.disabled()` | 3.00 | 2.24 | **1.75** | 1.85 |
| `b` | `.bordered` while blocked, prominent when available | 2.24 | 2.24 | 1.85 | 1.85 |
| `c` | prominent, label lifted out of the disabled scope | 7.04 | 15.72 | 2.86 | **1.23** |
| `d` | no control while blocked; sentence, `.secondary` | 6.02 | 6.02 | 3.89 | 3.89 |
| `e` | `d` with the sentence in ink | **12.66** | **12.66** | **13.87** | **13.87** |

Identical at `1200 × 680` and at the `960 × 656` floor.

## What this harness added

**The disabled prominent button is a double dimming, and it fits exactly.** The fill is the enabled
accent composited at **α ≈ 0.69** over the column's ground (Dark `(27,27,27)`, Light
`(242,242,242)`); the label is then white at a **further α = 0.50** over that already-dimmed fill.
Both fits are exact to ±0.5 of a level in both appearances. Light is the bad half only because its
ground is bright: fill and label both converge on it. So *"the fill stays saturated while the label
dims"* is right about the percept and wrong about the mechanism.

**`.bordered` is not a fix.** It removes the false affordance and leaves the contrast where it was —
a disabled bordered button is the same grey ghost the prominent one becomes in a non-key window.

**Window key state is a fourth cell, and it is not optional.** `a` reads 3.00 in a key Dark window
and 2.24 in the same window unfocused; the *enabled* button reads 10.33 / 12.05 there, because the
system drops the accent when the window is not key but keeps the label at full strength. Only `d`
and `e` are immune, because they sit on the column's ground rather than on a control fill.

**Nothing above the control moves.** A pixel diff of `a` against `e` at `1200 × 680` is confined to
`940–1184 × 639–663` — the control's own box. The dock keeps its declared height (ADR-0025).

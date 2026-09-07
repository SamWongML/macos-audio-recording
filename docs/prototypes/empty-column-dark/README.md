# Evidence for issue #111 — the empty trailing column in Dark

Six treatments for the trailing column's boundary, each photographed in **four states**: empty
column × populated column, Dark × Light. Shot on a **Release** build at `1200 × 680` (the map's
rule: in Debug every `Correction` row reads `Measuring…`), each one from a **fresh launch at the
saved frame** with `APPTAPE_COLUMN_VARIANT=<key>` forcing the variant, so no harness control is in
any picture.

The empty-column shots needed the Library moved aside. `EditorModel.reconcileSelection` selects
the newest Recording on first open, so *nothing selected* is not a state a fresh launch reaches —
the empty column is only ever seen on an **empty Library**, on a **can't-open file**, or after the
user deselects. #106's method: a same-volume `mv` aside with the restore in the same shell
invocation, counted both ways, **39 files → 39 files** on every run.

## The variants

| key | treatment | thesis |
|---|---|---|
| A | **As it stands** | the shipping build; a bare pane is the honest look of a pane with nothing in it |
| B | **Level the step** | appearance-aware scrim, so the step reads ~5% in both appearances |
| C | **Hairline, no step** | no fill difference at all; a 1 pt rule is the whole boundary |
| D | **Chrome material** | `.regularMaterial` — the instrument report 0006 measured in Xcode |
| E | **The empty column dissolves** | no fill and no rule while empty; the treatment returns with the ladder |
| F | **As it stands, reaching the top edge** | A's exact fill, run through the title bar |

## Measured, off the running app

Modal RGB of the detail pane and of the column, sampled low in the window where neither draws
content, with the WCAG contrast ratio between them.

**Empty column**

| variant | Dark detail | Dark column | Dark step | Light detail | Light column | Light step |
|---|---|---|---|---|---|---|
| A | `(40,40,40)` | `(27,27,27)` | 1.168 : 1 · **−32.5%** | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 · −5.1% |
| B | `(40,40,40)` | `(38,38,38)` | 1.026 : 1 · −5.0% | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 · −5.1% |
| C | `(40,40,40)` | `(40,40,40)` | 1.000 : 1 · +0.0% | `(255,255,255)` | `(255,255,255)` | 1.000 : 1 · +0.0% |
| D | `(40,40,40)` | `(43,42,43)` | 1.031 : 1 · **+7.5%** | `(255,255,255)` | `(234,234,234)` | 1.203 : 1 · **−8.2%** |
| E | `(40,40,40)` | `(40,40,40)` | 1.000 : 1 · +0.0% | `(255,255,255)` | `(255,255,255)` | 1.000 : 1 · +0.0% |
| F | `(40,40,40)` | `(27,27,27)` | 1.168 : 1 · −32.5% | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 · −5.1% |

The populated column measures identically to the empty one for every variant except **E**, which
is A when the ladder is there and C when it is not, by construction.

## Two things the measurements say that the ticket did not

**Deleting the black scrim in Dark would barely move the column.** `.controlBackgroundColor` is
`(30,30,30)` in Dark against a detail that draws `(40,40,40)`, so **ten of the step's thirteen
units are the system's own** and only three are the scrim. A column with no scrim at all lands at
30 — still 25% darker, still a hole. Closing the gap means lifting the column *toward* the detail,
which is a **white** scrim: the exact thing ADR-0032 ruled out when it said the column wants to be
darker in both appearances. That is variant B, and it is the ADR the decision has to overturn or
uphold.

**The column's fill starts 52 pt down, in every filled variant, in both appearances** — below the
title bar, with a square top corner against a rounded window. Report 0006's primary source is that
Apple does the opposite: Xcode's inspector seam *"starts at the literal top of the window"*, and
WWDC20's *Adopt the new look of macOS* calls dividers reaching the top of the window the point of
`fullSizeContentView`. This window hides its toolbar background (issue #7) so the body reads to the
edge, and then the column stops short of it. With content in the column the eye reads the content;
empty, it reads the rectangle. **F is A with only that closed**, so `A` vs `F` asks *is the gap the
defect?* while `A` vs `B`/`D` asks *is the darkness?*

## Files

`<appearance>_<state>_<variant>.png` — `dark`/`light`, `empty`/`full`, `A`–`F`.
`M_<appearance>_<state>.png` — the six cropped side by side.
`harness/` — the driver. `openeditor.py` carries one fact worth keeping: #98's *always click the
panel twice* is wrong once the click lands, because the panel closes and the editor opens under
the pointer, so the second click selects the first Library row and hits the transport. Five "empty
column" shots came back with `hhh` selected and playing at 0:06.57 before the second click was
made conditional.

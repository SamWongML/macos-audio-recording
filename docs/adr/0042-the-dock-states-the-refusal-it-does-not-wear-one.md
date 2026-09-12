---
status: accepted
---

# The dock states the refusal; it does not wear one

[ADR-0041](0041-the-reason-is-not-part-of-the-control.md) moved a *reason* out of a disabled control.
This moves the **refusal itself**. The Export dock's blocked state was a `.borderedProminent` button
under `.disabled(...)`, and its label measured **1.75 : 1 in Light** — the ticket that filed it,
[#125](https://github.com/SamWongML/macos-audio-recording/issues/125), found it while #119 was being
resolved, in the one state a doctored Library could finally reach.

**The rule: when an Export cannot be started, there is no Export button. The dock says why, in ink,
in its own sentence idiom.**

| | before | after |
|---|---|---|
| blocked control, Dark, window key | **3.00 : 1** | **12.66 : 1** |
| blocked control, Dark, window not key | **2.24 : 1** | **12.66 : 1** |
| blocked control, Light, window key | **1.75 : 1** | **13.87 : 1** |
| blocked control, Light, window not key | **1.85 : 1** | **13.87 : 1** |

Release build, both appearances, at `1200 × 680` and at the `960 × 656` floor
([ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md)). The enabled button is
untouched and still measures 4.54 : 1.

## The disabled prominent button is two dimmings, and they fit exactly

The fill is the enabled accent composited at **α ≈ 0.69** over the trailing column's ground; the
label is then white at a **further α = 0.50** over that already-dimmed fill:

| | ground | fill | label |
|---|---|---|---|
| Dark | `(27,27,27)` | `(41,83,179)` | `(148,169,217)` |
| Light | `(242,242,242)` | `(108,150,246)` | `(182,202,251)` |

Both fits are exact to ±0.5 of a level in both appearances. This is #119's mechanism — `.disabled()`
dims its subtree's text on top of dimming the control — seen on a control that has no text of its own
to exempt, which is why #119's fix has no analogue here.

**Light is the bad half only because its ground is bright.** Dimming pulls the fill *down* in Dark and
*up* in Light, and the label follows; in Light both converge on the ground. So the ticket's reading —
*"the fill stays saturated while the label dims"* — is right about the percept and wrong about the
mechanism. The fill is dimmed too; dimming toward white preserves chroma while destroying contrast,
which is exactly what makes the control still look pressable.

## Window key state is a fourth cell, and it is not optional

The same shipped button measured **3.00 : 1** in a key Dark window and **2.24 : 1** in the same window
unfocused, because the system drops the accent when a window is not key. The *enabled* button reads
**10.33 / 12.05** there — it keeps its label at full strength — so blocked-versus-available stayed
legible while the blocked word did not. Every figure in this ADR is therefore quoted in four cells,
not two. [ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md)'s column was verified
in Dark and wrong in Light for four tickets; this is the same trap one axis over.

## What was measured and rejected

| | shape | Dark key | Dark nokey | Light key | Light nokey |
|---|---|---|---|---|---|
| `a` | baseline — `.borderedProminent` + `.disabled()` | 3.00 | 2.24 | **1.75** | 1.85 |
| `b` | `.bordered` while blocked, prominent when available | 2.24 | 2.24 | 1.85 | 1.85 |
| `c` | prominent, label lifted out of the disabled scope | 7.04 | 15.72 | 2.86 | **1.23** |
| `d` | no control while blocked; sentence, `.secondary` | 6.02 | 6.02 | 3.89 | 3.89 |
| `e` | `d` with the sentence in ink — **ships** | **12.66** | **12.66** | **13.87** | **13.87** |

**`b` was the expected answer and it is not one.** Dropping to `.bordered` removes the false
affordance and leaves the contrast where it was: a disabled bordered button is the same grey ghost the
prominent one becomes in a non-key window. It fixes what the control *claims* and not what it *says*.

**`c` is why the rule is not simply #119's rule again.** A full-strength label on a still-prominent
fill measures well in Dark and collapses to **1.23 : 1** in an unfocused Light window — and it lies:
a control that looks completely live but cannot be pressed is a worse defect than an unreadable one.
A control cannot be told to keep its label and lose its affordance. It can only be removed.

## The trade

**The Export dock loses its button whenever an Export cannot start.** A user who expects a control in
that slot finds a sentence instead, and there is no longer a greyed thing to point at. That is
accepted because the three blocked states all have something to say, the sentence is the dock's
existing idiom — `exportControl` already replaced the button with one for a Recording that is still
capturing — and a control whose label cannot be read is not a control anyone was pointing at.

**Each blocked state gets its own short sentence**, ordered by what the user can do about it:

| state | sentence |
|---|---|
| the Trim holds nothing | `Nothing in the Trim to export.` |
| the effective Quality Preset can't encode this file | `This quality can't encode this file.` |
| an Export of this Recording is already running | `An Export is already running.` |

The second **deliberately duplicates** what ADR-0041 already states on the rung. The dock names the
situation and leaves the specifics to the rung, because the alternative — one sentence generic enough
to cover all three — would say nothing in the first state, which is the only one nothing else on
screen explains.

The still-capturing sentence **moves to ink in the same change**: it was `.secondary` at
**3.89 : 1 in Light**, the same figure #119 rejected for the rungs, in the same slot on the same
ground. Two sentences in one slot at two strengths would have been an authored inconsistency.

## Two things this does not move

**The dock keeps its declared height.** A pixel diff of before against after at `1200 × 680` is
confined to `940–1184 × 639–663`, the control's own box, so
[ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md)'s single height holds and
nothing above the dock shifts. The sentence must therefore always say *something*: an empty slot
would collapse it.

**The glyph keeps no colour of its own**, so
[ADR-0037](0037-a-warnings-colour-belongs-to-its-mark-not-its-sentence.md)'s mark test is not invoked
and the app still has three marks under 3 : 1, not four. `square.and.arrow.up` is drawn in the same
ink as the words; it costs ~28 pt of the 245 pt the column offers at the floor, and nothing truncates.

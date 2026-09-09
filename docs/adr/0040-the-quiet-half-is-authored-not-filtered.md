---
status: accepted
amends: "ADR-0019's *what changes outside the Trim is colour, not brightness*; ADR-0033's three-fill lane table"
---

# The Trimmed-away half is authored, not filtered

`TrimTimeline.waveform` drew the audio **twice**: `shape.grayscale(1)` under a masked colour copy.
So the lane has **six** fills, not the three [ADR-0033](0033-the-playhead-is-an-instrument-not-content.md)
tabulates, and [#108](https://github.com/SamWongML/macos-audio-recording/issues/108) found both
things that fall out of that. They are one mechanism, and this is one decision.

**In Light the playhead measured `2.82 : 1` over the Trimmed-away peaks** — under ADR-0033's own
3 : 1 floor, on 45 of 587 sampled rows, read per row as
[#105](https://github.com/SamWongML/macos-audio-recording/issues/105) requires. **And in Light the
Trimmed-away half read *louder* than the kept half**: its peaks measured 6.90 : 1 against the lane
ground where the kept peaks measure 6.12, its body 5.23 against 4.96. Dark had the same effect in
the opposite direction and it flattered the intent, receding ~13%.

## `grayscale(1)` never delivered "colour, not brightness"

[ADR-0019](0019-content-is-the-colour.md) chose the filter over `Rectangle().fill(.background.opacity(0.62))`
on the stated grounds that what changes outside the Trim is **colour, not brightness** — no
per-appearance magic number, survives Increase Contrast, leaves the Trim as the only indigo on the
lane. Two of those three are true. The first is not: `grayscale(1)` preserves luminance only
approximately, and the light `Signal` stops are brighter than their greyscale equivalents, so
removing colour **darkens**. Measured, it moved the Trimmed-away half ~13% in both appearances —
down in Dark, which recedes on a dark ground and reads correctly, and **up in Light**, which
advances on a light ground. The comment claimed a treatment the code had never applied.

That is [ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md) again, and the same
shape as ADR-0033's `Color.primary`: a mechanism that reads like a physical operation — *remove the
colour, keep the light* — is still a claim about the destination, and only the render is evidence.

## The decision

**The under-copy is authored.** `grayscale(1)` is deleted and the Trimmed-away audio is drawn as a
second `WaveformShape` in `Palette.signalQuiet` / `signalMutedQuiet`, two named stops in the asset
catalogue.

**Dark does not move, and that is deliberate.** Dark measured correctly everywhere, so its stops are
back-solved to reproduce exactly what the filter rendered: `(91,91,91)` peaks and `(70,70,70)` body,
pixel-identical before and after. Dark is the control this change is checked against.

**Light recedes by the proportions Dark already receded by.** Dark's Trimmed-away peaks sit 19%
below its kept peaks in luminance and its body 13% below. Applying the same two proportions in the
lightening direction is what sets Light's stops — so the floor is cleared **by the relationship,
not by a number chosen to clear it**, and for the first time both appearances say the same thing.

| Light, per row | before | after |
|---|---|---|
| playhead vs Trimmed-away peaks | **2.82 : 1** | **3.60 : 1** |
| playhead vs Trimmed-away body | 5.23 : 1 | 4.30 : 1 |
| Trimmed-away peaks vs kept peaks | 18% darker — advances | **20% lighter — recedes** |
| Trimmed-away body vs kept body | 7% darker — advances | 13% lighter — recedes |

Verified at `1200 × 680` and at the `960` floor, in both appearances, on the Release build, per row
over all six fills. Dark reads 8.02 / 6.18 / 4.45 at both sizes, unchanged.

**The floor covers all six fills.** ADR-0033 measured the three that playback crosses; the narrow
reading would make the floor a function of a gesture's clamp. The Trimmed-away region is reachable
two ways — `TrimTimeline.scrub` seeks without clamping, and the Trim start can be dragged past a
parked playhead — and only the first could be closed by clamping. A floor you can walk off by
dragging a handle is not a floor. **`scrub` is left unclamped**: looking at what is outside the Trim
before moving a handle is legitimate, and a click that visibly does nothing reads as broken.

**The per-appearance number ADR-0019 refused is still refused.** What it rejected was an alpha
overlay tuned by eye, needing a different value per appearance and dissolving under Increase
Contrast. These are named stops: declared, inspectable, and able to carry High Contrast variants.

**They carry none, and not by omission.** Increase Contrast moves `signal` *away* from the lane
ground in both appearances — light `#403FA0` darker, dark `#9694F0` lighter — so a fixed grey
recedes further in both directions, which is the relationship these stops exist to state. Adding
High Contrast greys would mean authoring numbers that **cannot be measured on this machine**
(ADR-0033's *what is not verified*, unchanged here).

## Also decided here

**Authored is not rendered, and only rendered counts.** The stops took two calibration passes: the
capture path drops every colour ~10 encoded levels, `Signal`'s `#5E5CE6` included, which renders
`(83,81,220)`. The first attempt authored the measured greys directly and rendered 10 levels dark in
both appearances. The values in `Palette` are therefore chosen so that the *render* lands on the
target — the same discipline as ADR-0032, one step earlier in the pipeline.

**The Trimmed-away region gets a name.** It was "trimmed-away" in code, "the desaturated half" in
the ticket, and "outside the Trim" in ADR-0019. `CONTEXT.md` now carries **Trimmed-away**, and
*desaturated* is on its avoid-list precisely because this decision stops it being true.

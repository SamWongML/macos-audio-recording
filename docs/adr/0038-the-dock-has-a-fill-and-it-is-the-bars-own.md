---
status: accepted
amends: "ADR-0036's account of what `safeAreaBar` draws — the modifier is right, both of its measured claims are not"
---

# The dock has a fill, and it is the bar's own

[ADR-0036](0036-the-docks-boundary-is-the-systems-and-it-is-conditional.md) moved the Export dock
from `safeAreaInset` to `safeAreaBar` to stop the trailing column's content drawing through it, and
said the dock *"still gets no fill … it gets the system's boundary, and it is conditional"*.

[#120](https://github.com/SamWongML/macos-audio-recording/issues/120) re-measured that dock against
the app it was aiming at, and **the modifier survived the comparison while the description did not.**
`safeAreaBar` is right and it fixed [#114](https://github.com/SamWongML/macos-audio-recording/issues/114).
It also paints a fill of its own — numerically the same band ADR-0036 measured, named *"the
`Material.bar` ADR-0025 deleted, arriving under a system name"*, and rejected — and the scroll edge
effect it credits for the fix contributes nothing you can see.

This was found by comparing the dock against **Apple Music's sidebar dock**, which is the reference
for this shape on macOS 26: an account row pinned to the bottom of a scrolling sidebar, with the
list passing beneath it.

## The transparency already matches Apple Music, and always did

Apple Music, Dark, sampled at 2× from the sidebar's bottom edge: the sidebar ground is **41** above
the boundary and **43** beneath it, separated by a one-pixel (0.5 pt) hairline at **56**. A playlist
row travelling under the dock keeps **14% of its contrast** — peak 72 over a 43 ground, against 255
over 41 where the same row is unoccluded — and loses 78% of its edge sharpness. It is dimmed and
blurred, not hidden: you can still read that a row is there.

The dock does the same thing, measured as an A/B on identical pixels at 960 × 460 in Dark, with the
`Normalize loudness` row travelling beneath it:

| | contrast of the row beneath | edge sharpness |
| --- | --- | --- |
| `safeAreaInset` | **187** (221 on 34) — full strength, drawn straight over the `Export…` button; this is #114 | 0.082 |
| `safeAreaBar` (shipping) | **24** (62 on 38) — **13.0% retained** | 0.031 — **37.7% retained** |
| Apple Music, same measure | **13.8% retained** | 22% retained |

**Nothing about the dock's transparency needs changing.** It is within a point of Apple Music's, and
the modifier ADR-0036 chose is what buys it.

## The fill is real, it is unconditional, and it is not the scroll edge effect

Measured at **960 × 900**, where the trailing column has ~200 pt of slack, draws no scroller, and
has nothing whatsoever beneath the dock:

| | Dark | Light |
| --- | --- | --- |
| `safeAreaInset` | 27, flat to the button | 242, flat to the button |
| `safeAreaBar` | 27 → 0.5 pt hairline at **43** → **35** to the window's bottom edge | 242 → 0.5 pt hairline at **218** → **250** |

**`27 → 35` in Dark and `242 → 250` in Light are ADR-0036's own figures for `.hard`.** That is the
band it measured, named as the `Material.bar` returning under a system name, and rejected. It is
what shipped, over 58.5 pt of the column's bottom edge, at a size where nothing is passing beneath.

The scroll edge effect is not what draws it. `.automatic`, `.soft`, an explicit `nil`, and
`.scrollEdgeEffectHidden(true, for: .bottom)` are **pixel-identical** to each other and to setting
nothing at all. `.hard` is the only style that changes anything, and only in how it composites
content *behind* the bar: where content passes beneath it erases it instead of dimming it, and where
nothing does it is the same band to within 4/255. So the choice ADR-0036 framed as *"conditional or
unconditional"* was never on the table — there is one bar background, it is unconditional, and the
style flag only decides what happens to whatever travels under it.

## Why `0/0/0` was measured, and why nobody could reproduce it

ADR-0036's `.automatic` measurement is not a mistake in arithmetic. It is reproducible — at exactly
one window size.

The fill is **absent at 1200 × 680** and present at 1200 × 660, 1200 × 700, 1199 × 680, 1201 × 680,
960 × 656, 960 × 680, 960 × 900, and 1000/1080/1160/1180/1240 × 680. 1200 × 680 is the size ADR-0036
measured at, and it is `.defaultSize`.

**The trigger is the window's first live resize.** Dragging that same 1200 × 680 window's corner
down 20 pt and back to exactly 1200 × 680 turns the fill on and leaves it on — same window, same
size, same content, opposite result. A window whose saved frame equals `.defaultSize` opens without
ever being resized, so it never shows the fill; a saved frame at any other size is a resize during
restore, and shows it.

**A treatment measured only at `.defaultSize` is measured at the one size the window can reach
without ever being resized.** Shoot one size either side of it. ADR-0036 already knew the shape of
this mistake — it is the same one it names in ADR-0025's bare dock, *"correct at every size anyone
shot"* — and made it again, one size over.

## The declared floor is a content height, not a window size

`.frame(minWidth: 960, minHeight: 604)` constrains the **scene's content**. The window's frame adds
the 52 pt title bar the code already names elsewhere, so the shortest window the app can produce is
**960 × 656**. Asked for 400, 500, 600, 620, 640, 650 and 655 the shipping window resolves to 656
every time; 660 holds.

The 52 pt ADR-0036 charges to *"height the scroll edge effect reserves"* is that title bar.
**`safeAreaBar` costs nothing:** with the same declared `minHeight` of 380, `safeAreaInset` and
`safeAreaBar` both clamp to 960 × 432. The same offset accounts for the 552 that ADR-0036 and the
`minHeight` comment read as *"the content's own minimum is higher and always wins"* — the declared
minimum then was 500, and 500 + 52 = 552.

**604 stays.** `.frame(minHeight:)` means content, content is the right thing to constrain, and the
number is honest about what it constrains. What has to stop is calling the result a window size:
**960 × 604 is not a window any machine can produce.** Every figure this repo labels *"at the 960
floor"* from ADR-0036 onward was sampled from a window of **960 × 656**, and ADR-0036's own
three-way split of that phrase (552 before, 604 after) needs its second number read as 656.

## Consequences

**ADR-0025's *"no fill and no rule"* is retired for the Export dock, and kept everywhere else.** The
dock has a fill and a hairline; they belong to `safeAreaBar`, they are not ours to switch off, and
they are what dims the content #114 was about. What ADR-0025 forbade was *"a darkening bar over a
column that already reads as separate"* — chrome bought for nothing. This band is bought for
something, and Apple Music's dock draws its own. The transport in the detail pane still has neither
(ADR-0023), and nothing here licenses a second one.

**No code changes.** The shipped treatment is the one this ADR is describing; only the comments
around it were wrong. `.soft` is deliberately still not written in the file — it is byte-for-byte
what the dock already draws, and writing it would claim a choice that does not exist.

**The 8 pt overlay scroller at the floor stays**, unchanged from ADR-0036, and it is now the only
part of that ADR's Consequences that survives unedited.

Every figure here is sampled from `screencapture -x -o -l` of Release builds in both appearances
(ADR-0032), with `safeAreaInset` and `safeAreaBar` built from the same tree and switched by an
environment variable so the two are the same pixels apart from the modifier. Apple Music's figures
are sampled from 2× screenshots of the running app.

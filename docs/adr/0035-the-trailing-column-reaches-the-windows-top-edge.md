---
status: accepted
amends: "ADR-0032's account of the column's separation — the mechanism stands, the extent was never stated"
---

# The trailing column's fill reaches the window's top edge

[ADR-0034](0034-an-empty-state-is-spoken-once.md) emptied the trailing column: it holds the Export
ladder or nothing, and never explains itself. It also predicted the consequence and declined to fix
it — *"the empty column is now bare, and Dark is where that shows"* — filing the treatment question
separately as [#111](https://github.com/SamWongML/macos-audio-recording/issues/111).

Measured at `1200 × 680`, Dark's column is **36% darker** than its detail where Light's is 5% — about
seven times the step — and with nothing drawn on it the Dark column read as a hole rather than a
pane. The obvious reading was that the scrim was wrong in Dark.

## The decision

**The column's fill runs to the window's top edge, and its colour does not change.**

Nothing about [ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md) moves: the
scrim is still flat black at 0.05, still deliberately not appearance-adaptive, still a system colour
with a measured correction. `.ignoresSafeArea(edges: .top)` on the background alone — the ladder
keeps its inset from the title bar; only the paint goes under it.

## Why the colour is not the defect

Six treatments were built into the running app behind a picker and photographed from fresh launches
in both appearances, empty column and populated
([`prototype/empty-column-dark`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/empty-column-dark)).
Three things the render said that the palette could not:

**The fill began at y = 52 pt.** Below the title bar, with a square top corner against a rounded
window — in every filled variant, in both appearances. That is a rectangle stuck to the right-hand
side, not a column. Research report 0006's primary sources say Apple does the opposite: Xcode's
inspector seam *"starts at the literal top of the window"*, and WWDC20's *Adopt the new look of
macOS* calls a split view's dividers reaching the top of the window the point of
`fullSizeContentView`. Issue #7 hid this window's toolbar background for exactly that reason, and
then the column stopped 52 pt short of the edge it was hiding it for. **With content in the column
the eye reads the content; empty, it reads the rectangle** — which is why ADR-0034 is what exposed
this and why nothing before it did.

**Deleting the black scrim in Dark would have moved almost nothing.** `.controlBackgroundColor` is
`(30,30,30)` in Dark against a detail that draws `(40,40,40)`: **ten of the step's thirteen units
are the system's own** and only three are the scrim. A column with no scrim at all lands at 30 —
still 25% darker, still a hole. #111's own first bullet, *"a smaller black alpha in Dark, or none"*,
was never a live option, and knowing that took a measurement rather than an argument.

**Closing the gap in colour would have meant overturning ADR-0032.** The only way to bring Dark's
column near its detail is to lift it *toward* the detail — a **white** scrim, `0.045` over
`(30,30,30)`, measured at `(38,38,38)` and a 5% step matching Light's. It works, and it is precisely
what ADR-0032 ruled out when it said the column wants to be darker in both appearances. Buying a
5% step at the price of a superseding ADR is a bad trade when the pane reads correctly at 32%.

## Considered and rejected

| | treatment | measured | why not |
|---|---|---|---|
| B | appearance-aware scrim | Dark `(38,38,38)`, 1.026 : 1 | overturns ADR-0032 to fix something the top edge fixes for free |
| C | no fill step, a 1 pt hairline | 1.000 : 1 both | #78 removed this hairline for the asymmetry the top edge is now fixing; report 0006 found neither Xcode nor Finder draws one |
| D | `.regularMaterial` | Dark **+7.5%**, Light **−8.2%** | changes sign between appearances, and in Light is a *bigger* step than today's — ADR-0032's own rule, again |
| E | the empty column dissolves | 1.000 : 1 empty, 1.168 : 1 populated | a second state to maintain, and the pane blinking into existence on the first click is motion nobody asked for (ADR-0028) |

## Consequences

**The colour stays open, and that is deliberate.** Dark's column is still 32% darker than its
detail. The claim here is not that 32% is the right number; it is that the *shape* was the defect
and the number was not, and that a treatment gets changed when a render says it is wrong rather than
when a ratio looks large. If a later sweep photographs this column and still calls it a hole, the
measurements in #111 are the starting point and B is the variant to reach for.

**The empty column is rarer than the ticket implied.** `EditorModel.reconcileSelection` selects the
newest Recording on first open, so an empty column is only reached on an empty Library, on a
can't-open file, or after the user deselects. The state that matters is the first run — the one
screenshot where premium is decided, as ADR-0034 put it.

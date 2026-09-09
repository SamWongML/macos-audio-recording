---
status: accepted
---

# The trailing column sets the editor's default height

The editor opens at **1200 × 680**, centred, and comes back wherever it was left. The height is not
derived from the waveform, which is the pane the window exists to show: it is derived from the
**Export column**, the narrow pane on the other side. The lane stops wanting height long before the
column does, so the column is what the number has to clear.

Restoration is **AppKit's, not ours** — there is no code behind it and there should not be.

## The two panes disagree about the height

Measured against the running Release build with the real 39-Recording Library (issue #97):

| | |
|---|---|
| the lane reaches its 340 pt cap | **620** |
| the trailing column stops drawing a scroller | **645** |
| …and with the longest Correction caption | **670** |
| the window's real height floor | **552** — the content's, not the declared 500 *(**552 until [#114](https://github.com/SamWongML/macos-audio-recording/issues/114); 656 after it. 604 is what the code declares, and it is a content height — ADR-0038.**)* |
| the window's real width floor | **960** — the declared one |

Above 620 the lane has all the height [ADR-0023](0023-the-detail-pane-is-ruler-lane-brief-dock.md)
allows it, and every further point becomes air below the brief. That ADR asks for the air: the pane
is *lane, brief, air, transport*, and the cap exists precisely so a tall window cannot smear one
silhouette across four hundred points.

The column asks for the opposite. Below 645 its two cards do not fit, and macOS draws an overlay
scroller down the full height of the stack — the blemish
[issue #76](https://github.com/SamWongML/macos-audio-recording/issues/76) pinned the Export control
to the bottom edge to remove. Nothing is clipped; the overflow at 640 is five points. It is the
scroller that is wrong, not the content.

So there is no height that satisfies both panes, and **the tie goes to the column**: air is a
sanctioned outcome of ADR-0023, and a scroller is a defect an earlier ticket already went to some
trouble to get rid of.

*(Amended by [ADR-0036](0036-the-docks-boundary-is-the-systems-and-it-is-conditional.md) in two
places. The **645 / 670** figures were re-read as an argument for raising `minHeight` above them, so
that the column could never scroll and the Export dock could stay bare by construction; that was
rejected, and the column is now allowed to scroll with the boundary treated.

And **the height floor in this table is no longer the current one.** It was 552 — the content's
minimum against a declared 500 — right up until #114 swapped the Export dock from `safeAreaInset`
to `safeAreaBar`, which reserves height for the scroll edge effect it carries and grew the column's
minimum by **52 pt**. The floor is now **604**, and the code declares it rather than declaring a
number nothing can reach. So **every figure on this page, and every "at the 960 floor" measurement
in any ticket up to and including #113, means 960 × 552**; anything from #114 onward means 960 × 604.
*(Corrected by [ADR-0038](0038-the-dock-has-a-fill-and-it-is-the-bars-own.md): **read that second
number as 960 × 656.** `safeAreaBar` costs 0 pt of minimum — the 52 pt is the title bar, which 552
already contained, added a second time. 604 is the declared *content* height; the window it produces
is 656.)*
The scroller this ADR calls "wrong" is, at that floor, accepted: it appears only when the content
genuinely does not fit, and it was measured stopping ~27 pt clear of the dock rather than
overlapping it by 8.)*

## The size that shipped was wrong twice

`1120 × 640` was in the tree with the comment *"three columns want room"*, which is a reason for the
width and no reason at all for the height. Measured, it lands in the one narrow band that gets both
halves wrong: **20 pt past the lane's cap**, so the height buys the waveform nothing, and **5 pt
short of the column**, so it scrolls. Arrowed through the whole Library at that height, **39 of 39
Recordings** draw the scroller. Twenty points either way would have been better than the number
that was there.

## The column's height is a property of its strings

The 645 is not a constant of the layout. The Correction row carries one of three captions or none,
and swapping the app's own longest — `amplificationCapped`'s *"limited to keep the noise floor
down"* — in for `ceilingReached`'s *"peak ceiling reached"* moves the requirement to **670**: the
caption stops fitting beside the label, so `LabeledContent` stacks the row and it goes two-line and
full-width. That caption is not hypothetical; it is what a genuinely quiet Recording prints.

**680 absorbs that**, and absorbing it was chosen over designing it out. The alternative — the
column reserving its own tallest state, the move
[ADR-0027](0027-the-transport-reserves-its-widest-readout.md) made for the transport's readouts and
[ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md) for the sidebar's glyph rail
— is the more consistent answer and was rejected as more machinery than a rarely-seen caption is
worth. The cost is disclosed rather than hidden: **the margin is air the user sees always, spent
against a scroller they will see rarely**, and a translation longer than the English will move the
number with nothing to notice that it has.

**The requirement also grows after the window has opened.** A Recording whose BS.1770 pass has not
landed reads `Measuring…` with no caption; the figure and its caption arrive seconds later and the
column gets taller. Sweeping the Library at 645 immediately after launch reported 25 of 39
Recordings scrolling and a second sweep at the same height reported 39 — the same app, the same
number, a different moment. Any height chosen from a screenshot taken too early is chosen short.

## The width is the one number that is pure gain

`TrimTimeline` builds its envelope with `columns: Int(width)` — **one column per point of lane**. So
width is not stretch, it is resolution: 1200 gives the lane 656 columns against 1120's 576, and the
waveform is that much less averaged. The only ceiling is the screen, and the smallest Mac AppTape
runs on is a 1440 × 900 MacBook Air, which leaves 240 × 125 around a 1200 × 680 window with the Dock
showing. 1280 × 720 was looked at and rejected for sitting nearly edge to edge there.

## Considered options

**1200 × 680 (chosen).** Clears the column at its tallest, widens the lane by 14%, fits the smallest
supported screen with room around it.

**1120 × 660.** The minimal change — clears today's strings and keeps 20 pt less air. Rejected
because it does not clear the long caption, so the rare quiet Recording still scrolls in the default
window, which is the defect this ADR exists to close.

**1280 × 720.** Rejected on the 13-inch Air, where it is close to edge to edge, and on the air: 100
pt below the brief is a visible band.

**Keep 1120 × 640.** Rejected: it is the size that is wrong on both counts.

## Consequences

**Restoration is AppKit's and stays unwritten.** A SwiftUI `Window` autosaves its frame under
`NSWindow Frame <scene id>` — here `NSWindow Frame editor` — and the sidebar's split position under
`NSSplitView Subview Frames editor, SidebarNavigationSplitView`. Both are written the instant the
window shows and again on every move and resize, so they survive a `pkill`, not merely a graceful
quit: verified by moving the window to 1400 × 820 at (120, 60), killing the process, relaunching and
reopening to exactly that frame. Neither `LSUIElement`, nor `.defaultLaunchBehavior(.suppressed)`,
nor the `.accessory` ⇄ `.regular` flip of
[ADR-0017](0017-accessory-at-rest-regular-while-editing.md) interferes — this is per-window frame
autosave, not `NSApplication` state restoration, and the editor is opened by the user either way.

**`.defaultSize` is therefore the *first-run* size only**, and after the first open it is dead for
that user. That is the point: the number is the first impression, and it is judged on a Library the
user does not have yet.

**Nothing stored means centred.** Measured at (400, 198) on a 1920 × 1050 screen — horizontally
centred to the point, and biased above centre, which is AppKit's `center()`. No cascade, because
there is only ever one editor window (it is a `Window`, not a `WindowGroup`). Left alone.

**The declared height floor does not bind and is kept anyway.** Asked for 500 the window resolves to
**552**, the content's own minimum. The note in `AppTapeApp` had recorded 552 as a stale figure from
a Recording with a four-row brief and assumed the always-five-row brief of ADR-0023 had moved it; it
had not. 500 stays as the backstop it was, now labelled as a number you cannot reach. The width
floor is the opposite: asked for 900 the window resolves to 960, so ADR-0027's number is the one in
force.

**A future tidy-up will want to pull the height back to 620.** The lane's cap is the visible reason
for a height and the column's scroller is not, so the obvious "clean up the air" change reintroduces
the defect. That is what this ADR is for.

Settled in [issue #97](https://github.com/SamWongML/macos-audio-recording/issues/97); the
measurement harness is on `prototype/editor-default-size`.

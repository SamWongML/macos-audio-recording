---
status: accepted
---

# The Library row is one line, and the inspector states the Export

Issue [#78](https://github.com/SamWongML/macos-audio-recording/issues/78) asked what the Library
sidebar and the Export inspector look like under [ADR-0019](0019-content-is-the-colour.md), once the
detail pane had proven the design language. Three structurally different answers were built and
switched in the running app — two-line rows with a flush inspector, one-line rows with a rung list,
and name-only browse rows with an Export ladder — and judged against the real Library rather than a
mockup. **The one-line/rungs answer was chosen.**

Both halves are one idea: **the crowding was too much said, not too little arranged.**

## The row: one 32 pt line, and the timestamp is gone

The trailing lane crowded because it carried a timestamp, a scissors, a Seam glyph and a duration
in whatever width the name left over. The fix is subtraction.

**The timestamp is removed, not rearranged.** The day is in the section header directly above the
row, and the exact minute is in the brief two panes to the right, on the Recording the row selects.
A row that repeats both spends its width restating what the window already says twice.

**The trailing rail is fixed-width, and the glyphs are drawn at zero opacity rather than omitted.**
An `if` around a glyph moved the duration by the width of that glyph on every row that differed, so
the durations never lined up down the column — the ragged edge that read as crowding. A fixed 26 pt
glyph slot and a 42 pt duration slot make the column a column. The invisible glyphs are hidden from
accessibility, so nothing is read that is not shown.

**ADR-0019's 40 pt `sidebarRowHeight` is superseded by 32.** Forty points buys a second line, and
the second line's only content was the timestamp this ADR just deleted. A taller row for a fact
stated twice elsewhere is emptier, not calmer, and it costs four visible Recordings at the default
window height. `Metrics.sidebarRowHeight` is now 32 and `LibraryRow` reads it, so the token set and
the code stop disagreeing. `Metrics.name` is adopted at the same time — with the timestamp gone the
name carries the row alone, and semibold is what makes it the thing scanned.

**The silhouette survives selection**, superseding
[ADR-0023](0023-the-detail-pane-is-ruler-lane-brief-dock.md)'s *"a selected sidebar row drops its
waveform silhouette"*. Dropping it left the row the user is looking at as the one blank row in the
column, with a lone scissors floating in the space the shape used to fill. The fill was never the
problem — the **colour** was: `.secondary` at 50% is a mid grey, which is mud on the focused accent
fill and barely separated from the unfocused grey one. Selected, the shape takes `.primary` at a
lower alpha, which macOS inverts for both fills, so one rule covers both. The alpha is what keeps it
a ground rather than a competitor to the name in front of it.

**A row is drawn against two fills, and every colour it names must survive both.** macOS fills a
selected row with the accent at full saturation while the sidebar has focus and with a mid grey when
it does not, and it inverts `.primary` and `.secondary` for you on each — but it does nothing for
content that names its own colour. That is why the `Signal` scissors yields to `.primary` when
selected (ADR-0023, unchanged): indigo is indigo-on-blue on the focused fill and barely separated
from the unfocused one. ADR-0019's where-`Signal`-may-appear list is unchanged in substance.

## The inspector: it states what Export will produce

**The `Selection` section is deleted.** It stated the Trim's length and range forty points from a
transport that already states them, in a different colour — the window disagreeing with itself, and
the last of the two-colour Trim readouts that
[#77](https://github.com/SamWongML/macos-audio-recording/issues/77) started closing. What is
currently selected is the detail pane's job. What the inspector says is what Export will **produce**.
The trimmed duration has not gone quiet: it is the input to every size estimate, and each rung
prints its own.

**Quality is four rungs on screen, not a `Picker`.** All four presets and all four size estimates
are visible at once, so the choice is compared rather than revealed one at a time by a menu. This is
also the only shape in which ADR-0019's *"the selected Quality Preset rung gains a leading
checkmark, always"* means anything — inside a `Picker` the checkmark lives in a menu nobody sees.
A rung the source's format cannot encode faithfully states its own plain reason where its codec
would be, so every unusable rung says why, not just the effective one (ADR-0015).

**The source's rate and channel count are said once, beneath the rungs.** They come from the
*source*, so they are identical on all four rungs; printing them per rung was four copies of one
fact, and it wrapped every rung onto two lines in a 276 pt pane. Issue #9's "codec, bitrate, rate and
channels, visible and never editable" still holds — it is simply said once rather than four times.

**All four Export phases share one height.** *(Unchanged by ADR-0036 and re-verified at the 960 ×
656 floor in all four phases: the bar's fill draws inside the declared 34 pt, it does not resize the
dock — ADR-0038 for the fill's provenance and the floor's arithmetic.)* Idle, running, succeeded and failed each laid out to
their own intrinsic height, so the dock moved twice during a two-second job. They now share a single
declared height sized to the tallest phase, which is a two-line failure; `Try Again…` steps down
from prominent to plain, because a failure the user has just read is not the moment for the loudest
control in the pane. Issue #76 settled where the Export control sits; this settles that it stops
moving.

**The trailing column separates by material, not a hairline.** *(Amended by
[ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md): `controlBackgroundColor` and
`windowBackgroundColor` are the same value in both appearances, so in Light this step measured zero.
The mechanism stands; the step is now manufactured with a measured scrim.)* The `Divider()` started below the
title bar and ran to the window's bottom edge, and that asymmetry is what read as wrong. Research
report 0006 (`research/trailing-pane-separator`) found the hairline is not the norm: Xcode's
inspector boundary is a material shift reaching the literal top edge, and Finder's preview column
draws no boundary at all. The column takes `.controlBackgroundColor`, one step off the window's own
background, and where a line should start and stop stops being a question. The `Form` gives up its
own background so it does not paint over that, and the Export dock gives up its `.bar` for the same
reason — a darkening bar over a column that already reads as separate is the decorative chrome
ADR-0019 spends its budget avoiding. *(Amended by
[ADR-0036](0036-the-docks-boundary-is-the-systems-and-it-is-conditional.md) and corrected by
[ADR-0038](0038-the-dock-has-a-fill-and-it-is-the-bars-own.md): the dock is pinned with
`safeAreaBar` rather than `safeAreaInset`, which is what stops the column drawing through it — and
**that modifier brings a fill of its own**, 27 → 35 in Dark and 242 → 250 in Light with a 0.5 pt
hairline, unconditionally and at every size, not only where content passes beneath. **"No fill and
no rule" no longer holds for this control.** It is retired here rather than defended, because that
band is exactly what dims the content, and Apple Music's sidebar dock draws its own. The `.bar` this
paragraph deleted is still deleted: what remains is the system's, not ours, and there is no way to
switch it off. Everywhere else in the editor — the transport above all — "no fill and no rule"
stands.)*

## Consequences

`Metrics.sectionHeader` is **retired to a stop nothing reads**. The inspector stayed a grouped
`Form`, whose `Section` headers macOS styles itself and restyles between releases; overriding them
would freeze this app's headers at one OS version's idea of them for no gain the ticket could see on
screen. It is left declared, and deliberately unused, for the first surface that needs a header
outside a `Form`. That closes the last of the three declared-but-unapplied tokens the set was
carrying for #78.

The prototype that produced this — three variants and an in-app switcher, ~830 lines — is
**not merged**, as no `prototype/*` branch in this repo is. It stays on
`prototype/sidebar-and-inspector` as the evidence for the choice.

**Not settled here.** The editor's open animation, where the trailing column travels in from the
top-left of the detail pane, is a separate defect and is untouched by this ADR. So is what moves
keyboard focus in and out of the sidebar — observed to change the selection fill between the accent
and the grey, but not diagnosed, and deliberately not claimed.

---
status: accepted
supersedes: "issue #7's *no ruler in the editor*"
---

# The detail pane is ruler, lane, brief, dock

The editor's detail pane read as a scaffold, and the reason was structural rather than decorative:
`editorDetail` was a `VStack` holding a `TrimTimeline` whose `GeometryReader` is greedy, so the
waveform lane stretched to whatever height the window had — four hundred points of one silhouette —
above a single transport row, with `showsRuler: false` and nothing else on screen. A map that could
only add ornament could not fix that; this ADR settles the layout.

**Top to bottom: a ruled lane, the Seam line, the brief, air, and the transport docked to the
window's bottom edge.**

## Considered options

**Doing nothing but un-stretching the lane was rejected, but only just, and it is worth saying why.**
Three layouts were built into the real app and judged against the live waveform, not as mockups
(issue #77). The first — a fixed lane, the ruler on, the transport under it and the rest deliberately
air — tested the reading that the pane looked empty because the lane was *stretched*, not because
anything was missing. It is a real improvement over the greedy lane and it is the option this
project's own premium research argues for, since restraint is the premium signal and the apps
closest to AppTape's job got *more* generous in their redesigns. It lost because at the default
window size it still left the bottom third of the pane blank, and because the thing that would fill
it turned out to exist already.

**A window toolbar was rejected, so issue #7's *exactly one pane control* and its hidden toolbar
background both stand.** The third layout had one, and running it settled the question in a way no
argument would have: the toolbar's play button and the docked transport's play button appeared in
the same window at the same time, twenty points apart. Everything else a toolbar could hold —
Rename, Reveal in Finder, Move to Trash — is already in the File menu and the sidebar's context menu
by ADR-0020, and Reset Trim is in the dock. A toolbar here would be chrome with nothing to carry.

**A ruler was adopted, and this is the one decision that overturns issue #7.** It shipped
`showsRuler: false` — the component has always had one, switched off. A ruler is the peer norm
rather than decoration: Fission, Sound Studio, Descript and Logic all document one, and QuickTime,
the deliberately bare floor, is the only researched app confirmed to omit it. It is also what makes
the lane read as a timeline rather than a picture. It goes **above** the lane, where every peer that
has one puts it, with ticks at a round interval — 1/2/5/10/15/30/60 s and up, chosen so no two
labels come within 64 pt — because the Recording always fits the width and there is no zoom, so the
interval is a function of duration and width alone.

**Turning the ruler on forced a second decision that had been invisible until then: the Trim was
being stated three times.** The ruler said `Trim 0:00 – 0:07`, the transport row said it again forty
points below, and the inspector said it a third time. **The ruler keeps it and the transport row's
copy is gone.** The ruler wins the two in this pane because it spans the lane and sits directly
under the handles that set it; Reset stays in the transport, with the control that undoes the Trim,
since only the readout moved. The inspector's row is its own — that one is the Export contract, and
it is issue #78's to reconcile.

**The Trim's span bar on the ruler is `.secondary`, not `Signal`.** ADR-0019 lists exhaustively
where the accent may appear and a ruler is not on that list. The Trim's colour lives in the lane, on
the audio.

**A static Loudness readout was rejected, and not on taste.** It was the obvious filler for the
freed space — the audio-editor research proposed exactly it, as *this Recording measures X LUFS,
will be corrected to Y at Export*, and it ties an existing domain concept to the empty space without
a live VU that would be meaningless on already-captured audio. ADR-0013 forbids it in as many
words: the figure shown is always dB, and the measured LUFS is never shown to the user. The
correction in dB is already an inspector row. Anyone who wants this must supersede ADR-0013 first.

**So the freed space became the brief: the master's provenance and shape.** Source, when it was
captured, its format, and its footprint on disk — the app's own data, which is what the premium
research means by *added colour should be data, not ornament*. It deliberately states nothing the
Export inspector states: Length, Trim, Quality, the Loudness correction, Gain and the estimated size
are all the inspector's, and a window that says the same fact in two panes is a window disagreeing
with itself. Provenance had no home anywhere before this.

**Typable Trim points were rejected.** The third layout carried `In`/`Out` as editable fields.
Timecode is overwhelmingly display-only across the researched peers; QuickTime's Go To Timecode is
the single typable precedent and it is a menu command, not an inline field in a transport row. For a
Recording that always fits the width, with a loupe for accuracy and no zoom to navigate out of, a
text field buys very little.

**Overview strips, a dense edit toolbar and a transcript layer stay rejected** for the reasons the
audio-editor research already gave: an overview strip is a zoom-navigation aid and there is no zoom;
Fission's Crop/Split/Fade/Normalize row exists because those apps have many destructive operations
where Trim is AppTape's only edit; a transcript presupposes a pipeline this app does not have and
conflicts with a two-handle non-destructive Trim.

## Consequences

**The lane takes the leftover height, capped.** ADR-0019 made the lane the one element allowed to
take all remaining height; this adds a ceiling — a 168 pt floor and a 340 pt cap — because uncapped
is precisely the smear this ADR exists to fix. Extra window height becomes air below the brief.

**The transport is docked to the window's bottom edge** rather than sitting under the lane, so its
position no longer depends on how much the pane above it happens to hold — the same reasoning that
pinned the inspector's Export control in issue #76 — and the playhead clock lands where a clock
belongs, as the largest type in the window.

**The docked bar is a plain last child behind a `Spacer()`, and must not become a
`.safeAreaInset(edge: .bottom)`.** That is the idiomatic way to dock a bar, it is how this was
written first, and it **aborts the app on open**: a bottom safe-area inset on the content hosting
the permanently-presented `.inspector` re-enters the layout pass until AppKit throws. Same loop as
issue #85, reached by structure rather than by window width.

**The editor window's minimum height is now a layout number, where 960 wide is still a guard.** The
pane's content stops fitting between 460 and 480 pt of window height, and an over-constrained
`NavigationSplitView` plus permanent `.inspector` does not clip, it aborts. Measured on this
layout: 960 × 460 aborts, 960 × 480 does not; the shorter pane this replaces was fine at 420. The
floor is 500 as a backstop, though the content's own minimum usually resolves higher — a Recording
with a Seam line and four brief rows clamps the window at 552.

**Issue #85 is untouched and stays open.** Probed on this layout with the width floor temporarily
lowered: the editor still aborts at 800 pt wide. The loop lives in the trailing pane, not in the
detail pane, so it belongs to whatever settles the inspector's structure (issue #78), and the 960
width floor stays a guard until then. Two new facts for it, both measured on unmodified `main` at
1120 × 640, both structural rather than width-triggered: opening the editor window *during* launch
— `.defaultLaunchBehavior(.presented)` instead of `.suppressed` — aborts every time, and so does the
bottom safe-area inset above.

**The empty state stays a `ContentUnavailableView` and gains a second line.** The premium research
found no comparison app with a documented bespoke empty state and Apple's own guidance is the only
grounding available: say what to do next. It gets no button — the action is *pick a row*, and a
control that merely moved focus to the sidebar would be invented to fill a hole. The can't-open
state was already correct and is unchanged.

**The waveform's own treatment is unchanged.** ADR-0019 settled the colours and issue #81 measured
them; this ADR moves nothing on the lane except the ruler above it.

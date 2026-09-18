---
status: accepted
---

# 0026. Prism Pulse is the app icon

The user approved **Prism Pulse** after reviewing concepts and a native Icon Composer 27
refinement. Five overlapping glass capsules form a centered waveform, in lavender, blue,
indigo, violet, and azure. The default appearance uses a pearl `#F0F0F8` tile; the dark
appearance uses a charcoal `#161620` tile. The production `AppTape.icon` contains the approved
native source, including its separate appearance settings, rather than flattened preview PNGs.

This supersedes the original seven separate `Signal` bars and their two background colors.
The five-pane mark is an explicitly approved change from the initial five-bar rejection below:
overlapping glass panes now provide the visual identity. The editor's content palette remains
governed by [ADR-0019](0019-content-colour-palette.md).

The icon appears when the editor opens and the app flips to `.regular`, as described in
[ADR-0017](0017-activation-policy.md). The editable source and render settings live in
[`AppTape.icon`](../../AppTape/AppTape/AppTape.icon). Prototype artwork, reference images,
research notes, and review exports were removed after approval to keep the repository small.

## Initial icon studies

These findings document the original seven-bar decision, before the approved Prism Pulse study.

**AppTape's own waveform drawing was rejected, and this is the first surprise.** The faithful
thing is `WaveformShape`'s envelope: a filled polygon through 30 column midpoints, which is
what the editor's lane actually draws. Rendered at icon sizes it **collapses into a blob below
about 64 pt** — right for a 700 pt lane, unreadable in a 16 pt Dock tile, and a single quiet
column pinches the row waveform into two lobes that read as nothing at all. Discrete bars are the
same idea at icon scale, and they are also what the status item's `waveform` symbol already is,
so the Dock and the menu bar now rhyme.

**The tape was rejected on evidence, after four drawings.** The app is called AppTape and a
tape mark is the obvious move, so it got two full attempts in each direction. A ring with three
spokes rendered as a **steering wheel**; redrawn as a platter with three cutouts it renders as a
**film reel**, which says video. A capsule with two reel holes rendered as a **toggle switch**;
redrawn as a shell with a tape window it renders as a **bowtie on a card**. Nothing in four
tries said audio. This also agrees with [ADR-0019](0019-content-colour-palette.md), which rejected
full surface treatment as "the road to a dated skeuomorph": a cassette is a picture of hardware,
and the hardware is forty years old.

**The Trim was rejected twice, which is the finding worth keeping.** Trim is AppTape's only edit
and the one thing its icon could say that no other audio app says, so it was tried as two rails
bracketing the bars — and at Dock size the **rails read as two more bars**. It was then tried
again with colour instead of geometry, using ADR-0019's own two stops (`Signal` kept,
`Signal Muted` trimmed away), and the difference is faint at 320 pt and **gone by 64 pt**. The
two stops are deliberately close enough not to fight across a 700 pt lane, and that is exactly
what makes them useless in a tile. **The icon cannot carry the Trim. Do not try a third time.**

**A saturated indigo ground was rejected on the Dock, not on the page.** White bars on indigo is
the conventional premium shape and it renders perfectly well. Put next to real neighbours it
loses: it sits in a run of blue and indigo tiles, while the pale tile is the only light one in
that stretch of the Dock and is picked out instantly. This is also ADR-0019 read literally — a
sober ground, and the audio is the only colour.

**Five separate bars were initially rejected.** It is marginally crisper in the 16 pt tile and reads as an EQ or a
bar chart at 128 pt. Seven keeps the waveform texture and still resolves at 16.

**The system's derived dark variant was rejected, measured.** Left alone, the system keeps the
SVG's own `#5856D6` over a near-black grey gradient — about **2:1**, where the bars barely read.

## Consequences

**`AppIcon.appiconset` is deleted and `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppTape`.** An
Icon Composer file replaces the icon asset catalogue rather than sitting alongside it; Xcode
generates the older representations from it. The set it replaces was empty, so nothing was lost.

**Light and dark are explicitly authored.** Each pane uses Multiply in the default appearance
to reveal colored intersections and Screen in dark to keep those intersections luminous. The
five source SVGs share a 1024-point canvas and contain only geometry and color. The system
provides the mask, specular edges, refraction, and shadows. Refraction is 24% strength with
16% height, translucency is 32%, and neutral shadow is 22%.

**The icon palette belongs to the app's external identity.** Its indigo-centered colors are
defined inside the `.icon` bundle and are independent of `Signal` and the global accent.
`AccentColor.colorset` stays empty, and the editor's existing content-color rules are unchanged.

**Light Mode Finder is the known soft case.** Against a white icon-view background the tile's
edge nearly vanishes and the mark reads as bars floating on the page. It was accepted, not
overlooked: in Dark Mode, and in the Dock in either mode, the same tile is the strongest thing
in the row.

**`ictool` drops unknown `icon.json` keys silently**, so a clean compile proves nothing about
whether a setting took. Four wrong shapes for `fill-specializations` compiled with zero errors
and zero effect. Anything added to this file must be verified with `assetutil --info` on the
compiled catalogue, never by exit code. The shape that works: `fill-specializations` **replaces**
`fill`, the entry with no `appearance` key is the default, there is no `slot` wrapper, and the
appearance is `dark`.

The Prism Pulse integration passed a macOS Debug build. `assetutil --info` confirmed the five
lit vector layers, Multiply/Screen appearance overrides, distinct background gradients, and
the authored refraction, translucency, and shadow values in the compiled `Assets.car`.

**Clear and tinted appearances have a dedicated Mono treatment.** Every pane uses System Light
fill, Normal blending, and 82% opacity in Mono. All six appearances were exported directly from
Icon Composer 27 at 16, 32, 128, 256, 512, and 1024 points; the small-size previews and native
indigo tint intensity extremes were inspected. Static exports are review references; the native
source remains the app's adaptive icon. The source targets macOS only.

---
status: accepted
---

# The icon is the waveform on a pale ground

AppTape shipped with the **generic application icon**, which [ADR-0017](0017-accessory-at-rest-regular-while-editing.md)
puts on screen the moment the editor opens and the app flips to `.regular`. The mark is
**seven mirrored bars in `Signal` indigo on a pale `#E6E6F2` tile**, drawn as vectors in an
Icon Composer `AppTape.icon` bundle. The interesting part of this decision is not what was
chosen — it is that three obvious candidates were each tried, rendered, and killed by the
render rather than by argument.

## Considered options

**AppTape's own waveform drawing was rejected, and this is the first surprise.** The faithful
thing is `WaveformShape`'s envelope: a filled polygon through 30 column midpoints, which is
what the editor's lane actually draws. Rendered at icon sizes it **collapses into a blob below
about 64 pt** — right for a 700 pt lane, unreadable in a 16 pt Dock tile, and a single quiet
column pinches the silhouette into two lobes that read as nothing at all. Discrete bars are the
same idea at icon scale, and they are also what the status item's `waveform` symbol already is,
so the Dock and the menu bar now rhyme.

**The tape was rejected on evidence, after four drawings.** The app is called AppTape and a
tape mark is the obvious move, so it got two full attempts in each direction. A ring with three
spokes rendered as a **steering wheel**; redrawn as a platter with three cutouts it renders as a
**film reel**, which says video. A capsule with two reel holes rendered as a **toggle switch**;
redrawn as a shell with a tape window it renders as a **bowtie on a card**. Nothing in four
tries said audio. This also agrees with [ADR-0019](0019-content-is-the-colour.md), which rejected
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

**Five bars was rejected.** It is marginally crisper in the 16 pt tile and reads as an EQ or a
bar chart at 128 pt. Seven keeps the waveform texture and still resolves at 16.

**The system's derived dark variant was rejected, measured.** Left alone, the system keeps the
SVG's own `#5856D6` over a near-black grey gradient — about **2:1**, where the bars barely read.

## Consequences

**`AppIcon.appiconset` is deleted and `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppTape`.** An
Icon Composer file replaces the icon asset catalogue rather than sitting alongside it; Xcode
generates the older representations from it. The set it replaces was empty, so nothing was lost.

**The dark appearance is declared, not derived**: ground `#1A1929`, mark `#9694F0`. That mark is
**`Signal`'s High Contrast dark stop, reused rather than invented** — a small indigo mark on a
near-black tile needs precisely the lift Increase Contrast needs. `Signal` dark `#5E5CE6`
measures 3.41:1 there; `#9694F0` measures 6.43:1.

**The icon is a new `Signal` site, and ADR-0019's list of sites is no longer exhaustive as
written.** That list governs *views*, where the rule is "is this pixel captured audio?"; the icon
is the app's identity seen from outside the app, and it is the waveform, so it takes `Signal` for
the same reason the lane does. `Palette`'s doc comment names it. `AccentColor.colorset` stays
empty — ADR-0019's mechanism is untouched, and the icon's colours live in the `.icon` bundle,
not in the global accent.

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

**The tinted and clear variants are derived and have not been seen.** They are present in the
compiled catalogue (`ISAppearanceTintable`), but no script can render them —
`NSWorkspace.icon(forFile:)` ignores the drawing appearance for this axis, because icon style is
a separate user setting rather than Dark Mode. Only Icon Composer shows them.

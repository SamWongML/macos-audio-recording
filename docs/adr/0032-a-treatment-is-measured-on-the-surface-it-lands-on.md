---
status: accepted
---

# A treatment is measured on the surface it lands on, in both appearances

The after-picture ([#103](https://github.com/SamWongML/macos-audio-recording/issues/103)) found six
defects and [#104](https://github.com/SamWongML/macos-audio-recording/issues/104) fixed them. Two of
the six were the same mistake, made a year of tickets apart by two different decisions that were
each sound as written:

- The loupe's `±2 s` caption is `.caption2` in `.tertiary`. Over the loupe's `.regularMaterial` in
  Dark it measured **1.07 : 1** — the brightest glyph pixel `(57,57,57)` against a panel of
  `(53,52,56)`. The same style is legible in Light, and legible again in Dark under Reduce
  Transparency, where the material is swapped for an opaque window background.
- [ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md) gave the trailing column
  `.controlBackgroundColor`, *"one step off the window's own background"*. In Dark that is a step —
  `(43,42,42)` to `(28,28,28)`. In Light it is not: `NSColor.controlBackgroundColor` and
  `NSColor.windowBackgroundColor` are **the same value** in both appearances — `(255,255,255)` in
  Light, `(30,30,30)` in Dark — so the "material shift" resolved to zero difference and the
  three-column editor read as two with cards floating at the right.

Neither was a bad choice of colour. Both were **colours chosen from a palette and never measured
where they were going to land**, and in both cases the thing that ate them was a property of the
destination, not of the colour: vibrancy in the first, and Apple shipping one value for two
semantic roles in the second.

## The rule

**A treatment is not decided until it has been measured on the surface it will be drawn on, in both
appearances.** The palette states intent; the render states the result; only the render is evidence.

Three consequences, each of which cost a ticket to learn:

**A hierarchical style over a material is a vibrancy style, and vibrancy is what collapses.**
`.secondary`, `.tertiary` and `.quaternary` do not resolve to fixed colours — over a dark material
they blend toward it. `.secondary` was tried on the caption first and measured only **2.77 : 1**,
still under the 4.5 : 1 floor for text that size. `Color.primary.opacity(0.7)` composites normally
and measures **6.47 : 1** on the same panel, against the figure beside it at 11.39 : 1 — subordinate
where it needs to be subordinate and legible where `.tertiary` was not. **Where a hierarchical rung
cannot be measured clear of its floor, state the colour flat and subordinate it with opacity.**

**Two system colours that differ by name may not differ by value.** `controlBackgroundColor` and
`windowBackgroundColor` name two roles and ship one value. Where a design depends on a *step*
between two system colours, the step has to be measured, and where it does not exist it has to be
manufactured: the column now carries `.controlBackgroundColor` plus a flat black scrim at 0.05, so
it steps in Light (255 → 242) and keeps its Dark step (42 → 27). The scrim is deliberately **not**
appearance-adaptive — the column wants to be *darker* than the detail in both appearances, and
`.quaternary` is white on dark and would invert it. This does **not** make the column a third owned
colour: [ADR-0019](0019-content-is-the-colour.md)'s *chrome stays on system materials* stands, and
this is a system colour with a measured correction.

**"Verified" means verified in both appearances.** ADR-0025's column decision was checked in Dark
and shipped; the Light half was wrong for four tickets and nobody looked. Report 0006's grounding —
Xcode and Finder tell panes apart by background, not by a rule — was and is correct; what was never
true is that *this app's* two backgrounds differed in Light.

## Consequences

ADR-0025's *"the column takes `.controlBackgroundColor`, one step off the window's own background"*
is **amended**, not reversed: the mechanism stands, the claim that the system colour alone produced
the step does not. The separation is still a background step and still not a hairline.

This ADR is a rule about evidence, so it has no opposite worth arguing: it does not say what any
colour should be, only that a colour is not decided until it has been read off the running app in
both appearances. Every figure quoted above is a sample from a `screencapture -x -o -l` of the
Release build, not a computation from the asset catalogue.

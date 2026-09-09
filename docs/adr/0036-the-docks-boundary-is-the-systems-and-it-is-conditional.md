---
status: accepted
---

# The dock's boundary is the system's, and it is conditional

*(Amended by [ADR-0038](0038-the-dock-has-a-fill-and-it-is-the-bars-own.md). The modifier stands and
the fix is real. **The title is wrong and so are three numbers below:** the boundary is not
conditional, it is `safeAreaBar`'s own fill rather than the scroll edge effect, and the floor is a
window of 960 × 656. Each is marked where it appears.)*

The Export dock is pinned to the trailing column's bottom edge with **no fill and no rule**
([ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md)): it *"separates by air and
by alignment"*, because a darkening bar over a column that already reads as separate is the
decorative chrome [ADR-0019](0019-content-is-the-colour.md) spends its budget avoiding.

That was a bet that the column never scrolls, and at `1200 × 680` it does not — which is the only
size the dock had ever been shot at. At **960 × 552, the window's floor as it then stood**, the column overflows
by 93–118 pt ([ADR-0030](0030-the-trailing-column-sets-the-default-height.md)'s numbers: the column
stops drawing a scroller at 645, and needs 670 for the longest Correction caption). The `Level`
group then scrolled straight through the transparent dock — the Gain slider's track and thumb drawn
*below* the `Export…` button and cut by the window's bottom edge, `−12` and `+12` straddling its
corners, in the column's **resting** scroll position in both appearances. The failed phase, the one
whose text is the payload, was drawn over the `Gain` row, the group's separator rule and the
slider's white thumb ([#108](https://github.com/SamWongML/macos-audio-recording/issues/108),
research 0008 finding 2).

**The dock still gets no fill. It gets the system's boundary, and the whole fix is one word:
`safeAreaBar` instead of `safeAreaInset`.**
*(The one word is right; **the dock does get a fill** — `safeAreaBar`'s own, 27 → 35 in Dark and
242 → 250 in Light, unconditionally. ADR-0038.)*

The two modifiers lay out identically. Only `safeAreaBar` *"extends the edge effect of any scroll
views affected by the inset safe area"* — it is macOS 26's purpose-built modifier for a bar pinned
over scrolling content, and it did not exist when [#76](https://github.com/SamWongML/macos-audio-recording/issues/76)
pinned this control. ADR-0025 was never wrong; it was written against the older of two modifiers.

## Considered options

**`.scrollEdgeEffectStyle(.hard, for: .bottom)` was measured and rejected.** The docs sell `.hard` as
*"a linear, nearly opaque boundary between pinned controls and scrolling content"*, which is exactly
what the failed phase's sentence wants to sit on. It also **paints unconditionally**: measured at
`1200 × 680`, where the column does not scroll and nothing passes beneath the dock at all, it still
laid down a band — **27 → 35 in Dark, 242 → 250 in Light**. That is the `Material.bar` ADR-0025
deleted from this dock, arriving under a system name. `.automatic` measured **0/0/0** at the same
size in both appearances: it draws only where content actually overlaps.
*(**Reproducible at 1200 × 680 and at no other size measured.** That is `.defaultSize`, and a window
whose saved frame equals it never resizes on restore, which is what the fill waits for. `.automatic`
and `.hard` paint the same band to within 4/255 wherever nothing passes beneath. ADR-0038.)*

So the choice was not "system effect or our own fill" but **conditional or unconditional**, and the
conditional one is the only one compatible with ADR-0025.
*(There is no conditional one: `.automatic`, `.soft`, `nil` and `.scrollEdgeEffectHidden(true)` are
pixel-identical, and the fill under all four is unconditional. ADR-0038.)* Nothing is set in the code on purpose —
`.automatic` is what `safeAreaBar` already gives, and writing it out would invite someone to
"improve" it to `.hard`.

**Raising the window's height floor to ~672 was rejected**, and it was the cheapest option on the
table: above ADR-0030's 670 the column never scrolls at any allowed size, so the bare dock would
have stayed literally correct by construction, and the overlay scroller would never return either.
It fails on the same ground twice. It forbids a state the app can now handle, and it would leave
this treatment rendering **at no size any machine can produce** — a boundary nobody could ever watch
fail. That is precisely how the dock arrived here: ADR-0025's bare dock was correct at every size
anyone shot.

**Making the column stop needing to scroll was not live.** The overflow at the floor is 93–118 pt and
the `Level` group is about that tall entire; giving it up means giving up Normalize, Correction and
Gain, which is issue #55 and [ADR-0013](0013-loudness-is-one-clamped-gain-not-a-limiter.md).

**Clipping the `Form` at the inset — a `VStack` rather than a safe-area inset — was rejected.** It
keeps "no fill and no rule" untouched and content never travels under the dock at all. It is also a
hard cut where macOS 26 and later expect content to flow beneath a bar, and it is the one option
that would make this window read as older than the OS it ships on.

## Consequences

**The overlay scroller comes back at the floor, and it stays.** Below 645 pt macOS draws it down the
column, overlapping the group's trailing edge by 8 pt — the blemish #76 pinned the control to remove
(finding 4), and the thing ADR-0030 calls *"the scroller that is wrong, not the content"*. It is
kept because it appears only when the content genuinely does not fit, which is the one moment it
tells the truth; hiding it with `.scrollIndicators(.never)` would suppress the only signal that
content continues, at exactly the size where content is in fact hidden. If the 8 pt overlap ever
reads as a collision rather than an overlay, the answer is to inset the content margins, not to hide
the indicator.

**`minHeight` is declared **604**, and the number moved twice inside this one change.**
*(604 is a **content** height. The window it produces is **960 × 656** — `.frame(minHeight:)` does
not include the 52 pt title bar — and `safeAreaBar` costs 0 pt of minimum, not 52. ADR-0038.)* The old
comment called the declared 500 *"honest about never being the number you hit"*, which is the one
thing a declared minimum must not be — a constant nothing can reach is a second, wrong answer to
"how short can this window get", sitting in the file a reader checks first. It was corrected to
ADR-0030's measured **552** — **and 552 went stale in the same commit that wrote it.**
`safeAreaBar` reserves height for the scroll edge effect it carries, so swapping the dock off
`safeAreaInset` grew the column's own minimum by **52 pt**. `spacing: 0` was tried and reclaims none
of it: the space is the effect's, not the bar's padding. Re-measured the same two independent ways
as the 552 — saved-frame launch, and live interactive resize on a fresh install with no defaults —
both clamping to exactly **960 × 604**, with 605 holding.

**This is not the floor raise rejected above.** That one was a deliberate 672 chosen to put the
column's overflow out of reach; this is 52 pt the treatment costs, and at 604 the column still
scrolls, which is the whole point. But it is worth naming what happened: the fix for a stale
declared minimum shipped a stale declared minimum, because the number was written before the change
that moved it was measured. **Declare the floor last.**

**Every "at the 960 floor" figure in this repo now means one of two heights.** Everything measured
before this ADR was measured at **960 × 552**; everything after is at **960 × 604**.
*(Read the second number as **960 × 656**: 604 is the content, 656 is the window. ADR-0038.)* ADR-0029's
verification, ADR-0030's table, research reports 0008 and earlier, and issues #97, #103, #104, #108
and #113 all mean 552. This ADR and everything after it mean 604.

Every figure here is sampled from `screencapture -x -o -l` of the Release build at both sizes in both
appearances, not computed from the asset catalogue (ADR-0032).

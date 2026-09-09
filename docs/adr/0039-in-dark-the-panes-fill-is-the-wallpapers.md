---
status: accepted
---

# In Dark the panes' fill is the wallpaper's, and so is the step between them

[#115](https://github.com/SamWongML/macos-audio-recording/issues/115) opened on a measurement that
is real and a control that is not. The measurement: in Dark the editor's sidebar is `(42,42,42)`
against a detail of `(42,42,42)` — **a step of `1.000 : 1`**, with no divider — so in the three
states where the detail draws nothing but its own background (empty Library, nothing selected,
can't-open) the window's left 1200 pt is one flat field. The control, from research 0008 finding 3,
was that *"Finder's sidebar is `(41,40,41)` against a content pane of `(37,36,37)`, with a divider
at x = 202–205"*, and therefore that **the system separates its two panes and AppTape separates
them by nothing.**

**Re-measured on this machine, Finder does neither of those things.** There is no divider: the band
at x = 191–202 is the sidebar's **scroller** — `(93,93,93)` at y = 100, 300 and 500, dimming to
`(55,55,55)` at y = 640 where it ends, 11 pt wide where a divider is 1 — and x = 202–205 is the
last three points of the sidebar's own fill, with the content pane starting at 205. And the two
fills research 0008 reported are not fixed values.

## Both panes are behind-window vibrancy, so in Dark the step is the desktop's

The sidebar and the detail are each an `NSVisualEffectView` blending what is *behind the window*.
In Dark that is the wallpaper, so neither pane's colour is a value the app owns, and the step
between them is whatever the desktop puts there. Like-for-like, Dark, empty content pane, the same
two window frames on the same wallpaper:

| window origin | Finder sidebar / content | AppTape sidebar / detail |
|---|---|---|
| `(360, 215)` — the harness's centred frame | `(42,42,42)` / `(42,42,42)` — **1.000 : 1** | `(42,42,42)` / `(42,42,42)` — **1.000 : 1** |
| `(40, 60)` | `(45,45,45)` / `(48,48,48)` — **1.053 : 1** | `(44,44,44)` / `(46,46,46)` — **1.028 : 1** |

AppTape tracks Finder within 0.025 of a ratio at both, and **both collapse to `1.000 : 1` at the
same frame**. The zero is not AppTape's; it is what these two system materials do over this
wallpaper at this position, and Finder does it too. Research 0008's `(41,40,41)` / `(37,36,37)` is
the same pair of materials over a different patch of desktop.

**Light is the opposite and needs saying, because it is the half that looks like the safe one.**
The materials clamp: `(237,237,237)` against `(255,255,255)`, **`1.171 : 1`, identical at both
positions**. So the appearance that has a real step has a *fixed* one, and the appearance that has
none cannot be given one by moving a fill.

## So the boundary keeps what it has

**Nothing is added.** A step cannot be the instrument here, because in Dark neither pane owns the
value a step would be made of, and the app is already drawing exactly what the system's own app
draws. Two candidates were built into the running app and measured before this was settled
([`prototype/editor-sidebar-boundary`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-sidebar-boundary)):

- **A `separatorColor` hairline**, full window height — `1.363 : 1` in Dark, wallpaper-independent,
  no fill moved. Rejected because the corrected control removes its warrant: Finder draws no line
  at this boundary, and this map does not add chrome the system does without one
  ([ADR-0019](0019-content-is-the-colour.md)).
- **Taking the sidebar off the material** — `windowBackgroundColor` plus
  [ADR-0032](0032-a-treatment-is-measured-on-the-surface-it-lands-on.md)'s scrim, which makes the
  sidebar *pixel-identical to the trailing column*: `1.200 : 1` Dark, `1.119 : 1` Light, stable at
  every position. Rejected for what it costs: the sidebar's vibrancy, and **Light separation** —
  `1.171 → 1.119` empty, `1.091 → 1.036` populated. Buying Dark by spending Light is the shape
  ADR-0032 exists to catch, and here it was measured rather than argued.

## Consequences

**The window's position on the desktop is a variable in Dark**, as [#108](https://github.com/SamWongML/macos-audio-recording/issues/108)
found the window's *size* to be. `launch.sh` centres every window, so every Dark fill figure this
map holds was taken over one patch of one wallpaper. Figures for anything drawn on a system
material — the sidebar, the detail's own background, the `.bar` footer — are that wallpaper's, not
the app's, and re-measuring them elsewhere will not reproduce them. Figures for the app's **owned**
fills are unaffected: the trailing column, the lane, the Export dock all draw flat colours, which
is why the column's `1.200 : 1` / `1.119 : 1` held across five states and both appearances in #108
and holds here at every position tested.

**And the asymmetry between the two boundaries is now explained rather than tolerated.** The
trailing column gets a step because it stopped using a material and draws a fill the app owns
([ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md),
[ADR-0035](0035-the-trailing-column-reaches-the-windows-top-edge.md)). The sidebar boundary gets
none because both its sides are still the system's. Two boundaries, two instruments, for a reason
that is in the mechanism and not in the taste.

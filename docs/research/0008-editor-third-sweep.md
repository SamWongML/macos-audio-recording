# The editor, swept a third time

**Issue [#108](https://github.com/SamWongML/macos-audio-recording/issues/108) · the after-after-picture · Release build, macOS 27, both appearances, 1200 × 680 and the 960 floor**

**No — the destination is not reached, and this time the gap is not in a state nobody photographed. It is in the state everybody gets first.** Five defects and two decisions. Four of the five were invisible to the two earlier sweeps because both shot one window size, and the fifth was two hundred lines away from a fix that had already been applied to its twin.

Evidence: 30 screenshots and the harness on [`prototype/editor-third-sweep`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-third-sweep/tools/third-sweep). Every number below is read off a rendered pixel, never off the palette (ADR-0032).

---

## The five defects

### 1. At its own default size, the editor opens with the keyboard nowhere

`AppTapeApp.swift:80` declares `.defaultSize(width: 1200, height: 680)`. At **exactly** that frame, a freshly-opened editor has `AXFocusedUIElement` = the `AXWindow`; the selected row wears the **inactive** fill `(71, 71, 72)`; and pressing ↓ does nothing — before and after frames byte-identical on rows 1 and 2.

One pixel either way and it is a different app:

| frame | `AXFocusedUIElement` | selected row | ↓ |
|---|---|---|---|
| 960 × 552 | `AXOutline` | accent `(47, 108, 248)` | moves |
| 1040 × 560 | `AXOutline` | accent | — |
| 1120 × 620 | `AXOutline` | accent | — |
| **1160 × 680** | `AXOutline` | accent | **moves** |
| 1200 × 640 | `AXOutline` | accent | — |
| 1200 × 681 | `AXOutline` | accent | — |
| 1201 × 680 | `AXOutline` | accent | — |
| **1200 × 680** | **`AXWindow`** | **grey** | **does nothing** |

Five runs at the default, six off it, all deterministic. The trigger is the saved frame *matching the declared default*, which is what every first run gets and what `#99` made the app open at.

This is [ADR-0029](https://github.com/SamWongML/macos-audio-recording/blob/main/docs/adr/0029-the-selection-fill-is-the-systems-the-focus-is-ours.md)'s own defect, back on the path nobody has to do anything to reach. Its table's first row reads *Editor just opened → `AXOutline` → accent*; that row is now true at every size except the shipped one. `#95` measured it at whatever size that session happened to use, and `#96`'s fix — moving focus into the list from `selectionBinding`'s setter — only fires on a click or an arrow key, so it cannot cover the moment before the user has done either.

The fill itself is still not wrong, exactly as ADR-0029 argued: the keyboard really is not in the list. The state is.

### 2. At the 960 floor the Export dock is transparent over a column that has to scroll

The dock is a `.safeAreaInset(edge: .bottom)` with, deliberately, **no fill and no rule** — `ExportInspector.swift:140`, ADR-0025, re-affirmed by `#104`. That holds while the column never scrolls, which at 1200 × 680 it does not.

At **960 × 552 — the window's own declared minimum** — it does. The `Level` group scrolls under the dock and renders straight through it: the Gain slider's track and thumb are drawn **below** the `Export…` button and cut off by the window's bottom edge, with `−12` and `+12` straddling the button's corners. Both appearances, on first sight of the column, before the user touches anything. Scrolling to the bottom clears it, so this is the *resting* position, not an edge case.

The failed phase is where it costs something. `#104` rewrote that phase — `Try Again…` → `Retry…` — so the sentence could carry both figures inside the shared 34 pt dock, and it does:

> ⚠ Not enough space: needs 39.2 MB, 1.91 MB free.   `Retry…`

At 960 that sentence is drawn over the `Gain` row, the group's separator rule and the slider's white thumb. The text fix works; the phase is unreadable anyway. `#104` verified this phase at 1200 × 680 only, which is exactly the width at which the fault cannot appear.

### 3. In Dark the sidebar and the detail pane are the same colour — exactly

| appearance | sidebar | detail | step |
|---|---|---|---|
| Dark | `(42, 42, 42)` | `(42, 42, 42)` | **1.000 : 1** |
| Light | `(237, 237, 237)` | `(255, 255, 255)` | 1.171 : 1 |

Measured in five states — populated, empty Library, nothing selected, can't-open, and at the 960 floor — and identical in all of them. There is no divider either.

Control, on this OS, this appearance: **Finder's sidebar is `(41, 40, 41)` against a content pane of `(37, 36, 37)`, with a divider at x = 202–205.** The system separates its two panes; AppTape separates them by zero.

Populated, the rows carry the eye and nobody notices. On the three states `#106` and `#111` just finished designing — empty Library, nothing selected, can't-open — the window's left 1200 pt is **one flat field with a search box floating in it**, and the sentence that is supposed to be centred in the detail reads as off-centre in a merged surface.

This is `#103`'s finding 6 exactly — *"the decision was sound and was verified in one appearance only"* — on the other pane and the other appearance. ADR-0032, third instance.

### 4. `48 kHz stereo · carried through unchanged` is the loupe caption's twin, unfixed

`ExportInspector.swift:251-255`: `.font(.caption2)` + `.foregroundStyle(.tertiary)`.

| appearance | background | brightest glyph pixel | contrast |
|---|---|---|---|
| Dark | `(34, 34, 34)` | `(89, 89, 89)` | **2.27 : 1** |
| Light | `(235, 235, 235)` | `(174, 174, 174)` | **1.86 : 1** |

Identical at 1200 and at 960 — the column is a fixed 276 pt at every width.

Those are the same two modifiers `#104` deleted from `TrimTimeline.swift:364` and wrote [ADR-0032](https://github.com/SamWongML/macos-audio-recording/blob/main/docs/adr/0032-a-treatment-is-measured-on-the-surface-it-lands-on.md) about, two hundred lines up the same file, left alone because the ticket pointed at one of them and not the other. It is the **only** `.tertiary` left on text a user is meant to read; every other surviving one is a glyph (`rectangle.dashed`) or a during-capture placeholder.

One difference worth stating, because it changes the fix: the loupe's caption failed as a *vibrancy blend* over a material. This one is over the trailing column's opaque scrim, so `.tertiary` does resolve to a real colour here — it is simply too faint a one. `Color.primary.opacity(0.7)` measured 6.47 : 1 in `#104`'s case and would clear the floor here too.

### 5. In Light the playhead falls under its own 3 : 1 floor over the trimmed-away peaks

[ADR-0033](https://github.com/SamWongML/macos-audio-recording/blob/main/docs/adr/0033-the-playhead-is-an-instrument-not-content.md) books no trade: 3 : 1 against every fill it crosses. Its table has three fills. **The lane has six**, because `TrimTimeline.waveform` draws the audio twice — `shape.grayscale(1)` under a masked colour copy — and greyscale makes three more.

Measured per row (`#105`'s rule: a single sampled playhead colour is meaningless), black ink at full strength:

| Light, lane fill | contrast |
|---|---|
| lane ground `(246,246,246)` | 19.43 : 1 |
| kept body `(97,96,189)` | 3.92 : 1 |
| kept peaks `(77,75,202)` | 3.24 : 1 |
| trimmed body `(103,103,103)` | 3.71 : 1 |
| **trimmed peaks `(85,85,85)`** | **2.82 : 1** |

45 of 587 sampled rows sat on the failing fill. Dark is fine everywhere — 8.02 / 6.18 / 4.45 over the desaturated fills, 8.02 / 5.71 / 3.83 over the coloured ones.

**And it is reachable.** `AudioPlayer` starts at the Trim's lower bound, so ordinary playback never leaves the kept region — which is why five earlier sessions never saw this. But `TrimTimeline.scrub` calls `player.seek(to: t)` with **no clamp**, so a click anywhere left of the Trim start parks the playhead over the desaturated audio. That is the screenshot above.

The mechanism is ADR-0032 one level down again, and it is the same one as finding 6 below: in Light the greyscale stop is *darker* than the colour it replaces, so the surface a black playhead has the least room against is the one nobody thought to measure.

---

## The two that are decisions, not defects

### 6. In Light the trimmed-away audio reads louder than the kept audio

| | Dark: kept | Dark: trimmed | Light: kept | Light: trimmed |
|---|---|---|---|---|
| peaks | 2.22 : 1 | **1.92 : 1** | 6.12 : 1 | **6.90 : 1** |
| body | 1.49 : 1 | **1.38 : 1** | 4.96 : 1 | **5.23 : 1** |

In Dark the trimmed-away half recedes by ~13%, as intended. In Light it **advances** by ~13%: against a near-white ground the grey has more contrast than the indigo it replaced, so the half that is not being exported is the more present of the two.

The mechanism is not a mistake. `grayscale(1)` roughly preserves luminance, and `TrimTimeline`'s own comment says so: *"what changes outside the Trim is **colour, not brightness**"*, chosen over the `.background.opacity(0.62)` overlay precisely so it would need no per-appearance magic number. It does what it says. The question the picture raises is whether *colour only* is enough in Light, where colour alone no longer implies quieter — and that is a decision against ADR-0019, not a bug against it.

### 7. The trailing column's colour is **not** still wrong

The map held this open: *"Whether that holds is a question only the third sweep can ask, because it needs the fixed column photographed by someone who has not just spent a session looking at it."*

| appearance | detail | column | step |
|---|---|---|---|
| Dark | `(42,42,42)` | `(27,27,27)` | 1.200 : 1 (−35.7%) |
| Light | `(255,255,255)` | `(242,242,242)` | 1.119 : 1 (−5.1%) |

Unchanged from `#111`, and the fill reaches y = 0 in every state and both appearances (`#112` holds). Photographed cold, across five states, **it reads as a pane, not a hole.** `#111`'s call — the shape was the defect, the darkness was not — survives. Variant B is not needed and ADR-0032 does not need superseding.

What the sweep found instead is that the window's *other* vertical boundary has the opposite fault in the opposite appearance (finding 3). The asymmetry worth spending a ticket on is the sidebar's zero, not the column's 32%.

---

## What still holds

Re-checked, all green:

- **`#104` defect 1**, the loupe's `±2 s` caption, in six combinations: **6.38** (Dark 1200), **6.17** (Dark 960), **5.24** (Light 1200), **5.25** (Light 960), **6.68** (Dark + Reduce Transparency), **5.55** (Light + Reduce Transparency). All clear 4.5 : 1; the figure beside it runs 11.0–14.6 : 1, so it is still subordinate. Reduce Transparency, where the material goes opaque, is the surface nobody had measured the *new* style on — it is the best of the six.
- **`#104` defect 2**: the failure names both figures.
- **`#104` defect 3**: the column's fill is full height in all three empty branches, both appearances — and now runs to the top edge.
- **`#104` defect 4**: the title bar names the Recording on the editor path (`hhh` · `Google Chrome · Sep 4, 2026 at 21:52`), names the file on the can't-open path (`Not audio` · `Sep 8, 2026 at 0:27`), and falls through to `AppTape` with nothing selected.
- **`#104` defect 6**: Light keeps its column boundary, 1.119 : 1.
- **`#105`**: over the *kept* fills the playhead measures 8.02 / 5.71 / 3.83 (Dark) and 19.43 / 3.92 / 3.24 (Light) — ADR-0033's own figures reproduced.
- **`#106`**: one sentence per state, in the detail, in all three states; the column silent in all three; the sidebar keeps its search field and its `0 Recordings · Reveal` footer.
- **`#112`**: the column reaches the window's top edge, every state.
- **Reduce Transparency** changes nothing else in the editor — the loupe is its only vibrant surface, and both Reduce-Transparency shots are otherwise pixel-equivalent to the default path.

One typographic nit, filed here rather than as a defect: at 1200 the no-selection sentence wraps as *"Choose one in the Library to play it, set its Trim, and / Export it."*, orphaning two words. At 960 it fits one line. `ContentUnavailableView` owns that width.

## Not re-run, and why

- **The during-capture `Correction` row** (`#104` defect 5). `#104` verified it end to end against a real capture — `—` while the master grew to 37 MB, then **−5.9 dB** at Stop — and the row's treatment cannot vary with window size, because the column is a fixed 276 pt at every width. Re-running a capture would have re-photographed a row already photographed in the only state that changes it.
- **Increase Contrast** and **large Dynamic Type**, for the measured reasons `#103` established: `NSAppearance(named: .accessibilityHighContrastDarkAqua)` does not take, `\.colorSchemeContrast` is get-only, and `.dynamicTypeSize(.accessibility3)` renders a pixel-identical window because macOS does not scale system fonts through it.

## Harness notes for whoever is next

- **The window size is a variable, not a constant.** Four of the five defects here need a size other than 1200 × 680 to exist, and one needs 1200 × 680 *exactly*. Two sweeps at one size found none of them. Shoot the floor and the default, always.
- **`AXFocusedUIElement` is cheap and it is evidence.** Reading it beside the selection fill is what turned "the fill looks different between two shots" into a deterministic, one-pixel-wide trigger.
- **A `.safeAreaInset` dock with no fill is a bet that the content never scrolls.** Anything pinned that way needs shooting at the smallest window the app allows.
- **`grayscale(1)` doubles the lane's fill count.** Any future contrast table for anything drawn over the waveform has six rows, not three, and in Light the greyscale halves are the darker ones.
- Nothing was left changed: the Library counted 39 → 39 across every aside and fixture, all six `com.apptape.trim` xattrs were backed up before the run and diffed identical after, the 2 MB image was detached and deleted, and the editor's saved frame and split-view widths were written back to what they were.

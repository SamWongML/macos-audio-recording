# Sidebar-boundary prototype (issue #115)

Throwaway. Drives the shipping Release build, builds five candidate boundaries into it behind
`APPTAPE_BOUNDARY`, and measures the fills off screenshots. **Never merged.** Forked from the
[third-sweep harness](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-third-sweep/tools/third-sweep)
(#108), whose rules all still apply — shoot in Release, launch fresh at a saved frame, address the
process by `unix id`, restore the Library counted both ways.

## Variants (`AppTape/AppTape/BoundaryVariant.swift`)

| | |
|---|---|
| `a` | baseline — what ships today |
| `b` | a `separatorColor` hairline at the boundary, running to the window's top edge |
| `c` | the trailing column's scrim painted *behind* the sidebar's list |
| `d` | `.scrollContentBackground(.hidden)` + `windowBackgroundColor` + that scrim |
| `e` | `d` + the hairline — Finder's arrangement as research 0008 described it |

## Scripts added to the fork

| | |
|---|---|
| `boundary.py <png> <logical-w> <split-x> [y …]` | The two pane fills, their contrast, and every colour run in the 20 pt either side of the seam. |
| `extent.py <png> <logical-w> <split-x>` | How far up and down the seam anything is actually drawn. |
| `atpos.sh <x> <y> <w> <h> <dark\|light>` | `launch.sh` at a caller-chosen **origin**. |
| `emptyat.sh <x:y:w:h:appearance:out> …` | `empty.sh` at a caller-chosen origin. |
| `sheet.py <appearance> <variant …>` | Side-by-side comparison sheet of the seam. |

## What this harness had to add, and why

`atpos.sh` / `emptyat.sh` exist because **the window's position on the desktop is a variable in
Dark**, the way #108 found the window's *size* to be. `launch.sh` centres every window, so every
figure in this map taken before #115 was taken over the same patch of wallpaper.

## Two defects found in the prototype itself, before it was compared

- **The hairline first drew 169 pt of a 680 pt window.** Overlaid on `detailContent`, which has no
  intrinsic height in the empty, nothing-selected and can't-open states — issue #103's finding 3,
  on this boundary. It belongs on the `HStack`.
- **`c` is nearly a no-op in Dark and a large move in Light** (42 → 40; 237 → 225): the exact wrong
  asymmetry, since the defect is in Dark. A scrim behind an `NSVisualEffectView` does not do what a
  scrim behind an opaque fill does.

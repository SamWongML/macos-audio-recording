# Unencodable-rung prototype (issue #119)

Throwaway. Drives the shipping Release build with six candidate shapes for an **unencodable**
Quality Preset rung's plain reason (ADR-0015), behind `APPTAPE_RUNG`, and measures each off a
screenshot. **Never merged.** Forked from the [sidebar-boundary harness](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-sidebar-boundary/tools/sidebar-boundary)
(#115), whose rules all still apply — shoot in Release, launch fresh at a saved frame, centre the
window, `AXRaise` before any click.

The state exists at all because the Library holds **`ZZ Probe 96k`** (2 ch / 96 kHz / Int16), which
renders three unencodable rungs at once. `launch.sh` selects it without a click: it is the newest
Recording, and `EditorModel.reconcileSelection` selects the newest on first open. **No sidebar row
is ever clicked by this harness** — #116 renamed a real Recording that way.

## Variants (`AppTape/AppTape/RungVariant.swift`)

| | | reason, Dark | reason, Light |
|---|---|---|---|
| `a` | baseline — orange sentence, whole row at `.opacity(0.5)` | 1.58 : 1 | 1.22 : 1 |
| `b` | ADR-0037 mechanically: orange ⚠ mark, sentence ink; row still halved | 2.00 : 1 | 1.65 : 1 |
| `c` | reason exempt from the row's `.opacity`, ink; estimate dropped | 4.03 : 1 | 3.01 : 1 |
| `d` | `c` with the reason `.secondary` | 2.49 : 1 | 1.82 : 1 |
| `e` | reason lifted **out** of the disabled Button, ink | **11.71 : 1** | **13.02 : 1** |
| `f` | `e` with the reason `.secondary` | 5.72 : 1 | 3.81 : 1 |

`e` ships. Identical figures at `1200 × 680` and at the `960 × 656` floor.

## What this harness had to add, and why

`c` is the variant that reads like it should have worked and did not. Exempting the reason from the
row's explicit `.opacity(0.5)` bought only 4.03 / 3.01, because **`.disabled()` dims its subtree's
text on its own** — the halving was being applied twice, and only one of the two was in the app's
source. Nothing short of moving the text out of the Button recovers full strength: that is `e`, and
it lands in ADR-0037's own 11–14 : 1 band.

## Two states this harness can reach that no earlier one could

- **Three unencodable rungs at once**, from `ZZ Probe 96k` — the state #114's after-picture could not
  photograph and ADR-0037 ticketed rather than fixed.
- **A checkmark on a rung that cannot encode.** `defaults write com.samwongml.AppTape
  com.apptape.exportPreset -string high` before `launch.sh` makes the *sticky* preset unavailable for
  this file, so `effectivePreset` is unavailable and the tick lands on a disabled row with Export
  blocked. Reachable in the real app by picking High on a 48 kHz Recording and then selecting this one.

## Scripts

Inherited unchanged from the sidebar-boundary fork, except `launch.sh`, which now threads
`APPTAPE_RUNG` instead of `APPTAPE_BOUNDARY`.

## After-pictures

`shots/after-*.png` are the **shipped** shape (PR #124), shot from the same Release product:
`after-{dark,light}-{1200,960}.png` and `after-sticky-{dark,light}.png` (a tick on a rung that
cannot encode). The reason holds at **11.71 : 1 Dark / 13.02 : 1 Light** in all six.

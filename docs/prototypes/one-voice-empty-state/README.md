# Evidence for issue #106 — one voice per empty state

Shot on a Debug build at `1200 × 680`, editor opened from the panel's `Open Editor` link.
The empty-Library shots were taken with `~/Music/AppTape` moved aside on the same volume and
restored in the same shell invocation, verified 39 files → 39 files.

| file | state |
|---|---|
| `before-empty-dark.png` | `main` — empty Library, Dark. Three headings, three glyphs, two impossible instructions. |
| `before-empty-light.png` | `main` — empty Library, Light. |
| `after-empty-dark.png` | branch — empty Library, Dark. One sentence. |
| `after-empty-light.png` | branch — empty Library, Light. |
| `after-noselection-dark.png` | branch — 39 Recordings, nothing selected, Dark. The other state the change touches. |

Measured pane fills, identical before and after in both appearances:

| appearance | detail | column | step |
|---|---|---|---|
| Dark | `(42, 42, 42)` | `(27, 27, 27)` | 1.20 : 1 |
| Light | `(255, 255, 255)` | `(242, 242, 242)` | 1.12 : 1 |

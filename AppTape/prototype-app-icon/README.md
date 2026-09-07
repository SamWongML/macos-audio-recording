# PROTOTYPE — AppTape app icon (issue #79)

Throwaway. Nothing here ships; the winning mark gets rebuilt properly on `main`.

Five candidates as Icon Composer `.icon` bundles, judged as **real system renders**
— `NSWorkspace.icon(forFile:)` is the same pipeline the Dock draws with — and then
in the **actual Dock** next to real neighbours.

| | claim | mark | ground |
|---|---|---|---|
| A | the app is your audio | seven mirrored bars | pale `#E6E6F2`, bars `Signal` |
| E | same, saturated ground | seven mirrored bars | indigo `#4A48C8`, bars white |
| B | the app is the Trim decision | bars bracketed by two rails | indigo, white |
| C | the app is tape (abstract) | a reel: platter, hub, three cutouts | indigo, white |
| D | the app is tape (concrete) | a cassette: shell, two reels, window | indigo, white |

## Running it

```sh
python3 make_icons.py                    # writes AppTape{A,B,C,D,E}.icon
./dock-shot.sh                           # puts all five in the real Dock, shoots it, puts the Dock back
swift sheet.swift out.png <apps…>        # contact sheet at 320/128/64/32/16
swift crop.swift in.png out.png x y w h
```

`dock-shot.sh` backs the Dock up to `/tmp/cc-dock-backup.plist` and restores on exit.
If it ever dies mid-run: `defaults import com.apple.dock /tmp/cc-dock-backup.plist && killall Dock`.

## What the renders decided

- The app's own envelope polygon (`WaveformShape`, 30 column midpoints) **collapses into
  a blob below ~64 pt**. Faithful at 700 pt, unreadable in a Dock tile. Discrete bars are
  the same idea at icon scale — and are what the status item's `waveform` symbol already is.
- **Every tape mark read as something else.** A ring with three spokes rendered as a
  *steering wheel*; redrawn as a platter with three cutouts it renders as a *film reel*.
  A capsule with two holes rendered as a *toggle switch*; redrawn as a shell with a tape
  window it renders as a *bowtie on a card*. Two rounds, four drawings, nothing said "audio".
- **B's Trim rails collapse into the waveform at Dock size** — at 128 pt they read as two
  more bars, so B is E wearing a moustache. That is why E exists: with the Trim eliminated,
  the live question is only *pale ground or saturated ground*.

## Round 2 — refinements of the picked mark

A picked. Round 2 varies one thing at a time: F refines the drawing, G retries the
Trim with colour instead of rails, H drops to five bars.

- **F is the drawing.** Stockier bars (66 wide on a 36 gap, against A's 58/42) and a
  steadier rhythm — one clear peak with one echo, rather than seven random heights.
  At 128 pt in Finder and in the real Dock it reads as a designed mark; A reads as noise.
- **The Trim cannot be said in the icon, and G is the second proof.** Round 1 said it
  with rails and they collapsed into the waveform. G says it with ADR-0019's own two
  stops — `Signal` kept, `Signal Muted` trimmed away — and the difference is faint at
  320 pt, gone by 64 pt. Two stops that are deliberately close enough not to fight on a
  700 pt lane are far too close to carry meaning in a 32 pt tile.
- **Five bars (H) is legible but not better.** Fewer bars reads as an EQ or a bar chart;
  seven keeps the waveform texture, and seven still resolves at 16 pt.
- **The pale ground's weak case is Light Mode Finder**, where the tile edge nearly
  vanishes against white and the mark reads as bars floating on the page. In Dark Mode,
  and in the Dock in either mode, it is the strongest thing in the row.
- **The dark and tinted variants exist and were never rendered.** `assetutil` on the
  compiled catalog shows all three stacks — `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`,
  `ISAppearanceTintable` — plus a derived `system-dark` gradient. The Finder shot does not
  show the dark one because macOS 26+ makes icon style a *separate* user setting from Dark
  Mode. Seeing them rendered needs Icon Composer, which stops on a licence agreement that
  is the human's to accept, so this is the one claim here backed by the catalog rather
  than by a screenshot.

## The dark variant, and the schema that took three probes

The system's *derived* dark variant keeps the SVG's own `#5856D6` over a near-black
grey gradient (`assetutil` shows `Color-3` 0.192 and `Color-4` 0.078 gray). Measured,
that is **~2:1** — the bars barely read. So the dark stop is declared, not derived.

`AppTapeFinal.icon` is F with:

- dark ground `#1A1929`, and
- dark mark `#9694F0` — which is **`Signal`'s High Contrast dark stop**, reused rather
  than invented. A small indigo mark on a near-black tile needs exactly the lift that
  Increase Contrast needs: `Signal` dark `#5E5CE6` measures 3.41:1 there, `#9694F0`
  measures 6.43:1.

**The schema is not guessable and `ictool` will not tell you.** Unknown keys are
dropped *silently* — four wrong shapes all compiled with zero errors and zero effect,
which is why every probe here checks `assetutil` for the value rather than trusting
the exit code. The real shape, from Icon Composer's own fixtures:

```json
"fill-specializations": [
  { "value": { "automatic-gradient": "extended-srgb:…" } },
  { "appearance": "dark", "value": { "automatic-gradient": "extended-srgb:…" } }
]
```

`fill-specializations` **replaces** `fill` — the entry with no `appearance` key *is*
the default. There is no `slot` wrapper, and the appearance is `dark`, not `dark-color`.
Layers take the same array under the same key with `{"solid": …}` values.

**Neither the dark nor the tinted variant can be rendered from a script.**
`NSWorkspace.icon(forFile:)` ignores the drawing appearance for this axis, because icon
style is a separate user setting (Settings → Appearance) rather than Dark Mode. Both are
present in the compiled catalog and neither has been seen. Icon Composer shows them.

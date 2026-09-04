# The editor's visual bugs — the before-picture

Ticket: [Sweep the editor for visual bugs and capture the before-picture](https://github.com/SamWongML/macos-audio-recording/issues/73).
Map: [Map: a premium AppTape editor](https://github.com/SamWongML/macos-audio-recording/issues/70).

**Status: partial.** Four editor states were captured and diagnosed before the machine's screen
locked, which ends screenshotting for the session. Everything below is either **observed in a
screenshot** or **read off the running app's accessibility tree** — both are first-hand. Findings
that are certain from the source but not yet photographed are marked so. The unphotographed states
are listed at the end.

## How this was captured

- Build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project
  AppTape/AppTape.xcodeproj -scheme AppTape -destination 'platform=macOS' build` on branch
  `fix/panel-live-source-waveforms` (the map's stated baseline). Builds clean.
- The app was launched, the panel opened from the status item, and the editor opened from the
  panel's **Open Editor**.
- Screenshots are `screencapture` of the editor window at 2× (`docs/research/assets/0003/`).
- Geometry and text come from the live accessibility tree, read with a small `AXUIElement` dumper.
- System at capture time: **Dark appearance**, default accent, `AppleShowScrollBars` unset
  (i.e. "Automatic"), Reduce Transparency and Reduce Motion both **off**.
- Window at its restored size **1186 × 558**, not the `.defaultSize(1120, 640)` declared in
  `AppTapeApp.swift` — finding 3 depends on the height, so both sizes want re-testing.

Library fixtures added for the sweep (removed afterwards): a Recording carrying two lane-drawn
Seams and one sub-threshold Seam; a 96 kHz WAV (which no AAC rung can encode faithfully); and a
`.mp3` of random bytes (a can't-open adopted file, ADR-0015).

## Findings

### Text and content

**1. The Seam summary prints its own markup.** The editor's Seam line reads literally
`^[3 Seam](inflect: true) · 2.8 s of silence padded in`, and on another Recording
`^[1 brief Seam](inflect: true) · 51 ms padded, too short to hear`.
`Recording.seamSummary` returns a `String`, so `Text(summary)` at `EditorView.swift:136` takes the
**non-localized** initializer and the inflection markup is never parsed. The sidebar footer's
`Text("^[\(count) Recording](inflect: true)")` is a literal `LocalizedStringKey` and renders
correctly — "42 Recordings" — which is why this went unnoticed. Both branches of
`Recording.seamSummary` (`Recording.swift:74–84`) are affected.
_Seen in `01-default.png`, `05-after-select.png`._

**2. The window title is the raw filename.** The title bar reads
`Google Chrome 2026-09-04 at 21.52.43` with the subtitle `Google Chrome` — the Source stated twice,
once wrapped in the on-disk naming scheme. The sidebar row for the same Recording shows
`Google Chrome` + `21:52`. `EditorView.swift:139` passes `recording.name`, which is the filename.
_Seen in `05-after-select.png`._

### Layout and clipping

**3. The Export button is off the bottom of the window.** The inspector's `Form` needs ~547 pt in a
506 pt scroll area, so `Export…` sits at **y = 797** while the window's bottom edge is **y = 794**.
The primary action of the pane is invisible at the window's restored size, and nothing indicates
there is more below. Read straight off the accessibility tree (`AXButton d=Export… [1710,797 74x24]`
inside `AXWindow [699,236 1186x558]`).
_Seen in `01-default.png` — the inspector ends at "Length"._

**4. The reported scrollbar overlap is the inspector's `Form`, not the sidebar.** The inspector's
`AXScrollBar` occupies x 1867–1886 while the Form's grouped boxes end at x 1875 — an **8 pt
overlap**, with the knob drawn over the group's trailing edge and eating the pane's trailing margin.
The sidebar's `List` scroller (x 949–968) clears its rows (which end at 940) and is not the culprit.
This is a **consequence of finding 3**: the Form only scrolls because its content does not fit, so
fixing the height removes the scroller.
_Seen in `crop-inspector-edge.png`._

**5. The Compact preset row is a different height from the other three.** `Compact` is 51 pt tall
against 38 pt for Master/High/Standard, because its subtitle `HE-AAC 64 kbps · 48 kHz stereo` wraps
at the 276 pt inspector width and breaks mid-phrase, leaving `kHz stereo` orphaned on line two. The
four rungs are meant to read as one comparable ladder (`ExportInspector.swift:150`).
_Seen in `01-default.png`, `crop-inspector-edge.png`._

**6. The sidebar silhouette is drawn through the timestamp.** `LibraryRow`'s waveform mask starts at
0.42 of the row width (`EditorView.swift:243–252`), but a long Source name pushes the time later: on
`Google Chrome` rows the `21:52` glyphs sit at ~0.44–0.50 and the silhouette runs straight through
them. Short names (`Zoom`, `Safari`) are clear. The mask was chosen as a fixed *fraction* so two
Recordings' silhouettes stay comparable — that goal and the name length are in direct conflict.
_Seen in `05-after-select.png` (selected row), `01-default.png`._

**7. The waveform has no vertical inset.** A loud Recording's envelope reaches the lane's top and
bottom and is cut flat by the rounded-rect clip, so ordinary loud material reads as *clipped audio*.
There is no headroom between the envelope's full-scale and the lane's edge
(`TrimTimeline.swift:66–69`).
_Seen in `05-after-select.png`._

### Colour and contrast

**8. The trimmed-away region is barely dimmed in Dark Mode.** `Rectangle().fill(.background.opacity(0.62))`
(`TrimTimeline.swift:76–80`) is dark grey over dark grey: at the trim boundary the two sides differ
only in the waveform's saturation, and the lane background is unchanged. A viewer cannot reliably
tell kept from trimmed. This defeats the stated contract — Trim never removes anything (ADR-0003)
"and the picture should say so" — and it is the very thing
[Study how modern audio editors fill the editor window](https://github.com/SamWongML/macos-audio-recording/issues/71)
concluded AppTape does *better* than its peers. On this evidence it currently does not.
_Seen in `crop-trim-dim.png`._

**9. A Trim handle parked on a Seam is unreadable.** `SeamBand` fills `.secondary.opacity(0.12)` with
`.secondary.opacity(0.55)` hatching (`SeamBand.swift:38`), and the Trim handle is a `.secondary`
capsule (`TrimTimeline.swift:172`) — the same grey. When a handle lands inside a Seam band the two
merge into one texture.
_Seen in `crop-trim-dim.png`._

**10. A Trim handle reads as a lane border, not a control.** At rest it is a 3 pt `.secondary`
capsule with a `.background`-coloured chevron that renders as a small dark notch. On an untrimmed
Recording both handles sit flush with the lane's edges and are indistinguishable from the lane's
own outline — there is nothing to say the timeline is draggable.
_Seen in `05-after-select.png`, `crop-trim-dim.png`._

**11. `.glass` does nothing visible on the transport button.** The play button
(`EditorView.swift:159`) reads as a plain dark rounded rectangle over the flat detail background —
closer to a disabled control than to the pane's primary transport. Whether Liquid Glass belongs on
content at all is
[Study what makes a macOS app read as premium](https://github.com/SamWongML/macos-audio-recording/issues/72)'s
finding (glass on chrome, never content); either way its current use buys nothing.
_Seen in `01-default.png`._

### Redundancy

**12. "Gain" is the label of two consecutive rows.** The Level section renders
`LabeledContent("Gain") { Text(signedDecibels) }` and then a `Slider` whose label is also `Gain`
(`ExportInspector.swift:206–216`), so the inspector reads "Gain … 0.0 dB / Gain −12 ▬ +12".

### Accessibility — found while sweeping, and each is a visual-truth bug too

**13. Every inspector value is exposed twice, and the outer copy is stale.** After a selection change
the accessibility tree carries both the old and the new number, outer-then-inner:
Correction `+5.3 dB` / `+1.4 dB`; Estimated size `≈ 0.359 MB` / `≈ 0.278 MB`; Length `0:11` / `0:08`.
The **pixels are correct** — the on-screen values updated — so this is not a visible staleness bug,
but VoiceOver would read the previous Recording's figures. The doubling tracks the `LabeledContent`
+ `Text` rows, and the stale outer value tracks `.contentTransition(.numericText())`.

**14. The timeline is invisible to accessibility.** The whole lane — waveform, playhead, both Trim
handles, Seam bands, loupe — exposes exactly two elements: `AXImage d=Compact Right Chevron` and
`AXImage d=Compact Left Chevron`. There is no element, label or value for the Trim, and no way to
read or set it without a mouse. `grep -n accessibility` finds **nothing** in `EditorView.swift`,
`TrimTimeline.swift`, `ExportInspector.swift` or `WaveformView.swift`.

**15. Reduce Transparency and Reduce Motion are honoured only in the panel.** `PanelView.swift:28–29`
reads both environment values and acts on them. The editor reads neither, while using
`.background(.bar)` (sidebar footer), `.regularMaterial` (loupe), `.glass`/`.glassProminent`
(transport, Export), and ungated `.animation(.default, …)` / `.easeOut` transitions. The map's Notes
state these constraints carry forward unchanged; today they do not.

### Empty states — certain from source, not yet photographed

**16. An empty Library shows a blank sidebar.** `EditorView.swift:48–56` has no empty branch: the
`List` simply renders nothing and only the footer's "0 Recordings" says anything.

**17. A search with no matches shows the same blank sidebar** — no `ContentUnavailableView.search(text:)`.

### Structural

**18. The blank band at the top of both panes.** Below the hidden toolbar background, the detail
pane's first ~50 pt hold only the floating title/subtitle, and the inspector's first ~50 pt hold
nothing at all before "Quality Preset". This is the blankness the map was chartered around; recorded
here so the before-picture states it rather than implies it.

## Not yet swept — needs the screen unlocked

Fixtures for the starred items are already in the Library and only need selecting.

- the loupe mid-drag (see the note below), playback in flight
- a Recording still capturing
- Export: idle, running, succeeded, failed
- ★ a Quality Preset that can't encode the file (the 96 kHz fixture; three rungs should dim and the
  reason line should appear)
- ★ a can't-open adopted file (the random-bytes `.mp3` fixture)
- an empty Library; a search with no results
- minimum width, wide; sidebar collapsed
- Light appearance; Reduce Transparency on; Reduce Motion on

**The loupe cannot be screenshotted under synthetic input.** macOS suppresses screen capture
system-wide while a synthetic drag is in flight — `screencapture` returns "could not create image
from rect" for a region, a black frame for the display, and "could not create image from window" for
a window id; ScreenCaptureKit from a helper binary and `screencapture -v` fail the same way. The
loupe exists only while a handle is held (`draggingHandle != nil`), so photographing it needs a
human's hand on the trackpad, or a temporary debug affordance that pins it open.

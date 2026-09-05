# The editor's visual bugs — the before-picture

Ticket: [Sweep the editor for visual bugs and capture the before-picture](https://github.com/SamWongML/macos-audio-recording/issues/73).
Map: [Map: a premium AppTape editor](https://github.com/SamWongML/macos-audio-recording/issues/70).

**Status: complete.** Every state the ticket asked for was reached except the loupe, which cannot be
photographed under synthetic input at all (see the end). Everything below is either **observed in a
screenshot**, **read off the running app's accessibility tree**, or **read off a main-thread
sample** — all first-hand. Two items are settled from source alone and say so.

The sweep ran in two sessions; the machine's screen locked between them, which is why the capture
notes below name two window sizes.

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

Library fixtures added for the sweep, **all since moved to the Trash**: a Recording carrying two
lane-drawn Seams and one sub-threshold Seam; a 96 kHz WAV (which no AAC rung can encode faithfully);
a `.wma` and a `.mid` of random bytes (can't-open adopted files, ADR-0015); and a one-minute capture
of QuickTime Player made to reach the still-capturing state. A `.mp3` of random bytes was tried
first and **did** open — AVAudioFile accepted it as a 22.05 kHz zero-length file — so it tests the
zero-length path, not the can't-open one.

A 3 MB disk image was mounted to force the Export failure, and unmounted afterwards.

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


## Findings from the second half of the sweep

The states below were reached after the screen was unlocked. Numbering continues.

### The editor freezes on a long Recording — and this caused three earlier "bugs"

**19. Selecting a long Recording hangs the whole editor, indefinitely.** Selecting the 20-minute
`Safari 2026-08-23 at 09.14.02` froze the window for **over fifteen minutes** — clicks ignored, the
playhead frozen, the inspector stuck on the *previous* Recording's numbers (Length `0:06` beside a
transport reading `Whole Recording · 20:00`, `≈ 0.202 MB` for what should be ~38 MB, and a `Gain
−4.6 dB` the file does not carry), and the accessibility tree gone entirely.

A main-thread sample (`assets/0003/main-thread-sample.txt`) shows **1005 of 1005 samples** on
`com.apple.main-thread` in:

```
LoudnessCorrectionModel.update(recording:normalize:)
  → LoudnessMeter.measure(url:startFrame:frameCount:isCancelled:onProgress:)
    → LoudnessAnalyzer.process / accumulatePeak
```

The cause is one missing keyword. `LoudnessCorrectionModel.update` deliberately dispatches with
`Task.detached(priority: .utility)` — but the target is set to
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`project.pbxproj:348`), and `LoudnessMeter` is a plain
unannotated `enum`, so `measure` is implicitly `@MainActor` and the detached task hops **straight
back to the main thread**. The whole BS.1770 pass then runs there. Marking `LoudnessMeter` (and
`LoudnessAnalyzer`) `nonisolated` is the fix; it belongs to
[Fix every visual bug the sweep filed](https://github.com/SamWongML/macos-audio-recording/issues/76),
not here.

**This is the root cause of three things this sweep first mis-read as separate bugs**, and finding
13 in the first half should be read in that light:

- the "inspector is stale after a selection change" — the inspector had not been redrawn because the
  main thread was blocked;
- the "accessibility tree collapses to nothing" — AX queries time out against a blocked main thread;
- the editor appearing to ignore clicks entirely.

_Caveat, stated plainly:_ this was a **Debug** build, and the sample shows the inner loop paying for
unspecialized generics (`IndexingIterator.next` → `_swift_getGenericMetadata`), which Release would
largely remove. The freeze would be shorter in Release. The structural defect — a whole-file
loudness measurement on the main actor, scaling with Recording length — is there either way, and
20-minute Recordings are ordinary for this app.
_Seen in `19-stale-recheck.png`._

### A Recording you just made is unusable until the app restarts

**20. Stopping a capture leaves the Recording at 0:00 with no waveform.** A one-minute capture of
QuickTime Player was made and stopped. Afterwards the editor showed `Whole Recording · 0:00`,
`Length 0:00`, `0:00` in the sidebar row, and a flat empty lane — while `afinfo` on the file
reported **60.05 s**. Reselecting it and waiting did not help. **Relaunching the app** showed the
same file correctly as `Whole Recording · 1:00`.

`Recording.frameCount` and `sampleRate` are `let`s read once in `Recording.init`, and
`LibraryStore.reconcile` deliberately keeps the *same object* for an unchanged path (so a live Trim
survives a refresh) — so the Recording adopted while it was still empty never re-reads its length.
The Recording just captured is the one the user most wants to open.
_Seen in `31-still-capturing.png` (during), `33-after-restart.png` (correct, after relaunch)._

**21. While capturing, the waveform is a solid blue slab.** The lane draws the zero-length envelope
as a filled rectangle spanning the full width rather than as no waveform at all, and it never grows.
The transport still offers Play on a Recording with no frames.
_Seen in `31-still-capturing.png`._

### The Export control does not fit, in three of its four phases

**22. Only the idle `Export…` button fits the window; the other three phases are cut off.** At the
**declared** default size (1120 × 640) the idle button clears the bottom edge by ~18 pt. But the
inspector has no fixed height, and each of these adds a row:

| what | effect on the Export control's position |
|---|---|
| a non-zero Gain (adds `Reset Gain`) | ~37 pt lower |
| Normalize loudness on (adds `Correction`) | ~37 pt lower |
| an unencodable preset (adds the reason block) | ~40 pt lower |
| the running phase (progress bar + `Cancel` row) | taller than the button |
| the succeeded phase (`Exported` + `Reveal in Finder` row) | taller than the button |

Photographed at 1120 × 640: **`Exporting… 9%` and `Cancel` are bisected by the window's bottom
edge**, and so are `Reveal in Finder` and `Done`. So a user who exports at the default window size
cannot see the progress, cancel, or reveal the file they just made.
_Seen in `13-defaultsize.png` (idle, fits), `15-export-done.png` (running, cut),
`16-export-success.png` (succeeded, cut)._

This supersedes the first half's framing of finding 3: the Export button is not merely off-screen at
one restored size — the inspector's height is variable and unbounded, and nothing pins the primary
action.

### Size estimates never switch to KB

**23. Short Trims show six-decimal megabytes.** `ExportSizeEstimate.sizeText` emits only MB or GB
(`ExportSizeEstimate.swift:33–46`), so the four rungs read `≈ 0.00432 MB`, `≈ 0.00171 MB`,
`≈ 0.000853 MB`, `≈ 0.000426 MB` on a zero-length Recording, and `≈ 0.0000561 MB` on a Recording
still capturing. Three significant figures is the stated intent; the unit never follows.
_Seen in `31-still-capturing.png`._

### The "permanently visible" inspector is not permanent

**24. The inspector disappears entirely for two ordinary selections** — a can't-open adopted file,
and no selection at all. Both branches render a bare `ContentUnavailableView` with no `.inspector`,
so the trailing column vanishes and the window's whole layout jumps as the user arrows down the
Library. The remaining void is ~900 × 750 around a small centred glyph.
_Seen in `11-cantopen-real.png`, `29-no-selection.png`._

### Preset rows wrap, and it is not just Compact

**25. Any preset subtitle wraps once the source is not 48 kHz.** At 22.05 kHz **all four** rungs
wrap (`24-bit ALAC · 22.1 / kHz stereo`); on a Recording still capturing, High and Standard wrap
too. The ladder the four rungs are meant to read as becomes four rows of different heights, always
breaking after `48` or `22.1` and orphaning `kHz stereo`.
_Seen in `31-still-capturing.png`, `12-unencodable.png`._

### At its minimum size, the window drops the Library

**26. At the minimum (418 × 400) the sidebar is gone and the transport is gutted.** The window
clamps to 418 pt wide, below the 232 pt sidebar minimum plus the 248 pt inspector minimum, and
SwiftUI resolves the shortfall by collapsing the sidebar without any indication. The detail pane is
squeezed to ~180 pt: the lane is a sliver where the Trim handles and playhead are wider than the
audio, and the transport's time read-out, `Trim …` text and `Reset` **silently disappear** rather
than truncate. The inspector keeps its full width throughout — it wins every space fight.
_Seen in `24-minwidth.png`._

### Light appearance changes what the picture means

**27. The lane loses its shape in Light appearance.** `.quaternary.opacity(0.35)` over a light
window is indistinguishable from the window itself, so the trough that reads as a distinct panel in
Dark simply is not there.

**28. The Seam hatch nearly vanishes in Light appearance**, where in Dark it reads as a bold grey
block. The same Recording tells the user something different in each appearance.

**29. The playhead outweighs the Trim handles in Light appearance** — `.primary` renders black
against grey `.secondary` handles, so the non-interactive decoration is the heaviest mark in the
lane. In Dark both are near-white and, as finding 10 records, hard to tell apart at all.
_Seen in `26-light-full.png`; compare `22-playing.png`._

**30. The playhead and the Trim handles are the same mark.** In `22-playing.png` the playhead at
0:02.50 and the Trim end handle are both plain white vertical lines of near-identical weight; only
the small dot on the playhead's cap separates them, and that dot sits outside the lane.

### Amber now means three different things

**31. The Export failure and the unencodable-preset warning both use `.orange`.** ADR-0009 already
spent the amber/colour-only accessibility trade on the Runway. Amber now marks the Runway, "this
preset can't encode this file", and "not enough space to export" — three unrelated meanings, one
hue, in an app whose stated palette discipline is that content carries the colour.
_Seen in `12-unencodable.png`, `30-export-failed.png`._

### Smaller things

**32. The window title and subtitle are identical for an adopted file.** `Recording.source` strips a
trailing date from the filename, so a hand-adopted file with no date and no `com.apptape.source`
xattr yields `source == name` and the title block reads the same string twice.
_Seen in `12-unencodable.png`._

**33. Two different files can present as identical sidebar rows.** The `.wma` and `.mid` fixtures
both rendered as `ZZ Fixture unplayable … Can't open` — the extension is not shown and nothing
disambiguates them.
_Seen in `11-cantopen-real.png`._

**34. A can't-open row crushes its timestamp to an ellipsis.** `layoutPriority(-1)` on the time
collapses it to `…` rather than dropping it, leaving a stray ellipsis between the name and
`Can't open`.
_Seen in `11-cantopen-real.png`._

**35. The sidebar footer count ignores the search.** With a query matching nothing the list is empty
and the footer still reads `44 Recordings`. It counts `store.recordings`, not the filtered set.
_Seen in `17-search-empty.png`._

**36. The waveform draws silence as a solid line.** The `max(v * scale, 0.5)` floor in both
`WaveformShape` and `WaveformPath` paints a continuous 1 px bar through genuine silence, so the gaps
between phrases read as a low-level signal that is not there.
_Seen in `30-export-failed.png` (the "Quiet talk" Recording)._

**37. `Export…` is not full width despite asking to be.** `.frame(maxWidth: .infinity)`
(`ExportInspector.swift:257`) has no effect inside the grouped `Form` row; the button hugs its label
and centres. Harmless, but the code's intent and the render disagree.
_Seen in `13-defaultsize.png`._

**38. Old Trims are silently ignored.** Two masters in the Library carry
`com.samwongml.apptape.trim`, while `RecordingMetadata.trimKey` is `com.apptape.trim`
(`RecordingMetadata.swift:18`). The 20-minute Safari master has a stored Trim of 416.06–663.48 s and
the editor shows `Whole Recording · 20:00`. This is almost certainly a stale namespace from an
earlier build on this machine rather than a shipping defect — recorded because it was observed, and
because a Trim that is silently dropped is the one failure ADR-0006 cannot tolerate.

## Confirmed states with nothing wrong to report

- **Export succeeded and failed** show the right content: `Exported` with a green check, and
  `Not enough space to export (needs about 5.41 MB, 2.96 MB free)` — an exact, actionable sentence.
- **The unencodable-preset treatment works**: the three AAC rungs dim, the sticky rung stays visibly
  selected, Export is blocked, and the reason is spelled out (`AAC can't encode above 48 kHz — this
  file is 96 kHz.`) with `Choose a quality that fits this file.` beneath it.
- **The can't-open state says the right thing** — `Can't open this file`, an accurate explanation,
  and a `Move to Trash` action.
- **Playback** updates the transport clock and the playhead correctly and loops the Trim.

## Two findings settled from source, not photographed

- **Findings 16 and 17** (empty Library and empty search have no `ContentUnavailableView`).
  Finding 17 is now also photographed — `17-search-empty.png` shows the blank sidebar. Finding 16
  could not be: reaching it means moving the user's Library aside, which was declined, and it is not
  worth risking 1.7 GB of their Recordings to photograph a blank list whose absence is plain in
  `EditorView.swift:48–56`.
- **Finding 15** (Reduce Transparency and Reduce Motion honoured only in `PanelView`).
  `com.apple.universalaccess` is TCC-protected and cannot be written from a script, and toggling it
  through System Settings would change the user's live accessibility configuration. The source is
  unambiguous: `accessibilityReduceTransparency` and `accessibilityReduceMotion` appear **only** in
  `PanelView.swift:28–29`, while the editor uses `.background(.bar)`, `.regularMaterial`, `.glass`,
  `.glassProminent` and ungated `.animation` throughout.

## The loupe cannot be photographed under synthetic input

macOS suppresses screen capture system-wide while a synthetic drag is in flight. Every route was
tried and all fail while the button is down: `screencapture -R` ("could not create image from
rect"), full-display `screencapture` (a black frame), `screencapture -l <windowID>` ("could not
create image from window"), `screencapture -v` video, and `SCScreenshotManager` from a helper
binary. The loupe exists only while a handle is held (`draggingHandle != nil`), so photographing it
needs a human's hand on the trackpad, or a temporary affordance that pins it open.

It was nonetheless exercised: dragging a Trim handle works, commits once at gesture end, and the
resulting Trim renders correctly (`03-trimmed.png`, `crop-trim-dim.png`).

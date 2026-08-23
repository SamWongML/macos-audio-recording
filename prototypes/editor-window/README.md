# PROTOTYPE — Editor window: waveform and trim (issue #7)

Throwaway. Four answers to "what is the editor window, and how does trimming feel", crossed
with three answers to "how do you land a Trim handle accurately". Not production code.

```sh
./run.sh   # builds, signs, launches. ⌘Q quits.
```

- **⌥← / ⌥→** switch the **variant** — M Document · N Library split · O Inspector · P Tape deck
- **⌥↑ / ⌥↓** switch the **precision treatment** independently — Whole · Zoom · Loupe
- In the timeline: **⌘= / ⌘−** zoom · **[** or **]** picks the In or Out handle · **← / →**
  nudges it (**⇧** for one second a step) · **space** plays
- The switcher's **Recording** popup jumps between fixtures without going through a variant's
  own Library

**First run writes ~575 MB of fixture Recordings into `~/Music/AppTape`** — real CAF masters
in ADR-0003's format (Float32, stereo, 48 kHz) and ADR-0006's naming, because there is no
capture path yet and every question here needs real audio to answer. Delete them with:

```sh
rm ~/Music/AppTape/{Safari,Spotify,QuickTime\ Player,Google\ Chrome}\ 2026-08-23*.caf
```

The four are chosen to be awkward rather than pretty:

| fixture | length | why it exists |
|---|---|---|
| **Safari** | 20:00 | Near-uniform speech with four short pauses. At full width one pixel is **1.2 seconds** and the pauses are invisible. This is the precision question. |
| **Google Chrome** | 3:00 | **Eight seconds of room tone before anyone speaks**, then talk, a music sting, talk. The classic "cut the head off", and the one case you can genuinely do by eye. |
| **Spotify** | 1:30 | Quiet intro, loud body, breakdown, loud outro. Wide dynamic range, so the envelope does real work. |
| **QuickTime Player** | 0:30 | A pure 440 Hz sine — a flat rectangle at every zoom. The degenerate case for "can you find your place in a waveform". |

## What is *not* being decided here

Every decision this map has already made is inherited, not revisited: the Library is a
folder ([ADR-0006](../../docs/adr/0006-the-library-is-a-folder.md)), the master is immutable
and Trim is two points against it ([ADR-0003](../../docs/adr/0003-immutable-lossless-caf-master.md)),
there are four Quality Presets with a live estimate ([#9](https://github.com/SamWongML/macos-audio-recording/issues/9)),
and the menu bar item is the transport ([ADR-0004](../../docs/adr/0004-nsstatusitem-not-menubarextra.md)).
The **Level** block is a deliberate stub — [#24](https://github.com/SamWongML/macos-audio-recording/issues/24)
and [#25](https://github.com/SamWongML/macos-audio-recording/issues/25) own it. It is drawn
only so the variants can be judged on whether they leave it somewhere sensible to land.

## Nine findings before any layout question

### 1. A twenty-minute master's waveform builds in 155 ms, so there is no peak cache

Audacity and Logic ship `.pk` sidecar files because scanning a master used to be slow. It is
not, here. Measured with `-O`, one file at a time, min/max/RMS per 256 frames over a mono
mixdown:

```
QuickTime Player   11.5 MB     30 s audio     6.8 ms   1698 MB/s
Spotify            34.6 MB     90 s audio    11.9 ms   2904 MB/s
Google Chrome      69.1 MB    180 s audio    32.6 ms   2118 MB/s
Safari            460.8 MB   1200 s audio   155.2 ms   2969 MB/s
```

**So the app needs no new on-disk artifact beside the CAF**, which keeps ADR-0006's "the
folder is the truth" clean — nothing to invalidate, nothing to garbage-collect, nothing to
explain to a user looking in `~/Music/AppTape`. The prototype builds every Recording's
envelope at launch, all four at once, and it is not noticeable.

Caveat, stated honestly: the page cache was warm (the fixtures had just been written) and
`purge` needs `sudo`, so this is a *warm* number. Cold it is read-bandwidth-bound — a few
hundred ms on an internal SSD, and seconds on a slow external drive, which is worth
remembering if a relocatable Library ever comes back into scope.

### 2. The same loop unoptimised is 125× slower — do not judge this from a Debug build

The identical scan run through `swift` without `-O`:

```
Safari  460.8 MB   1200 s audio   19452.0 ms   24 MB/s
```

**19.4 seconds instead of 155 ms.** A Debug build will make the waveform feel completely
broken and will make a peak cache look mandatory. It isn't; the optimiser is.

### 3. A `Canvas` renders nothing inside a `List` row on macOS 27

This is the most implementation-critical finding here, because [#4](https://github.com/SamWongML/macos-audio-recording/issues/4)
settled `AVAudioFile → downsample → Canvas` as *the* sanctioned waveform path, and variant N's
entire claim rests on a sparkline per sidebar row.

Ruled out one at a time: the envelope was fully loaded (a debug `onAppear` printed
`buckets=225000` for the row that drew nothing), the frame was laid out at exactly its
requested 46×20 (a red debug border proved the space was reserved), `.drawingGroup` was
removed, and the observable was moved onto the `Recording` element so each row observes what
it was handed. **None of it helped.** The identical view in a non-lazy `HStack` — variant P's
Library deck — drew fine the whole time.

Replacing the `Canvas` with a `Shape` producing the same `Path` fixed it immediately:

```swift
// draws nothing in a List row
WaveformShape(columns: …)                                 // Canvas
// draws
WaveformPath(columns: …).fill(.secondary.opacity(0.7))    // Shape
```

So: **`Canvas` for the big lane, `Shape` for anything inside a `List`.** Both are in
`Waveform.swift`, and they draw the same picture.

### 4. macOS 27 deprecated the non-throwing `AVAudioEngine` / `AVAudioPlayerNode` calls — and renamed them

Every "just do it" method now has an error-returning twin, and the Swift names are *not* the
obvious ones, so `try engine.connect(…)` does not compile:

| deprecated in 27 | replacement selector | Swift name |
|---|---|---|
| `connect(_:to:format:)` | `connect:to:format:error:` | **`connectNode(_:to:format:)`** |
| `connect(_:to:fromBus:toBus:format:)` | …`error:` | `connectNode(_:to:fromBus:toBus:format:)` |
| `play()` | `playAndReturnError:` | **`playAudio()`** |
| `play(at:)` | `playAtTime:error:` | `playAudio(at:)` |
| `installTap(onBus:bufferSize:format:block:)` | …`error:block` | — |

`scheduleSegment(_:startingFrame:frameCount:at:)` is **not** deprecated, and it is what makes
playing a Trim a one-liner.

### 5. There is still no range control, re-checked against the macOS 27 interface

`Slider` has exactly four live initialiser shapes and every one takes a single
`Binding<V>` plus a `ClosedRange` of *bounds*. No `RangeSlider` type exists. macOS 26/27
added `SliderTick`, `SliderTickBuilder` and `neutralValue`, which decorate one thumb — they
do not add a second. `Timeline.swift` is therefore the honest cost of the Trim selector:
hit-testing, handles, playhead, zoom, loupe and the keyboard path, all by hand.

### 6. ⌃← / ⌃→ / ⌃↑ / ⌃↓ belong to Mission Control and never reach the app

The first pass used them for the two switcher axes. The whole desktop slid sideways instead;
an app-local `NSEvent` monitor never sees them. Moved to ⌥.

### 7. `.onKeyPress` never fires on a custom timeline — every key had to move to an app-level monitor

Zoom and handle-nudging were originally `.onKeyPress` on the lane, with `.focusable()`. No
key ever arrived: a plain `.focusable()` custom view on macOS only joins the Tab loop under
Full Keyboard Access, and clicking a `Canvas` does not make it first responder. All keyboard
routes now live in one `NSEvent.addLocalMonitorForEvents` (`TimelineKeys`), which works
regardless of which window is key.

**This is a question for [#21](https://github.com/SamWongML/macos-audio-recording/issues/21),
not an answer.** An app-level key monitor is fine for a prototype; whether it is an
acceptable assistive story — VoiceOver cannot see a `Canvas` at all — is that ticket's call.

### 8. `translation == .zero` is not "the first event" of a drag

Grabbing a handle silently turned into a scrub, intermittently. The first `onChanged` of a
`DragGesture(minimumDistance: 0)` usually already carries a pixel or two of travel, so the
"is this the initial touch" test failed and the gesture fell through to seeking. Decide once
per drag from `value.startLocation` instead.

### 9. The loupe has to normalise to its own window, or it is a flat line where it matters

Drawn on the lane's absolute scale, the magnifier showed nothing at all in the quiet gap
between two phrases — which is exactly where an edit point is. It now rescales its ±2 s
window so its own loudest point fills the box. The main lane deliberately does **not** do
this: an absolute scale there is the only thing keeping the picture honest about level.

### And one confirmation: ADR-0006's extended attributes really do survive a Finder rename

Trimmed the 30-second fixture to 0:00–0:12, quit, renamed the file in Finder to
`Kettle noises.caf`, relaunched. The Trim came back intact and the Recording is now called
"Kettle noises" — [ADR-0006](../../docs/adr/0006-the-library-is-a-folder.md) working exactly
as written.

It also exposed a gap in it. The ADR says Source rides in an xattr, but nothing writes one,
so the prototype parses it out of the filename — and a rename that drops the date pattern
drops the Source with it, leaving "Kettle noises" as its own Source. **Capture must write
the Source xattr**, or a renamed Recording forgets where it came from.

## The four variants

| | The window is… | The Library is… | Export lives… | Play means… |
|---|---|---|---|---|
| **M** Document | one window **per Recording**, titled with its name, proxy icon and all | not in the app at all — Finder, plus ⌘O | the toolbar, with the estimate in a one-line footer | the whole Recording |
| **N** Library split | **one window, forever**; a sidebar selects the Recording | a sidebar list with a sparkline per row | the detail's toolbar | the whole Recording |
| **O** Inspector | waveform and nothing else, plus a **trailing inspector** | a toolbar popover | the inspector, permanently, above the reserved Level block | **the Trim only, looping** |
| **P** Tape deck | a **transport**: a 56-point playhead clock, Mark In / Mark Out | a horizontal deck along the bottom | the toolbar | from the playhead to the end |

Each disagrees with the others about something real:

- **M vs N** is *does the Library belong in the app at all?* M takes ADR-0006 at its word —
  the folder is the truth, so shipping a second Finder is duplication. Price: no way to
  compare two Recordings without two windows, and after a busy afternoon there are eight of
  them. (You can watch this happen: switch Recording while in M and a second window opens.)
- **O** is the only one that treats **Export as a panel rather than a button**, and the only
  one where all four preset sizes are visible at once — `≈ 212 MB / 39.2 MB / 19.6 MB /
  9.79 MB` side by side, where M and N's pop-up menu shows one at a time. It is also the only
  variant with somewhere obvious for #25's Loudness and Gain to land. Price: the widest
  window, and an inspector that is half empty until #25 ships.
- **P** is the only one that says **you find the edit by ear**. Its waveform handles are inert
  on purpose; Trim is set from the playhead with ⌘I / ⌘O. On the 20-minute Safari fixture
  that is arguably the only honest way to hit a word. On the Chrome fixture, where the eight
  seconds of silence is plainly *visible*, it is strictly worse than one drag.

## The three precision treatments

Independent of layout, so any variant can wear any of them (⌥↑ / ⌥↓).

- **Whole** — the Recording always fits the width. On Safari that is **1.2 s per pixel**: the
  four pauses built into the fixture are simply not visible. Nothing to learn, nothing to
  navigate, and no way to be accurate.
- **Zoom** — ⌘= / ⌘−, pinch, and scroll to pan, with an overview strip carrying a viewport
  rectangle. Six presses on Safari gets from 20 minutes to about 18 seconds and the syllable
  structure appears. Price: a mode, a navigation model, and **the Trim handles can end up
  off-screen with nothing saying which way they lie**.
- **Loupe** — still whole-width, but dragging a handle opens a ±2 s magnifier at raw sample
  detail, read straight off the master (no envelope). No mode, no navigation; it exists only
  while your finger is down. Price: it cannot help you *find* anything, only place a handle
  you have already got hold of. Tick **Pin the loupe open** in the switcher to judge it
  without holding a drag — pinned, it follows the playhead instead of the handle.

## What to watch while flipping

- **Trim the eight seconds of silence off the Chrome fixture.** It is visible, so this is the
  case that favours dragging. Do it in Whole, then Zoom, then Loupe, then do it in P by ear.
  That one task separates all four.
- **Now find the seven-second pause at 8:32 in Safari.** In Whole it is not on screen in any
  meaningful sense. This is the case that favours P — or Zoom.
- **In M, switch Recording from the switcher popup** and watch a second window open. Then
  decide whether that is a feature or the reason M loses.
- **In O, drag a handle and watch every preset's estimate move at once.** Then do the same in
  N, where the pop-up shows one number. Is seeing all four worth a permanent inspector?
- **In N, look at the sidebar sparklines.** They are the whole argument for N: four
  Recordings from the same afternoon, told apart at a glance. Are they enough?
- **In P, hit space and listen.** Then decide whether Mark In / Mark Out is a transport you
  would use or an editor you would fight.
- **Play in each variant and notice they disagree about what play means** — the switcher says
  which. O's looping-the-Trim is the one that previews the actual Export.
- **Watch M's toolbar at 820 points.** Play, clock, title, Reveal, preset and Export do not
  all fit; the title truncates to `QuickTime Player 2026…`. M's claim is minimalism, and its
  toolbar is the most crowded of the four.
- **Reduce Transparency and Reduce Motion.** The loupe is a `.regularMaterial` popover and the
  numeric readouts use `.contentTransition(.numericText())`.

## Deliberately left out

- **What Export does while it runs** — [#27](https://github.com/SamWongML/macos-audio-recording/issues/27).
  The button logs a line and stops.
- **Loudness and Gain** — [#24](https://github.com/SamWongML/macos-audio-recording/issues/24)
  / [#25](https://github.com/SamWongML/macos-audio-recording/issues/25). Drawn as an inert
  stub in O only, to prove there is room for it.
- **A degraded Recording** — [#18](https://github.com/SamWongML/macos-audio-recording/issues/18).
  Every fixture here is clean; none shows a dropout marker.
- **Adopted-file limits** — [#30](https://github.com/SamWongML/macos-audio-recording/issues/30).
  The prototype adopts anything `AVAudioFile` opens, with no guard rails at all.
- **Undo.** Trim is written to the xattr on every change with no undo stack, which is almost
  certainly wrong for a real editor and is not a question this ticket asked.

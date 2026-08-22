# PROTOTYPE — Source picker (issue #6)

Throwaway. Three variants of the Source picker on a real `MenuBarExtra`, switchable from
the bar at the bottom of the panel or the ← / → keys. Not production code.

```sh
./run.sh   # builds, signs ad-hoc, launches; waveform icon in the menu bar. ⌘Q quits.
```

The `▤` button in the switcher bar opens the raw Core Audio process table — the evidence
the design is reacting to, not part of any variant.

## The finding that shaped all three variants

Dumping `kAudioHardwarePropertyProcessObjectList` live on this machine returned **28
entries**, and they are not apps. `PerfPowerServices`, `systemstats`, `mediaremoted`,
`audiomxd`, `corespeechd`, `assistantd`, `callservicesd`, `systemsoundserverd` — daemons
with no window, no icon, and mostly no name. A picker fed from this list directly is
unusable.

Worse, the one process actually producing audio was:

```
118  pid 6424  out=Y  com.google.Chrome.helper  | (no NSRunningApplication)  | Google Chrome Helper
114  pid 1976  out=.  com.google.Chrome         | Google Chrome [regular]    | Google Chrome
```

The HAL client pushing audio is a **helper with no `NSRunningApplication`** — no icon, no
localized name — while the process the user would call "Chrome" is silent. Two entries
share `com.google.Chrome.helper`; only one of them is playing. This is the helper-process
problem from [the capture-API research](../../docs/research/capture-api.md) confirmed
empirically, and it settles one thing before any layout question: **the picker is built
from `NSWorkspace.runningApplications` filtered to `.regular`, and audio processes are
mapped *up* to those apps — never the other way round.** `AudioSources.swift` does that
mapping in `owningBundleID(of:among:)`.

It also matters for `CATapDescription.bundleIDs`: tapping `"com.google.Chrome"` would
attach to nothing. The tap needs the helper's bundle ID, or a prefix rule.

**WebKit breaks the prefix rule.** Safari's audio runs through `com.apple.WebKit.GPU`,
which is shared — the same bundle ID appeared three times, owned by Safari, Xcode, and a
thumbnail extension. Only `NSRunningApplication.localizedName` ("Safari Graphics and
Media") reveals who it belongs to. The prototype special-cases it; whether that heuristic
is good enough for the spec is a real open question, and it is worth watching Safari in
the ▤ table before choosing a variant.

## The variants

| | Structure | Primary affordance | Bet |
|---|---|---|---|
| **A** Picker row | Compact form: one labelled `Picker`, then Record | The Record button | The Source is a setting you touch rarely; stock components, smallest surface |
| **B** List is the panel | The panel *is* the app list, playing-first | The row | Choosing a Source and starting a Recording are one gesture; no separate picker exists |
| **C** Hero + drill-down | Remembered Source shown large; "Change" replaces the panel with a searchable, sectioned list | The Record button, with changing as a deliberate second mode | The Source is remembered and re-recorded from constantly, so it earns the panel |

## What to watch while flipping

- Play something in Chrome, then Safari, and watch whether the "playing" state is a
  signal worth designing around, or noise. **B leans on it hardest** — it defaults to
  showing only apps producing audio, so if the signal is flaky, B is the first casualty.
- Does an app-that-is-running-but-silent need to be pickable at all? A and C say yes, B
  says only via a toggle.
- With the ▤ table open: do any apps show "no audio process"? Those are apps a tap by
  bundle ID would find nothing to attach to.

## Variants D–G (second round)

B was chosen as the baseline, with two objections: its `All` toggle did nothing when
nothing was playing (it silently widened the list while the header still read "Playing
Audio" — fixed, it now shows an explicit empty state), and it never committed to a Record
affordance.

| | Structure | Record affordance |
|---|---|---|
| **D** List + record dock | Two zones: list picks, a permanent dock underneath records | Full-width prominent button, docked |
| **E** Row expands to record | One zone: the selected row grows to reveal Record inside itself | Prominent button, inside the row |
| **F** Waveform rows | Playing rows are painted by their own **real** amplitude | Small trailing `record.circle` glyph |
| **G** Variable symbol + hover | Quiet rows, **no taps at all**; `speaker.wave.3` two-state | Glyph swaps to a Record button on hover |
| **H** Row is the record control | Real waveform, inset around a reserved trailing lane | The row itself — no button chrome |

**G vs. H is the real decision, and it is a product choice, not a style choice.** G is what
the picker can show *for free*: `kAudioProcessPropertyIsRunningOutput` is a boolean that
costs no permission, so G shows silent-or-sounding and nothing more. H spends the System
Audio Recording grant to show true amplitude. The waveform research's sharpest caution is
to **never open a tap per row just to populate a list**, because that surfaces the
permission prompt before the person has asked to record anything.

H also carries the record-affordance research's top recommendation: the row *is* the
control. No button chrome, no coloured capsule — a `circle` glyph that becomes a pulsing
`record.circle.fill`, kept legible over the moving waveform by **layout** (a trailing lane
the waveform is inset around) plus a `.thinMaterial` puck, not by z-order. The rejected
blue capsule reads as a *size* violation rather than a colour one: "Use style — not size —
to visually distinguish the preferred choice among multiple options" (HIG, Buttons: Style).
The keyboard path is a plain `.bordered` button with `.keyboardShortcut(.defaultAction)`,
which the system colours itself.

**F and G deliberately disagree**, and that is the point of having both. F answers the
brief as asked — real amplitude waves as the row background. G is what
[`docs/research/waveform-in-list-rows.md`](https://github.com/SamWongML/macos-audio-recording/blob/research/waveform-rows/docs/research/waveform-in-list-rows.md)
recommends instead: `Image(systemName:variableValue:)` redrawn a few times a second, with
**no perpetual animation in the list at all**, because Apple's Motion guidance argues
against continuous motion on frequently-recurring UI and its frame-rate guidance puts a
level readout in an 8–24 Hz tier. Look at both before deciding.

### Real amplitude, and what it costs

F and G both install a **real Core Audio process tap per playing app**. Verified: Chrome
and QuickTime tapped simultaneously stayed correctly isolated — Chrome varied 0.57–0.75 on
real content while QuickTime held a constant 0.3662 on a pure 440 Hz sine.

Two traps found in the process, both worth carrying into the spec:

- **An ungranted tap returns silence with `AudioDeviceStart` reporting `noErr`.** No error,
  just zeros. Combined with there being no API to query the grant (issue #3), the app can
  only *guess* the permission state — the `looksUnpermitted` heuristic here (taps running
  several seconds, every sample zero) is indistinguishable from genuinely silent playback.
- **TCC attribution follows the responsible process.** The same signed bundle read all-zero
  when launched straight from a terminal, and real audio when launched via `open`. Test
  through LaunchServices or you will chase a phantom bug.

This means F and G take the System Audio Recording grant **just to draw the picker**,
before the user has asked to record anything. That is a product decision, not an
implementation detail, and it probably belongs to issue #14 (first-run permission flow).

## The waveform froze, and why

The first version of the waveform read its samples out of `LevelRing` inside a
`TimelineView(.animation)`. It looked right in code and was wrong in practice: the
waveform only advanced when something *else* in the UI changed.

Instrumented with `--args diag`, which prints per-second counts of every redraw source:

```
DIAG canvasDraw=4/s  sampler=6/s  timelineTick=28/s     <- first second
DIAG                 sampler=12/s timelineTick=48/s     <- canvas stopped drawing entirely
```

The timeline was ticking 48 times a second. The `Canvas` drew four times, then never
again. The reason is that **the ring is mutated by the realtime audio thread, which SwiftUI
cannot observe**: the `Canvas` closure read the ring but nothing in its *inputs* ever
changed, so SwiftUI correctly concluded there was nothing to redraw. A `TimelineView` that
discards its context (`{ _ in ... }`) does not by itself make the subtree's inputs change.

The fix is to stop treating the waveform as animation and treat it as data:
`LevelMonitor.waveforms` publishes a downsampled `[Float]` per Source at 20 Hz, and
`WaveformBackground` takes that array as a plain stored property. The view's input now
genuinely changes on every sample, so the redraw is guaranteed rather than hoped for.

After, in steady state:

```
DIAG canvasDraw=20/s sampler=20/s
DIAG canvasDraw=20/s sampler=20/s
DIAG canvasDraw=20/s sampler=20/s
```

Locked 1:1 with the sampler, with no `TimelineView` involved. This also lands where the
waveform research pointed: drive the indicator from the audio callback a few times a
second, not from a display-linked animation loop.

## Smoothing the trace

Three changes, in order of how much each mattered:

1. **A longer, deterministic window.** The trace is no longer downsampled out of the audio
   ring — the sampler appends one point per tick, so the window is exactly
   `traceLength / 20Hz` = **7 seconds**, and it scrolls one point per frame. Deriving the
   window from the sampler rather than from the ring also makes it *predictable*: the
   IOProc's callback rate follows the device's buffer size, so a window measured in ring
   entries scrolled at whatever speed the hardware happened to pick.
2. **An attack/release envelope** (`follow`) instead of raw bucket peaks — fast rise so
   transients survive, slow fall so the trace stops jittering. Verified against a burst
   tone: the level snaps to full on each burst and decays 0.070 → 0.005 → 0.000 through
   the silence.
3. **Quadratic path segments** through the midpoints instead of a polyline, which is what
   makes it read as a waveform rather than a chart.

The `.animation(value: samples)` modifier was removed: animating the array does not
interpolate the drawn path, so it only implied a smoothing that was never happening.

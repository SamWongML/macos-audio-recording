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

---
status: accepted
---

# 0051. The recording strip floats above the editor, and each surface answers its own presses

The main window records through a compact strip inset at the top of the whole detail area — over
the waveform and the Export column alike, and in every detail state including the empty Library —
so capture reads as the window's, never the selected Recording's. Both surfaces command the one
`RecordingController`, which remembers a single Source for them, and every Record and Stop carries
the surface it was pressed on, so a saved Recording or a refusal is answered where the user asked.

## Consequences

**The strip is Liquid Glass, in the controls layer only.** One glass bar holds the Source menu and
the status; beside it a red, prominent glass button is Record at rest and Stop while capturing, both
in one `GlassEffectContainer`. That adds two controls to [ADR-0019](0019-content-colour-palette.md)'s
two, as Apple's Materials guidance allows for a floating functional layer; nothing in the content
layer — the lane, the brief, the Library rows — takes glass. Red belongs to live capture, so the
transport's neutral play button can never be mistaken for it, and every state also has words and a
shape: a hollow ring for waiting, a filled dot for recording, a square for Stop.

**Waiting for audio is said, and the clock waits with it.** [ADR-0016](0016-recording-starts-at-first-sound.md)
left the menu bar's frozen `00:00` as the only waiting signal. In the window the strip says *Waiting for
audio* and shows no clock until the first sound creates the master; from then on it shows the master's
length and the live level. Only changes of state are announced to VoiceOver, never the clock.

**Choosing a Source is not recording one.** The Source menu only remembers a choice, persisted
across launches. Record looks the remembered bundle identifier up among the apps running at that
moment, so a relaunched app's new processes are the ones tapped; an app that is not running, or has
opened no audio yet, is named with its recovery and never replaced by another. The Source cannot
change while capturing. The helper's row stays a choice and a press at once until the helper's own
redesign, and it remembers what it starts, so the strip names the Source the helper is recording.

**Stop is presented by the surface that pressed it.** `CaptureRun` reports a saved Recording with
the stopping surface and `EditorPresenter` routes it: Stop in the window selects the Recording where
the user already is, without activating the app or revealing a window; Stop in the helper still opens
the editor on it, unchanged until the helper's redesign. A run that ended before any sound reports
nothing, so nothing is selected.

**A refused press is explained where it was made.** The strip shows the disk-floor refusal and an
inferred denial with their one recovery action, and pressing Record again is still the retry. The
helper's panel raises itself for a refusal only when the helper made the press. What stops the
remembered Source being recorded — nothing chosen, not running, no audio yet — outranks a refusal
left over from an earlier press, because that is what disables Record now.

**⌘R presses the strip's Record or Stop.** Application-menu routes for capture, playback and Export
belong to the keyboard and VoiceOver work, not to this strip.

**AppTape is not its own Source.** As a regular app since [ADR-0050](0050-dock-first-app.md) it had
started listing itself among the running apps; recording its own playback is never what a Source means.

## Not yet verified on the target system

The strip is a new top safe-area inset in the split view that once aborted on safe-area bars while it
hosted `.inspector` ([ADR-0023](0023-detail-pane-layout.md), [ADR-0024](0024-trailing-column-not-inspector.md)).
That modifier is gone, and the Export column's own bottom bar has run since, but the inset, the
glass, the Source menu's icons and subtitles, and the strip at the minimum window width with a long
Source name still need checking on macOS 27 with a real capture, in both appearances and with Reduce
Transparency, Increase Contrast and Reduce Motion.

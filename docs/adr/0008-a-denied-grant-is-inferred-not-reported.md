---
status: accepted
---

# A denied grant is inferred from silence, never reported

macOS never tells the app it lacks the System Audio Recording permission. Measured on macOS 27:
a denied `AudioDeviceStart` returns **`noErr` in 0.000 s**, installs the IOProc, and calls it at
the normal ~94 Hz **forever, with every sample exactly zero** — byte-identical to a Source that
happens to be quiet. `kAudioDevicePermissionsError` exists in `AudioHardwareBase.h` and never
appears. So the app **infers** the denial: a Recording whose every buffer has been exactly zero
**since its first sample**, for 3 seconds, while the Source reports
`kAudioProcessPropertyIsRunningOutput`, is treated as ungranted — the Recording ends, its
all-zero file is removed outright, and the panel offers a deep link to System Settings.

## Considered options

**Branching on `kAudioDevicePermissionsError`** is what the ticket assumed and what the API
appears to offer. It is dead code: the probe on
[`prototype/permission-flow`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/permission-flow/prototypes/permission-flow)
never once saw it, in any state. It is worth keeping as a guard, but nothing may depend on it.

**Testing the grant at launch**, before the user asks for anything, was rejected on two counts.
It puts the prompt in front of a user who has done nothing to invite it, and the only honest
test costs a real capture — a tap on the app's **own** audio is not TCC-gated at all (measured:
peak 0.1000 with no grant, no prompt, and `tccd` never consulted), so the app cannot quietly
self-test. The grant is therefore taken at the **first press of record**, where the prompt's
sentence lands one gesture after the user asked for exactly that.

**Persisting the permission state** in `UserDefaults` was rejected because every stored value
can go stale in a way the app cannot see — the user flips the toggle in System Settings, runs
`tccutil reset`, or restores the machine. A stale "denied" is the dangerous one: it would
suppress an attempt that would now succeed. Re-attempting costs 17 ms on the granted path, so
there is nothing to save. Nothing about permission is stored.

## Consequences

**A tap is permission-checked at creation and never again.** Flipping the toggle in System
Settings leaves a *running* tap all-zero indefinitely — measured at 38 seconds and ~3300
further callbacks after the grant landed. A tap built afterwards, in the same process, recovers
within a second, and macOS neither terminates the app nor offers "Quit & Reopen". So recovery
costs a **tap rebuild but not a relaunch**, and the recovery message ends with *press record
again*. This also confirms on measurement what
[ADR-0007](0007-mid-recording-faults-are-seams-not-stops.md) decided by reasoning: a revocation
*during* a Recording is invisible until something rebuilds the tap, so it needs no special case.

**Starting a Recording can block for 90 seconds, across two calls.** With the prompt on screen
and unanswered, `AudioDeviceCreateIOProcIDWithBlock` blocked **60.007 s** — before
`AudioDeviceStart` was reached — and `AudioDeviceStart` then blocked a further **30.005 s**,
delivering **no callbacks at all**. Any timeout must wrap the whole bring-up rather than the
start call, and there is none on the first Recording, because a shorter one would abort a
Recording while the user is still reading the prompt. After a single successful capture the
prompt cannot appear, so a slow bring-up is a wedge and the timeout is 10 seconds. That flag is
a fact about *capture*, not about permission, so it does not reopen the no-stored-state rule.

**Zero callbacks and zero-valued callbacks are different observations.** Three states are
distinguishable: granted (instant `noErr`, ~94 callbacks/s, real audio), denied (instant
`noErr`, ~94 callbacks/s, all zero) and prompt-unanswered (`noErr` after 30 s, no callbacks).

**The inference is narrow on purpose, and hands off cleanly.** The clause that makes it safe is
*since its first sample*: a Source that falls silent mid-Recording has already delivered audio,
so it can never trigger this. That leaves the mid-Recording all-zero case entirely to
[issue #18](https://github.com/SamWongML/macos-audio-recording/issues/18), whose threshold is a
different number for a different situation. It also keeps the inference clear of
[issue #33](https://github.com/SamWongML/macos-audio-recording/issues/33): the IOProc is not
called at all while nothing is playing, and `isRunningOutput` tracks actual output rather than
an open pipeline, so a Recording started against a paused Source produces no callbacks to judge.

**Removing the file is the one deletion the app performs without asking.** A Recording that
never held a non-zero sample is not a Recording, and
[ADR-0006](0006-the-library-is-a-folder.md) makes the folder the truth with no index to mark a
file bad. It is `removeItem`, not `trashItem`: putting a file of pure silence in the Trash asks
the user a question about something they never made.

**The recovery pane is misleadingly titled.** The deep link
`x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture` works, but opens
a window titled **"Screen & System Audio Recording"** — the audio-only section sits inside it.
An app that promises it never wants screen access must name **"System Audio Recording Only"**
in its own copy so the pane's heading does not read as a contradiction.

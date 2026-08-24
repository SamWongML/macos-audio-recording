---
status: accepted
---

# Mid-Recording faults are padded seams, not stops

The world changes underneath a Recording: the Source quits and relaunches, the output device
changes, the tap degrades to all-zero buffers. The policy is that **capture recovers in place and
the master stays wall-clock true** — a fault is destroy-and-recreate the tap and aggregate, with the
missing stretch **padded with silence**, not elided. **A Recording ends for exactly six reasons**,
and no fault is one of them until recovery is exhausted.

## Considered options

**Auto-stopping when the Source quits** was the obvious alternative and is wrong. A stop is
irreversible — there is no multi-clip assembly to rejoin two files, so a Recording ended in error is
unrecoverable, while a Recording that kept running through a Source's absence costs disk and is
Trimmed away for free. The spike also established that a Source which quits and relaunches is picked
up again within about a second by `processRestoreEnabled`, so auto-stopping would discard the
recovery the OS performs for us.

**Eliding the gap** rather than padding it was rejected because Trim points are stored against the
master. A master whose timeline silently compresses at each fault shifts every Trim set after it,
which is the one thing a non-destructive editor cannot afford.

**Resampling a rebuilt tap onto the master's format** was rejected for the reason ADR-0003 kept
converters off the capture path and issue #9 kept them off the Export path: it would be the app's
only resampler, running on its most timing-sensitive thread, to rescue a rare case that ending the
Recording handles honestly.

## Consequences

**The six ends.** A Recording ends when the **user stops it**; when the **disk guard** fires
(issue #17); when **rebuilding is exhausted** (three attempts); when a **rebuilt tap's format does
not match the master's ASBD**; on **system sleep**; and on **app quit or logout**. Fast user
switching is folded into the sleep rule. Everything else is a seam to pad or an event to ignore.
Sleep and fast user switching are on the list precisely because their gap is *unbounded* — padding
an overnight sleep would write about 12 GB of zeros — so the rule is that a gap the app cannot
account for as a rebuild seam is not padded, it is the end of the Recording. Waking does not start
a new one: a Recording begins by user gesture, always.

**Restore gets first refusal over rebuild.** ADR-0001 records that a restored process reports
`kAudioProcessPropertyIsRunningOutput` a beat before its audio reaches the tap, so an eager rebuild
would tear down a tap the OS was about to fix, converting a free recovery into a seam. The rebuild
trigger is therefore defined as strictly slower than restore; the threshold itself belongs to the
detector in issue #18.

**A rebuild re-resolves the Source's processes.** Taps are aimed by process object ID at the start
of a Recording and are *not* re-aimed while healthy — a Source that spawns a new audio-producing
helper mid-Recording is missed, an accepted risk given each browser routes every tab through one
audio service process. But a rebuild is a new tap, and the object IDs held from the start are dead
if the Source relaunched, so re-resolution happens there, where the seam is already being paid.

**Seam length comes from host time, not sample counts.** A rebuilt tap's sample timeline restarts at
zero and cannot span the gap. The pad is computed from the `AudioTimeStamp` host-time delta across
the fault, converted to frames at the master's fixed rate — the same clock the frames are stamped
with, so the silence lands where the missing audio would have.

**Revoked permission is not a special case.** There is no API to query `kTCCServiceAudioCapture`
(issue #3), so a revoked grant and a dead tap are the same observation from inside the app: frames
arriving, all zero. It is handled as the generic no-audio case, and the question dissolves.

**The aggregate should name no output device.** The spike built its aggregate with
`kAudioAggregateDeviceMainSubDeviceKey` set to the current default output device's UID — the
aggregate's *time source* per `AudioHardware.h:1584` — which makes losing that device a fault to
recover from. A tap-only aggregate makes output device changes structurally a non-event instead, and
the spike's own composition hints it already works, since its sub-device list was empty and the named
master was not a member of it. That hint is not proof; issue #34 verifies it, and the fallback if it
fails is to listen on `kAudioHardwarePropertyDefaultOutputDevice` and rebuild on change, which this
ADR's seam machinery already covers.

**Detection is not settled here.** This ADR fixes the policy and the complete list of events that
must be detected; how each is detected, how fast, what the user sees at the moment it happens, and
whether an affected Recording is marked degraded once saved all belong to issue #18.

Settled in issue #13.

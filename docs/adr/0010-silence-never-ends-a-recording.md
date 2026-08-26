---
status: accepted
---

# Silence never ends a Recording, and every gap is a Seam

ADR-0007 fixed the policy for a mid-Recording fault and left detection open. Detection turns on one
fact: **a tap that has died and a Source that has gone quiet are the same observation** — callbacks
arriving at the full rate with every sample zero, with `kAudioProcessPropertyIsRunningOutput` true in
both cases. So faults are split in two. A **hard fault** is unambiguous — a Core Audio error, a
callback famine, a format mismatch — and spends one of ADR-0007's three attempts. A **soft fault** is
all-zero-while-running, is ambiguous with real silence, gets **one** rebuild, and **never counts
toward exhaustion and never ends a Recording**. Separately, the writer thread pads *any* unaccounted
host-time gap, so a dropped buffer and a rebuilt tap both land as a **Seam** and the master is
wall-clock true by construction rather than by remembering to handle each fault.

## Considered options

**Handling every fault uniformly** is what a plain reading of ADR-0007 suggests, and it is a trap.
Silence trips the detector, the rebuild constructs a perfectly good tap, the audio is still zero
because there *is* no audio, and the detector trips again. If each pass spends an attempt, a
thirty-second pause in a podcast destroys the Recording — the worst outcome this design can produce,
reached from the most ordinary input it will ever see. The split exists to make that structurally
impossible rather than merely unlikely.

**A stronger discriminator than time** was looked for and does not exist. ADR-0008 established that
`kAudioDevicePermissionsError` never appears in any state, so there is no error to branch on;
`isRunningOutput` is true for a paused tab and a dead tap alike; and the tap is the app's only
observation of the Source's audio, so there is nothing to cross-check it against. Time is the only
axis left, which is why the threshold below is a judgement and not a measurement.

**Letting an overrun elide** is the literal reading of ADR-0003, which has the realtime IOProc drop
the buffer and increment a counter. The IOProc's half of that stands — it may not block. But a
dropped buffer removes 10.67 ms from the timeline and shifts every later sample earlier, which is
precisely what ADR-0007 rejected eliding *for*: Trim points are stored against the master, so a
master that silently compresses moves every Trim set after the gap. "Inaudible" is the wrong axis;
the damage is silent, cumulative, and to the wrong thing. **ADR-0003's consequence is corrected
here: the IOProc still drops, the file no longer elides.**

**A boolean `degraded` flag** was the cheap mark and answers none of the questions asked of it. It
cannot draw the waveform, and it cannot tell 8 ms of overrun from 40 s of dead tap — the two things
the mark most needs to distinguish. The Seam list costs nothing extra, because the writer already
computes every pad.

**A timeout on bring-up** cannot be written. ADR-0008 measured 60 + 30 s of legitimate blocking
across `AudioDeviceCreateIOProcIDWithBlock` and `AudioDeviceStart` while a human read a TCC prompt,
and the human is the variable there — it could as easily be five minutes. Issue #11 saw
`AudioDeviceStart` hang *indefinitely* with no prompt after a previous instance was `SIGKILL`ed
holding a tap. Any wall-clock number either murders a slow but legitimate grant or leaves the wedge
unbounded, so the answer is a cancel gesture instead of a number.

## Consequences

**The soft threshold is 10 seconds of continuous all-zero while `isRunningOutput` is continuously
true**, the window resetting on any momentary drop. Ten times the ~1 s restore window, so it can
never race the `processRestoreEnabled` recovery ADR-0007 gives first refusal; longer than
essentially all in-content dead air, so a podcast's pauses do not manufacture Seams. It is
deliberately tuned for the false positive rather than the false negative, because the number barely
matters for a genuinely dead tap — one rebuild either fixes it or the rest of the Recording is
silence regardless. What it does cost is real: it is the audio lost to the one *measured* cause,
mid-Recording revocation, which ADR-0008 clocked sitting dead for 38 s until a rebuild in the same
process recovered it in one second. The soft detector is a **one-shot per audio epoch** — after its
single rebuild it disarms, and re-arms only on the next non-zero sample.

**Hard faults: a 500 ms callback famine, armed at the first callback, and attempts at 1 s / 2 s /
4 s.** 512 frames at 48 kHz is a callback every 10.67 ms, so 500 ms is ~47 missed in a row and no
healthy tap does that under any load. Arming at the *first callback* rather than at start is not a
detail: ADR-0008 measured the TCC prompt blocking inside `AudioDeviceCreateIOProcIDWithBlock`
delivering no callbacks at all, and a famine detector armed at start reads the first-run prompt as a
fault. The doubling spacing keeps restore's first refusal on this path too and puts the end about
7 s after an unrecoverable fault. A **format mismatch is not a retry** — ADR-0007 lists it among the
six ends, so it ends the Recording at once rather than spending attempts.

**A gap beyond 30 seconds is not padded; it ends the Recording.** This is the price of the unified
reconciler: a writer that pads whatever it cannot account for would, on wake, see a multi-hour
host-time delta and write the ~12 GB of zeros ADR-0007 named when it put sleep among the six ends.
Thirty seconds is roughly 3x the worst legitimate Seam, which is now computable — the soft path is
10 s of detection plus ~1 s to rebuild. **It is not a seventh end**: it is the sleep end arriving by
another route, exactly as ADR-0009 framed ENOSPC as the disk guard firing late, and it is the
backstop for every gap nobody modelled. The reconciler trusts `mHostTime` only when the timestamp
carries `kAudioTimeStampHostTimeValid`, and otherwise assumes contiguity — a 10 ms slip beats a
guess. The writer sees only that there was a gap; the **cause** comes from the capture controller
knowing whether a rebuild was in flight.

**Bring-up is cancellable rather than timed.** It runs off the main thread, the row shows in-flight
from about 500 ms using the pulsing `record.circle.fill` issue #6 already specified, and **a second
click abandons the attempt**: the UI returns to idle and whatever the blocked call eventually
returns is torn down, since the call itself cannot be interrupted. The same gesture that started it
stops it, so nothing new is learned. Nothing is lost by abandoning, because ADR-0006 creates the CAF
at the *first sample* — a bring-up that never produced one leaves no file. After about 10 s the
panel carries a plain "still starting" line on ADR-0009's blocking-message surface (issue #22 owns
how that looks), worded without claiming to know it is permission, because it does not. This matters
beyond the bench: the app crashing while holding a tap is exactly the crash ADR-0003 covers, and
without a way out the next Recording would hang with none.

**Sleep, fast user switching and quit are detected on notification and produce no Seam.**
`NSWorkspace.willSleepNotification` and `sessionDidResignActiveNotification` for the first two,
`applicationWillTerminate` plus `NSWorkspace.willPowerOffNotification` for the third. All three end
the Recording *on* the notification rather than on wake, so the file is finalized while the machine
is still awake and there is no gap to reconcile — which keeps the 30 s ceiling above a backstop
instead of a load-bearing path. None of them seams: they end the Recording, so there is no audio
after the gap and the master simply ends at its last real sample. Quit stops and saves unwarned, as
ADR-0004 already accepts for a left-click.

**A recovered Seam tells the user nothing at the moment.** Recovery is the whole point of ADR-0007;
a sub-second gap the app already handled is not news and offers no action, and a third menu bar
state would re-buy the accessibility trade ADR-0009 took consciously once. An honest live signal
already exists for free: the picker row's level meter reads zero for exactly as long as the tap is
dead. The telling for a Seam belongs to the file, not to the moment.

**All four unrequested ends share ADR-0009's notification channel, and each names its reason.** The
six ends split into *you asked for it* — user stop, app quit or logout — and *you didn't*: the disk
guard, rebuilding exhausted, format mismatch, sleep. ADR-0007's requirement that exhaustion be loud
therefore costs nothing new. The reason is named because the four ask different things of the user
(free up space, nothing, nothing, start again) and a generic "Recording stopped" makes them open the
app to find out which. ADR-0009's rule that a notification is never retracted holds: each of these
is terminal. **When authorization is absent, the editor window opens on that Recording instead,
without activating the app.** ADR-0009's refusal to open a window was aimed at a *predictable* stop
that had already warned twice; an unwarned stop with no other channel is the case it was not arguing
about. Note that this covers the very first Recording, where authorization is `NotDetermined`
because ADR-0009 takes it at the end of the first *completed* one — and a fault-stopped Recording
does not trigger that request, since stacking a permission prompt onto a failure is the mistake
ADR-0009 avoided by keeping it off the audio grant.

**A Recording is marked, the mark is the Seam list, and it describes the master.** One extended
attribute alongside ADR-0006's Trim, Gain and Source: `com.samwongml.apptape.seams`, a JSON array of
`{start, frames, cause}` with `start` and `frames` in master frames — integers, so there is no `NaN`
to reach the file as issue #7 found one doing — and `cause` one of exactly **`overrun`** or
**`rebuild`**. Two values, not more, because every other event either ends the Recording or does not
seam. An unreadable or absent value reads as a clean Recording, which is the safe direction and the
same graceful degradation ADR-0006 gives the others. The mark describes the master and **not the
Trim**: ADR-0003 makes the master immutable and Trim a view over it, so a badge that vanished when a
handle was dragged would read as the app having repaired something.

**Every Seam is recorded; only Seams a listener would notice are surfaced.** The threshold is a
single Seam of **250 ms or a total of 250 ms**, which sits cleanly between the two populations — a
dropped buffer is 10.67 ms and a rebuild Seam is ≥ 1 s by construction. The total rule catches what
a per-Seam rule misses: fifty scattered micro-gaps that add up to real damage. Surfacing everything
would fire the badge on something inaudible and teach the user to ignore it, which costs exactly the
case it exists for.

**Seams draw as a hatched band with a minimum width of about 3 pt**, at true width inside issue #7's
loupe. A minimum width is required because #7 fixed the timeline at always-fits-the-width, so a
20-minute master is ~1.2 s per pixel and a 1 s Seam is sub-pixel. Hatching rather than a colour is
deliberate: red is ADR-0004's transport, amber is ADR-0009's Runway, and a third hue would re-buy
that accessibility trade for something less urgent. Hatch also reads as *no data here* rather than
*warning*, which is what it means. Sub-threshold Seams live in a one-line summary in the editor
rather than littering the lane, and the Library row carries a **subtle trailing glyph on surfaced
Recordings only** — the Library is where a user arrives weeks later, when the moment's telling is
long gone. A hand-adopted file (issue #30) has no Seam attribute and is unmarked, correctly: the app
did not capture it and cannot vouch either way.

**The mark still means exactly one thing.** ADR-0009 left a guard-stopped Recording unmarked so that
this one would mean *the samples here may be dead*, and that holds: an early end is not itself a
mark, only dead samples are.

Settled in issue #18.

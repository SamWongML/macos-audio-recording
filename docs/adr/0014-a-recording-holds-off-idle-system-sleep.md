---
status: accepted
---

# A Recording holds off idle system sleep, but only the idle timer

ADR-0007 made **system sleep one of the six ends of a Recording**, because the gap sleep opens is
unbounded and padding an overnight sleep would write ~12 GB of zeros into the master. That is the
right answer to *what happens when the Mac sleeps mid-Recording*. It left the prior question open:
should the Mac be allowed to reach that end on its own, from the idle timer, while a Recording the
user deliberately started is running? The policy is that **a running Recording holds a
`ProcessInfo.beginActivity(options: .idleSystemSleepDisabled)` token for its exact lifetime**,
holding off the *involuntary* idle-sleep timer — and nothing else.

## Considered options

**Not asserting at all** — letting the idle timer end the Recording as an honest ADR-0007 end — was
the obvious alternative and is wrong for this app. The flagship use is *record a two-hour stream,
walk away, come back to a finished Recording*, and under this option that fails silently at the idle
timer with nothing the user could have done. Two things make a capture a stronger case for the hold
than the media *playback* that already takes this assertion routinely: a lost Recording is
**unrecoverable** — ADR-0007 established there is no multi-clip assembly to rejoin two files — where
a lost playback just replays, and idle sleep is **involuntary**, a timer the user did not choose in
this moment, unlike closing the lid.

**Also holding the display awake** (`.idleDisplaySleepDisabled`) was rejected. Audio capture never
needs the screen lit; holding a bright display on all night wastes power and is user-hostile. The
system-only hold is the actual need. The chosen assertion is documented to let the display dim and
sleep while the system stays awake, which is exactly the split we want.

**Offering an opt-out** — a preference to let the Mac sleep while recording — was rejected as a pure
footgun: it hands the user a way to defeat the one protection this decision exists to provide, and
the battery worry that might motivate it is already handled by the OS (see below). The hold is
therefore intrinsic to a running Recording, not a setting.

**Raw `IOPMAssertion`** was passed over for Foundation's `beginActivity`, the blessed idiom for
"doing a chunk of work, don't idle-sleep": one token tied to a lifetime rather than CF-typed
assertion-ID bookkeeping, and its `reason` string surfaces in `pmset -g assertions` as a free
diagnostic breadcrumb. `beginActivity` maps onto the same underlying
`kIOPMAssertPreventUserIdleSystemSleep`, so the semantics below are the assertion's, not an
approximation.

## Consequences

**The six ends are unchanged, and the deliberate ones cost no extra code.** The assertion's own
documented behaviour is that the system *still* sleeps for **lid close, the Apple menu's Sleep, and
low battery** (`IOPMLib.h`: *"The system may still sleep for lid close, Apple menu, low battery, or
other sleep reasons"*). So each of those remains precisely ADR-0007's system-sleep end — the token
is released, the Recording ends clean with all-real samples and no seam, and ADR-0009's notification
names sleep as the reason. The hold suppresses only the involuntary idle timer; it never fights a
sleep the user asked for or the hardware forces. The app does **nothing special for a closed lid** —
it is one of the six ends, and that falls out of the assertion for free.

**No battery runaway.** An unattended laptop on battery does not stay awake until it dies, because
"low battery" is one of the sleeps the assertion does not stop; the Recording ends as an honest
ADR-0007 sleep end before the battery is flat. Power assertions are in any case advisory — the OS
may decline them under battery, thermal, or user circumstances — which only reinforces that every
forced sleep stays an ADR-0007 end.

**No UI change.** The token is held for exactly the Recording's lifetime, so ADR-0004's red
`● 01:23` recording indicator already signals the state that implies the hold; a separate "keeping
awake" glyph would be redundant chrome on a surface kept deliberately spare. There is no menu-bar
signal for the hold and no toggle to disable it.

**No new vocabulary.** The hold is an internal behaviour, not a user-facing concept, so `CONTEXT.md`
is untouched.

Settled in issue #35.

---
status: accepted
---

# The disk guard is a headroom clock, not a byte count

A Recording is an unattended writer aimed at the boot volume at **~1.4 GB/hour** (ADR-0003), and
ADR-0007 lists **the disk guard** as one of the six reasons a Recording ends without naming it. The
guard is a **2 GB hard floor** on the volume holding the Library, watched by `statfs` every 5
seconds, with two advisory tiers defined in **time to that floor** rather than in bytes. There is no
maximum duration: disk is the only bound.

## Considered options

**`NSURLVolumeAvailableCapacityForImportantUsageKey` was rejected in favour of plain available
capacity**, which is the opposite of what Apple's own header recommends and is the most surprising
line in this decision. The important-usage key counts space the system expects to reclaim by purging
caches — on the development machine the two numbers differ by about 13 GB. The header's guidance is
that the important-usage key "should not be used in determining if there is room for an
irreplaceable resource," and that for irreplaceable resources you should "always attempt to save the
resource regardless of available capacity." That guidance is aimed at an app deciding whether to
*begin* saving something it already holds in memory; our case is the inverse — a capture that is
already streaming and whose failure mode is taking the whole machine to zero bytes. Read for its
intent rather than its letter, it points the same way we went: do not bet irreplaceable data on the
larger, softer number. Being ~13 GB pessimistic costs about nine minutes of headroom.

**Absolute byte thresholds for the advisory tiers** were the first answer and were wrong. The
master's byte rate is fixed at creation but is not a constant across Recordings — 1.38 GB/hour at
48 kHz against 1.27 at 44.1 — so the same 4 GB is a different warning depending on the Source's
rate. Worse, the obvious conversion to time divides free space by the rate, which measures time to
*zero* rather than time to the floor where we actually stop, and overstates the urgency of every
tier by the floor's own 87 minutes.

**A maximum duration** was rejected because nothing imposes one: CAF's `mChunkSize` is `SInt64`, and
APFS does not care. Any cap would be either high enough never to fire or low enough to cut a
legitimate long capture, with no principled value between. The case it was meant to serve — a
Recording the user forgot they started — is already served by the guard.

**A configurable floor** was rejected. The floor protects the machine rather than serving a
preference, and a user who lowers it to 500 MB has bought a wedged Mac, not a longer Recording. The
better escape hatch already exists: ADR-0006's Library is a folder, so a symlink points it at an
external volume and the floor then applies to *that* volume. This should not return as a settings
row.

## Consequences

**Headroom is `(free − 2 GB) ÷ rate`, and the tiers are times.** The menu bar item turns **amber at
3 hours** of headroom; a **user notification** is posted at **30 minutes**; the Recording **ends at
the floor**. At 48 kHz those are roughly 6.2 GB and 2.7 GB free. Amber is deliberately late enough
that a healthy disk never shows it — an advisory that is always on is decoration — and 30 minutes is
enough time to delete something and keep recording, which is the only action the warning asks for.

**The check is `statfs` on a 5-second timer**, off both the realtime IOProc and ADR-0003's writer
thread. `f_bavail × f_bsize` is exactly the plain available-capacity number chosen above, for one
syscall and no `URLResourceValues` churn. The cadence is set by *other* processes, not by us: we
drift about 23 MB per minute, while a competing download can cross a 2 GB floor in seconds. The
volume measured is the one holding the Library after resolving symlinks, not the boot volume.

**Tiers are a pure function of current headroom, so they recover silently.** Emptying the Trash
takes the item from amber back to red with no all-clear notification, and a posted warning is never
retracted — a notification records a moment that was true, and chasing it with "never mind" trains
the user to ignore both. A **15-minute hysteresis band** on both the tier and its notification stops
a Recording hovering on a boundary from flapping the menu bar every 5 seconds or warning twice.

**ENOSPC is the guard firing late, not a seventh end.** A competing writer can take the last bytes
between polls. The handling is identical — stop, finalize, notify — so ADR-0007's six ends stay six.
ADR-0003's negative-`mChunkSize` trick means the file on disk is already valid and playable up to
the last flushed buffer, so the loss is bounded to the in-flight ring buffer. Implementation note:
`AudioFile.h` has **no named disk-full error** — its enum stops at `kAudioFileFileNotFoundError`
(-43) — so this arrives as a raw pass-through status and cannot be matched on cleanly.

**A guard-stopped Recording is an ordinary Recording.** It carries no mark in its extended
attributes. Every sample in it is real and it is complete up to where it stopped; marking it would
blur the mark issue #18 may introduce, which should mean exactly one thing: *the samples here may be
dead*. The telling belongs to the moment, not to the file forever.

**A guard stop does not open the editor.** The standing rule that stop auto-saves and opens the
editor was written for the user's own gesture; a window appearing unbidden hours later, possibly
over a full-screen app, is hostile. The notification is the telling, and **clicking it opens the
editor** on that Recording.

**The app takes a second permission, and it is not a TCC one.** `NSUserNotification` is deprecated
as of macOS 11, so UserNotifications.framework is the only path and it needs
`requestAuthorization([.alert])`. It is requested **once, at the end of the first completed
Recording** — not at launch, and deliberately not at first record, where it would stack on the audio
grant ADR-0008 takes on that same gesture and get both denied. Nothing is persisted app-side:
`UNNotificationSettings.authorizationStatus` already reports `NotDetermined`. If it is denied,
nothing breaks — amber still works and the guard still stops.

**Amber costs a second pre-rendered menu bar variant.** ADR-0004 established that
`NSStatusBarButton` ignores `contentTintColor`, so colour arrives only as a non-template `NSImage`
plus an `attributedTitle`. The **whole item goes amber, glyph and clock together**, at the same 78pt
width and with no `⚠` added: red and amber on one item reads as a rendering bug. This makes colour
the sole signal at that tier, which is a **conscious accessibility trade, not an oversight** — a
colour-blind user loses an advisory, while the 30-minute tier is text and reaches them intact.

**Starting is refused below the floor**, and starts amber between the floor and the 3-hour tier.
Beginning a Recording the guard kills within a minute leaves junk in the Library and teaches nothing.
The refusal reuses the panel message surface ADR-0008 introduced for a denied grant; it names the
free space and the floor, and its action opens Finder at the Library rather than a Settings deep
link, there being no pane to send the user to. **The panel carries at most one blocking reason at a
time**; how that surface looks, and what happens if two reasons ever compete, belongs to issue #22.

**Library-wide growth is out of scope for v1.** Masters accumulate and the app never deletes one.
ADR-0006 made the folder the truth precisely so that Finder is the management tool.

Settled in issue #17.

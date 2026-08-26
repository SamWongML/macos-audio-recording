---
status: accepted
---

# The panel stays hand-rolled; the expanded-interface session is not worth the left-click

AppTape's panel is an `NSPopover` the app manages itself: `.transient`, closed by an outside
click, by a second click on the status item, and by **Escape**, and opened with a
`NSApp.activate()` the app calls. It does **not** adopt
**`NSStatusItem.expandedInterfaceDelegate`**, the macOS 27 API written for exactly this
situation.

That API is the reason this decision needs recording. Its header describes AppTape's case
verbatim — *"status items which do not use an `NSMenu` but instead position other windows
('expanded interface') relative to the item"* — and promises that adopting it *"allows the
status item to participate in ... menu tracking behaviors"*: exactly what
[ADR-0004](0004-nsstatusitem-not-menubarextra.md) knowingly forfeited. A future reader who
finds a hand-rolled popover sitting next to an unused first-party API will assume it was
missed. It was not.

## What it costs

The same paragraph carries the price: *"This method should be used instead of manually
toggling your interface by target/action handling on the button or item."* Target/action on the
button **is** ADR-0004's one-click stop.

Measured, the split is cleaner and more absolute than the prose suggests. With the delegate
set, a **left-click begins the session and the button's target/action never fires** — zero
left-click actions across a full run — while a **right-click fires target/action and begins no
session**, even while a session is live. The two coexist, split by mouse button; AppKit simply
takes the one ADR-0004 spent.

## What it delivers

Three of the five things that were hoped for.

**Menu tracking is real**: AppKit ends the session on an outside click, consistently ~0.5 s
*before* the app's own `popoverDidClose`. **Activation is free**: after 20 s inactive, a single
left-click produced `active=true`, a key popover window and `canBecomeKey=true` within **25
ms**, with **no `NSApp.activate` call at all** — so ADR-0004's stated activation cost is simply
not paid on this path. And the panel is genuinely key: typing reached a real field editor.

## What it does not deliver

- **Click-again-to-close is unreachable.** A left-click on the item while its own panel is open
  begins no session, ends no session and fires no action. The item becomes the one place on
  screen where clicking does not dismiss the panel.
- **Escape does not end a session.** Twelve presses across three live sessions in one run, more
  in another, zero endings. Every session-end in either log traces to an outside click or to
  the app's own `cancel()`.

That is the decision, and it is a plain ledger. The session costs the gesture ADR-0004 exists
to protect, returns only what the app already does by hand, and **loses two dismissal
gestures** on the way. Nothing on the credit side is unavailable to a popover the app opens
itself.

A state-dependent design was checked and rejected on the same evidence: the delegate can be set
and cleared at runtime and takes effect on the very next click — cleared mid-session, the
left-click action fired immediately with the session still live — so "delegate on while idle,
off while recording" was mechanically available. It would have bought AppKit's tracking in the
idle state only, at the price of a panel that dismisses differently depending on whether a
Recording is running.

## Consequences

**`.transient`, not `.semitransient`.** A semi-transient popover closes when the user interacts
with *the window containing its positioning view* — for a status item that window is the menu
bar, so it would effectively never close.

**Escape is the app's, deliberately, and must never be left to AppKit.** A plain `.transient`
popover does close on Escape, 5 times out of 5 — until a SwiftUI **`.onKeyPress` anywhere in
the panel** takes it away, even one returning `.ignored`, which is supposed to mean "I did not
handle this". Measured across two runs of the same panel. Relying on the free behaviour means
an unrelated UI change can silently remove Escape later.

**`NSApp.activate()`, not `activateIgnoringOtherApps:`.** The macOS 27 SDK marks the latter
`API_DEPRECATED("... Use NSApp.activate instead")`. ADR-0004's consequences name the deprecated
call; this supersedes that wording. Activation earns its keep — the popover window is key within
~5 ms and a text field takes keystrokes — and the theft is temporary: every close hands the
front back.

**Anchoring treats the button's frame as a claim to be checked.** `button.window.frame` is
untrustworthy at exactly the moments it matters: `[0,0 29x0]` before the item is placed, its
**last frame retained** while `isVisible` is false, and a stale duplicate `x` shared by two
items just after one is restored. A frame is usable only if it is non-empty *and* contained in
some `NSScreen.frame`; otherwise the panel anchors to the top-right of `NSScreen.main` below
`NSStatusBar.system.thickness`, still as a popover. Refusing to open would be worse — a hidden
item is exactly when someone is hunting for the app. The probe machine has no notch
(`safeAreaTop` 0, both `auxiliaryTop*Area` nil), so the notch overflow case is **untested**.

**The panel stays open when a Recording starts.**
[ADR-0008](0008-a-denied-grant-is-inferred-not-reported.md) infers a denied grant from 3 s of
all-zero *after the first press of record*, and the panel is the surface that message lands on;
a panel that dismissed on the press would have nowhere to put it. It also keeps issue #6's
pulsing record glyph and level meter on screen as the confirmation that capture began.

**One message surface, most-recent-reason-wins.** [ADR-0009](0009-the-disk-guard-is-a-runway-clock.md)
fixes that the panel carries at most one blocking reason; the collision it left open mostly
dissolves, because the disk check runs *before* `AudioDeviceStart`, so a press refused for space
never starts a tap and can never produce a denial inference. The two can only meet as a stale
message and a fresh one, so a new reason replaces the old. The row never disables the list:
pressing record again is the documented retry for a denied grant, and for the disk case a second
press re-checks and re-refuses, which reads honestly.

**An unrequested end is not a panel message.** All four of
[ADR-0010](0010-silence-never-ends-a-recording.md)'s unrequested ends already name their reason
in a notification. An ended Recording blocks nothing — every row is pressable again the instant
it stops — and reporting it in the panel too would make the same event arrive twice when the
panel happens to be open and once when it is not.

**A user stop opens the editor and takes focus; the panel closes if it was open.** A stop is
requested, which is exactly the boundary ADR-0010 drew: unrequested ends get a notification,
requested ones get the window.

**Arrow keys move focus between panel rows only *after* something inside the panel has been
clicked** — on the hand-rolled path and the session path alike, so it is neither the session's
fault nor its fix. Improving on it is **out of scope**, closed with
[#21](https://github.com/SamWongML/macos-audio-recording/issues/21) along with any route to the
status item that is not the mouse. Escape is unaffected and stays the app's own, above.

Settled in issue #22. Probe: branch `prototype/panel-behaviour`.

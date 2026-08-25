# Panel behaviour probe — issue #22

ADR-0004 left `MenuBarExtra` for a raw `NSStatusItem` and listed the bill: the app now
hand-rolls the popover, its dismissal, and `NSApp.activate`. Issue #22 was opened to decide
how each of those should behave.

Reading the macOS 27 SDK first turned up something the ADR did not know about:
**`NSStatusItem.expandedInterfaceDelegate`** and `NSStatusItemExpandedInterfaceSession`, both
`API_AVAILABLE(macos(27.0))`, in a header dated 2026. Its comment describes our case verbatim
— *"status items which do not use an `NSMenu` but instead position other windows ('expanded
interface') relative to the item"* — and promises that adopting it *"allows the status item to
participate in keyboard navigation and menu tracking behaviors"*: precisely the two things
ADR-0004 forfeited, and precisely what issue #21 exists to recover.

The same paragraph carries the price: *"This method should be used instead of manually
toggling your interface by target/action handling on the button or item."* Target/action on
the button **is** ADR-0004's one-click stop. So this probe exists to find out what the new API
actually delivers, and what it costs.

## What it builds

Three status items, so the two designs can be compared click for click in one process:

| item | wiring |
| --- | --- |
| **S** | `expandedInterfaceDelegate` set **and** target/action wired; popover `.applicationDefined`; **never** calls `NSApp.activate` |
| **T** | target/action only; popover `.transient`; `NSApp.activate()` on every open — exactly `prototype/menu-bar-surface`'s variant K |
| **D** | flips S's `expandedInterfaceDelegate` between `self` and `nil` at runtime |

Both panels host the same SwiftUI content: four focusable rows, a text field (the sharpest
test of key focus — it cannot take a keystroke unless the popover's window is key), and a live
`NSApp.isActive` readout. Everything either item does is timestamped into
`~/Library/Logs/AppTapePanelProbe.log`; `run1.log` and `run2.log` are kept here.

```
./run.sh
```

## What it found

**The delegate claims the left button, and it is the exact inverse of ADR-0004.** With the
delegate set, a **left-click begins the session and the button's target/action never fires** —
zero left-click actions across all of run 1 — while a **right-click fires target/action and
begins no session**, even while a session is live. They coexist cleanly, split by button;
AppKit simply takes the one ADR-0004 spent to buy one-click stop.

**The session does deliver three things.** AppKit ends it on an outside click, consistently
~0.5 s *before* our own `popoverDidClose`, so menu tracking is genuinely handled. The app was
inactive for 20 s and a single left-click produced `active=true`, `key=_NSPopoverWindow`,
`canBecomeKey=true` within **25 ms** — with **no `NSApp.activate` call at all**, so ADR-0004's
stated activation cost is not paid on this path. And the panel is really key: typing reached
`_SystemTextFieldFieldEditor`.

**It does not deliver the three that decided the issue.**

- **Click-again-to-close is unreachable.** A left-click on the item while its own panel is open
  begins no session, ends no session, and fires no action. The item is the one place on screen
  where a click does not dismiss the panel.
- **Escape does not end a session.** Twelve presses across three live sessions in run 1, more in
  run 2, zero endings; every session-end in either log traces to an outside click or to the
  probe's own `cancel()`.
- **Control+F8 never reached the item**, with the delegate on *or* off, in both runs. The
  menu-bar keyboard route — the one reason the left-click was worth paying — did not appear.

So `NSStatusItemExpandedInterfaceDelegate` costs the gesture ADR-0004 exists to protect and
returns only what variant K already does by hand, while *losing* two dismissal gestures.
ADR-0004 stands; see ADR-0011.

## Traps worth keeping

**A SwiftUI `.onKeyPress` anywhere in the panel takes Escape away from the popover.** Run 1's
plain `.transient` popover closed on Escape 5 times out of 5. Run 2's panel adds
`.onKeyPress(.escape)` returning `.ignored` — which should mean "I did not handle this" — and
Escape stopped dismissing it. Escape has to be an explicit `performClose` the app owns, or an
unrelated UI change can silently break it later.

**`activateIgnoringOtherApps:` is deprecated** in the macOS 27 SDK
(`API_DEPRECATED("... Use NSApp.activate instead")`). ADR-0004's consequences name it;
ADR-0011 corrects that to `NSApp.activate()`.

**`button.window.frame` is untrustworthy at exactly the moments anchoring matters.** Before
the item is placed it reads `[0,0 29x0]`; while `isVisible = false` it **keeps its last frame**,
so an anchor computed then points at bare menu bar; and after restoring, two different items
reported the same `x`. Any anchor has to check the frame is non-empty *and* inside some
`NSScreen.frame` before trusting it. This display has no notch (`safeAreaTop` 0, both
`auxiliaryTop*Area` nil), so the notch overflow case is **untested here**.

**Arrow keys do nothing on a freshly-opened panel.** Focus moves between rows only after
something inside the panel has been clicked — on *both* paths, so it is not the session's
fault and not the session's to fix. That belongs to issue #21.

**The delegate can be set and cleared at runtime** and takes effect on the very next click;
cleared mid-session, the left-click action fired immediately with the session still live. A
state-dependent design (delegate on while idle, off while recording) was therefore mechanically
available — it just isn't worth having.

**The session callbacks carry no click.** `NSApp.currentEvent` read `mouseMoved` at `didBegin`
and type 21 at `didEnd`, never the button press, so the delegate cannot tell you which gesture
opened the panel.

## Probe caveats

Run 1 shared a single `NSPopover` between S and T, which made "the session ended" ambiguous
whenever a T click had already closed S's panel by hand; run 2 gives each item its own popover
and is the one to trust on ordering. Control+F8 is reported here as *not reproduced on this
machine across two runs* — the system shortcut can be disabled in Settings, which was not
independently verified.

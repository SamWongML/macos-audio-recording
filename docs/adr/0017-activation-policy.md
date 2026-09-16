---
status: accepted
---

# 0017. AppTape is `.accessory` at rest and `.regular` while the editor is open

At rest AppTape is a pure menu-bar utility — no Dock icon, no app-switcher entry,
no application menu bar — because the transport is entirely the `NSStatusItem`
(ADR-0004) and the editor is launch-suppressed. When the editor window opens the
app flips to **`.regular`**, giving that window a Dock icon, a ⌘-Tab entry, and a
standard menu bar while it lives. Closing the last editor requests a return to
`.accessory` after AppKit transfers activation and menu bar ownership. The app can
briefly remain `.regular` without an editor while that handoff completes or while
the status panel remains open. This extends ADR-0004: the status panel still
explicitly activates the app so its controls work in accessory mode.

The scaffold (issue #11) set no `LSUIElement` and never called `setActivationPolicy`,
so as built AppTape was `.regular` — a permanent Dock icon — by omission. Nobody had
decided this; issue #42 did.

## Considered options

**`.accessory` fixed** — never a Dock icon, never a menu bar. Simplest: one policy,
no transitions, no launch flash. Rejected because the editor (issue #7) is the app's
primary editing surface — a three-column window with a sidebar, waveform, Trim and an
Export inspector — and `.accessory` removes its application menu bar, ⌘-Tab entry,
and Dock icon for re-revealing it behind other windows. Accessory apps can implement
keyboard handling, but do not provide this standard application-menu surface.

**`.regular` fixed** — a permanent Dock icon. Rejected because at rest there is
nothing behind the icon to open: the editor is launch-suppressed and, per issue #33,
there may be no Recording at all, so the icon would click through to nothing — which
is worse than no icon. It also contradicts ADR-0004's `LSUIElement` reasoning.

**Flip on window focus** rather than existence — `.regular` when the editor is key,
`.accessory` when it resigns. Rejected because it makes the Dock icon and menu bar
flicker away every time you ⌘-Tab to the very app you are recording to check on it.
Tying the policy to the window's *existence* keeps it a stable, switch-back-able
window while it is open.

## Consequences

**The desired policy is existence-based; demotion requires a completed handoff.**
`LSUIElement` launches the app as `.accessory` without a Dock flash. An editor
promotes it to `.regular`, independent of focus. Closing its window cancels Export
immediately but only schedules reconciliation on the main queue. Outside the
window-close notification, the app calls `hide(nil)` once if it is still active or
owns the menu bar. It applies `.accessory` only when it is inactive **and**
`NSWorkspace.menuBarOwningApplication` positively identifies another process.
An unknown owner is not evidence of a completed handoff.

The controller receives app deactivation/hide notifications and observes menu bar
ownership through documented KVO. It waits for these events, without a timed delay,
polling, forcing Finder/Dock to activate, private APIs, or hiding the system menu
bar. A pending transition is cancelled as soon as opening an editor is requested,
before SwiftUI attaches the window. Editor identities make duplicate reports
idempotent. The status panel suspends the handoff while it is open, and presentation
entry points unhide AppTape before showing UI again.

This sequencing replaces the original synchronous `.accessory` change inside
`NSWindow.willCloseNotification`, which could withdraw the active application's
menu bar while AppKit was still closing its window. The associated global icon
bounce remains a visual validation item; see the
[investigation](../investigations/2026-09-16-editor-close-menu-bar.md).

**The Dock icon is transient at rest.** It remains during the close handoff and is
removed after another application owns the menu bar. If AppKit cannot establish
that condition or refuses the policy change, keeping `.regular` is safer than
forcing a system UI transition. Policy failures are logged and may retry on a later
lifecycle event; they do not start a retry timer.

**The editor's menu bar is the standard system set**, trimmed of what does not apply
(App: About/Quit; File: Close ⌘W; Edit: the standard items; Window; Help). Issue #7
already places every control on-screen — the sidebar toggle, Play, Trim, Export — so
the menu bar's job is to make ⌘W/⌘Q and standard Edit shortcuts work, not to be a
control surface. App-specific command shortcuts (Export, Play, Reset Trim) are
implementation latitude within issue #7, not a decision here, and are unaffected by
the issue #21 keyboard-path scope boundary, which concerns the status item and stop,
not the editor's own shortcuts. `SidebarCommands()` and `InspectorCommands()` are
deliberately *not* added: issue #7 found they left the app with zero windows.

**v1 ships no app icon.** The Dock and app-switcher now show *an* icon whenever the
editor is open, but designing one is explicitly out of scope for v1 (issue #42), so
that surface carries the default generic application icon — an accepted v1 limitation,
distinct from ADR-0004's pre-rendered menu-bar glyph, which is unaffected.

Settled in issue #42.

---
status: accepted
---

# AppTape is `.accessory` at rest and `.regular` while the editor is open

At rest AppTape is a pure menu-bar utility — no Dock icon, no app-switcher entry,
no application menu bar — because the transport is entirely the `NSStatusItem`
(ADR-0004) and the editor is launch-suppressed. When the editor window opens the
app flips to **`.regular`**, giving that window a Dock icon, a ⌘-Tab entry, and a
standard menu bar for exactly as long as it lives; closing the window flips back to
`.accessory`. This is the hybrid a menu-bar app that owns a real window wants, and
it extends ADR-0004 rather than contradicting it: the app is still `.accessory`
whenever the panel shows, so ADR-0004's "an `LSUIElement` app is not frontmost, so
`NSApp.activate` is needed" stays true.

The scaffold (issue #11) set no `LSUIElement` and never called `setActivationPolicy`,
so as built AppTape was `.regular` — a permanent Dock icon — by omission. Nobody had
decided this; issue #42 did.

## Considered options

**`.accessory` fixed** — never a Dock icon, never a menu bar. Simplest: one policy,
no transitions, no launch flash. Rejected because the editor (issue #7) is the app's
primary editing surface — a three-column window with a sidebar, waveform, Trim and an
Export inspector — and `.accessory` denies it every first-class window affordance:
no ⌘W/⌘Q or standard Edit menu, no ⌘-Tab entry, and no Dock icon to re-reveal it if
it is hidden behind other windows. A real window deserves to behave like one.

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

**The flip is existence-based.** `.regular` from editor-open to editor-close,
independent of focus. Set `LSUIElement` in `Info.plist` so the app launches
`.accessory` with no Dock-icon flash, then `NSApp.setActivationPolicy(.regular)`
on editor open and `.accessory` on its close. SwiftUI 27 exposes no scene-level
activation-policy API (verified against the SDK's what's-new set), so this stays an
AppKit call in the app shell — which ADR-0004 already hand-rolls.

**The Dock icon can never open nothing.** Because the icon exists if and only if the
editor window does, the "Dock icon that opens nothing" failure the fixed-`.regular`
option carried cannot arise: there is always a window behind it, and clicking it just
re-reveals that window.

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

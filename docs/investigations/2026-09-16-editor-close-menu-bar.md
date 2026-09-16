# Editor close and the menu bar icon bounce

Investigated on 2026-09-16 against `af3c6b8`, on macOS 27.0 build 26A428.

## Finding and confidence

The leading cause is AppTape's synchronous `.regular` → `.accessory` activation
policy change during `NSWindow.willCloseNotification`. This is an application-wide
change to Dock and menu bar participation, performed before the close has completed.
It is the strongest explanation in this code for a simultaneous movement of other
applications' status icons.

The call path and premature policy change are verified in source. The exact
WindowServer animation and its disappearance with the patch are **not yet verified
visually**. The supplied screenshot is a still image, and attempts to connect to
the running/build-output AppTape through the available UI tool timed out. Apple's
documentation establishes API semantics, not a documented macOS 27 bug matching
this exact animation. Do not report this as a confirmed Apple defect or a visually
verified fix.

## Evidence

The original path was:

```text
red close button / File > Close / Command-W
  → NSWindow.willCloseNotification
  → EditorWindowLifecycle.windowWillClose
  → ExportCoordinator.cancel
  → ActivationPolicyController.editorDidClose
  → openEditorCount becomes zero
  → NSApp.setActivationPolicy(.accessory), synchronously
```

Apple defines [`willCloseNotification`](https://developer.apple.com/documentation/appkit/nswindow/willclosenotification)
as a notification that the window is about to close. It is not a notification that
deactivation or a menu bar handoff has finished.

The [accessory policy](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory)
removes the application's Dock and application-menu presence while still allowing
programmatic activation and windows. It does not remove the app's `NSStatusItem`.
Changing this policy affects the application's relationship with the system UI;
it is not equivalent to merely ordering out an editor window.

Apple separately exposes [`frontmostApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication)
for the recipient of keyboard input and
[`menuBarOwningApplication`](https://developer.apple.com/documentation/appkit/nsworkspace/menubarowningapplication)
for the owner of the displayed menu bar. The latter explicitly supports KVO. The
local macOS 27 SDK headers agree. Consequently, testing only `isActive == false`,
or reacting only to a window losing key status, cannot establish menu bar ownership.

The status item is created once by `MenuBarController.install()`. The close path
does not remove it, create a replacement, change its length, or animate its frame.
Its clock and glyph updates are driven by capture state. SwiftUI waveform and
sidebar animations have no direct control over other processes' status items.
These observations make a local glyph/layout animation a weaker explanation.

The existing tests only tested `count > 0 ? .regular : .accessory`. They could not
detect unsafe ordering between close, deactivation, and ownership transfer.

## Implemented solution

Keep the existing product behavior: launch as a menu bar utility; provide a normal
Dock entry and menus while the editor is open; return to accessory mode afterward.
Make the transition depend on observed state:

1. Cancel Export immediately and unregister the closing editor by window identity.
2. Enqueue reconciliation so no policy demotion or app hiding occurs inside the
   window's close callback.
3. If AppTape is still active or owns the menu bar, call `NSApp.hide(nil)` once.
   AppKit chooses the next app through its normal hide behavior. Apple states in
   [cooperative activation guidance](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation)
   that hiding implies deactivation; explicitly calling `deactivate()` is unnecessary.
4. Wait for deactivation and menu owner observations. Apply `.accessory` only when
   AppTape is inactive and another process positively owns the menu bar.
5. Recheck the current editor state on every deferred reconciliation. Cancel the
   pending return as soon as a new editor is requested, including the interval
   before SwiftUI creates its window. Defer the handoff while the status panel is
   open so it cannot be hidden by a pending editor close.
6. Unhide the app before presenting either the editor or the status panel again.

The main-queue enqueue establishes sequencing; it is not a guessed animation
duration. There is no `asyncAfter`, polling loop, global animation preference,
forced Finder activation, or private API. AppKit's
[`setActivationPolicy(_:)`](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:))
returns success/failure; a refusal is logged and preserves the pending transition
for a subsequent lifecycle event.

The deliberate tradeoff is a short period in which the Dock icon remains after
the editor closes. If ownership is unknown, a handoff never arrives, or AppKit
refuses the change, the controller retains `.regular` instead of forcing demotion.
This changes the exact timing promised by ADR-0017, which is amended with this patch.

## Alternatives

| Approach | Assessment |
| --- | --- |
| Fixed 100–500 ms delay before demotion | Does not prove handoff completion; races with reopening and varies with load and Spaces. |
| Only enqueue the existing demotion | Lets the close callback unwind but does not establish menu bar ownership. |
| Demote when the window resigns key | Also happens on ordinary app switching, sheets, and panel interaction while the editor remains open. |
| Call `deactivate()` or activate Finder/Dock directly | Bypasses normal focus selection; Apple discourages direct `deactivate()` for ordinary handoffs. |
| Disable animations or hide/show the system menu bar | Changes or disrupts system UI without correcting the lifecycle transition. |
| Permanent accessory policy | Eliminates runtime policy transitions but removes the editor's application menus and Dock/Command-Tab presence. |
| Permanent regular policy, with Dock reopen support | Eliminates runtime policy transitions and is the simplest architectural fallback if the macOS animation persists after a confirmed background demotion; changes the menu-bar-only-at-rest product behavior. |
| Separate accessory recorder and regular editor processes | Stable policy per process, but introduces IPC, lifetime, export, and library coordination far beyond this defect. |

No public API promises that an activation-policy change will never animate system
UI. If the guarded background transition still produces the bounce, the durable
next choice is a stable policy, not a longer delay or a second activation trick.

## Validation

The final `xcodebuild test` run passed all **360 tests** (370 executions including
parameterized cases), with zero failures or skips, on the affected macOS build.
All **14 activation-policy regression tests** passed. Repository-wide strict
`swift-format` lint and `git diff --check` also passed. The result bundle is
`/tmp/apptape-close-full-tests.xcresult`; the log is
`/tmp/apptape-close-full-tests.log`. The build required normal host access because
the execution sandbox blocked Icon Composer export and Xcode test services; the
successful run used unchanged project build/signing settings with
`CODE_SIGNING_ALLOWED=NO`.

The regression suite drives the production controller through an injected AppKit
boundary and a controlled main queue. It checks both event orders, unknown owners,
inactive closes, duplicate reports, multiple editor identities, reopen races,
status panel interaction, notification coalescing, policy refusal, and repeated
open/close cycles. These tests establish sequencing, not rendered animation.

Visual acceptance still requires an A/B run on the affected desktop:

1. Compare the original build with the patched build using the same menu bar,
   desktop, and window position. Record the top of the display at sufficient frame
   rate to see the one-shot movement; a screenshot cannot establish it.
2. Exercise red close, Command-W, and File > Close repeatedly. Verify one normal
   handoff, stationary status icons, and eventual removal from Dock/Command-Tab.
3. Reopen immediately, reopen after the app has hidden, and reopen from the status
   panel. Verify the editor is visible and its menus/shortcuts work.
4. Switch apps without closing and minimize/restore the editor. Its Dock entry
   must remain. Close while the status panel is open and verify the panel remains
   usable until dismissal.
5. Verify close while capturing leaves capture running, and close during Export
   still cancels Export. Exercise an external display, another Space, and a
   full-screen foreground app if present in the affected setup.
6. If the bounce persists, isolate policy demotion in a disposable diagnostic
   build by retaining `.regular` after close. If it persists even without demotion,
   investigate the system appearance/foreground transition rather than changing
   the controller's timing again.

---
status: accepted
supersedes: "issue #7's *exactly one pane control* and *permanently-visible inspector*"
---

# The inspector is hideable, and says so

Hiding the Library sidebar and showing it again made a button for the *trailing* pane appear in the
toolbar for a fraction of a second and then leave. A control that exists for 100 ms reads as a
rendering bug whichever way you resolve it, and this ADR resolves it toward the control being real:
**the Export inspector can be hidden, and the toggle that hides it is always in the toolbar.**

## The cause

`EditorView` presented the inspector with `.inspector(isPresented: .constant(true))`. A constant
binding is an inspector whose toggle cannot do anything, so SwiftUI suppressed the automatic toolbar
item — but the suppression is not stable across a toolbar rebuild, and hiding and showing the
leading sidebar rebuilds the toolbar. The item appeared for a frame or two on the way through.

The binding is now real state, so the toggle has something to do. The flicker is a symptom of a
control with no meaning; giving it meaning is what removes it.

## Considered options

**Removing the button instead was the other honest fix, and it was rejected on the human's call.**
It preserves issue #7 exactly and is a smaller change. It was not chosen, and there is a reason
beyond preference: issue #7's *permanently-visible inspector* was decided when the inspector held
the Export ladder and nothing else, and issue #76 has since pinned the Export control to the pane's
bottom edge and issue #77 gave the detail pane a brief that fills the space. A trailing pane you
cannot dismiss is a harder claim to defend for a window that now has content of its own to show,
and the editor's minimum width is 960 in large part because that pane cannot go away (issue #85).

**The toggle is declared explicitly, on the main toolbar, rather than left to the automatic one.**
An item declared inside the inspector's own view builder rides the strip of toolbar above the
inspector and is dismissed with it — the one placement that cannot serve as the way back once the
pane is closed. It is the standard `sidebar.trailing` symbol with a label that names what the click
will do, so the button is legible in a toolbar with no background behind it.

**`InspectorCommands()` is still not added.** Issue #7 found that `SidebarCommands()` and
`InspectorCommands()` left the app with zero windows (ADR-0017), and nothing here revisits that. The
menu route to this toggle does not exist, deliberately; the toolbar button is the whole interface.

## Consequences

**Issue #7's *exactly one pane control* is retired.** The editor has two: the system sidebar toggle
on the leading edge and this one on the trailing edge. They are symmetric, which is the arrangement
the original decision was avoiding — and the reason it was avoiding it (a trailing control that did
nothing, because the pane never moved) no longer holds.

**Issue #7's *permanently-visible inspector* is retired too, but only as far as the user's own
choice.** The inspector is still attached above all three detail branches, not inside the one that
has a Recording to export, so selecting a can't-open file or deselecting still does not make the
column disappear on its own (issue #73, finding 24). What changed is that the user may close it. The
distinction matters: the bug that finding was about was the pane vanishing *without being asked*.

**The choice persists across launches** (`@AppStorage`), because a pane the user closed should stay
closed, as every other macOS pane does.

**The window's 960 pt width floor is unchanged for now.** It is issue #85's crash guard, and while
hiding the inspector may well make the loop unreachable at narrower widths, that is a measurement
nobody has taken — the floor is not lowered on a guess. If closing the inspector does prove to make
narrow widths safe, that is a fact for issue #85 and possibly the shape of its fix, since a
conditionally-present `.inspector` is a different structure from a permanently-presented one.

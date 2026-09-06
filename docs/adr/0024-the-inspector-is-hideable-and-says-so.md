---
status: accepted
supersedes: "issue #7's *exactly one pane control* and *permanently-visible inspector*"
---

# The trailing pane is a column, not a SwiftUI inspector

Three symptoms were reported or measured against this editor, and they looked like three problems:

1. A toggle for the trailing pane flickered into the toolbar for a fraction of a second whenever the
   leading sidebar was hidden and shown again.
2. Showing the trailing pane made the **leading** sidebar collapse and come back.
3. The editor aborted in `_NSViewLayout` under any constraint it could not satisfy — too little
   width, too little height, or a bottom safe-area bar (issue #85).

**They are one framework bug.** `.inspector` on a `NavigationSplitView` is a known-broken
combination: [FB20061521](https://developer.apple.com/forums/thread/799125) (*abnormal Sidebar and
Columns state*) and [FB20061260](https://developer.apple.com/forums/thread/799794) (*the sidebar
toggle disappears when the sidebar is collapsed*) were filed in September 2025 and still reproduce
on macOS 26.2 RC, with no Apple reply and no published workaround anywhere. The reporter's own
conclusion is the one issue #85 reached independently, by bisection: **the bug only occurs if the
inspector modifier is present; removing it resolves the issue.**

**So the trailing pane stops being a SwiftUI `.inspector` and becomes an ordinary column of the
detail view** — an `HStack` with a hairline divider — and the Export inspector can be hidden by a
toolbar toggle that is always there.

## What this costs, and why it is still cheaper

`.inspector` gave two things for free, and both are now ours: the toggle button and the
drag-to-resize divider. Both are a few dozen lines. The alternative was to keep the modifier and
work around a bug that has survived five OS releases without anyone publishing a workaround, on a
window whose minimum width is a crash guard because of it. Owning forty lines is cheaper than
renting a defect.

## Considered options

**Keeping `.inspector` and mitigating was considered and rejected.** An explicit `columnVisibility`
binding and more slack in the three columns' widths might have suppressed the collapse; nothing
would have touched the abort, and the 960 pt width guard would have stayed. Betting on finding a
workaround that the reporters of two open Feedback issues did not find is not a durable fix.

**Removing the button instead was the other honest fix, and it was rejected on the human's call.**
It preserves issue #7 exactly and is a smaller change. It was not chosen, and there is a reason
beyond preference: issue #7's *permanently-visible inspector* was decided when the inspector held
the Export ladder and nothing else, and issue #76 has since pinned the Export control to the pane's
bottom edge and issue #77 gave the detail pane a brief that fills the space. A trailing pane you
cannot dismiss is a harder claim to defend for a window that now has content of its own to show,
and the editor's minimum width is 960 in large part because that pane cannot go away (issue #85).

**The toggle is ours, and there is exactly one of it.** An intermediate version kept `.inspector`
with a real binding *and* added an explicit `ToolbarItem`, which produced two buttons side by side —
SwiftUI's automatic `»` and ours. With the modifier gone there is no automatic one, so the single
explicit button is both the control and the whole interface. It carries `sidebar.trailing` with a
label naming what the click will do, so it stays legible in a toolbar with no background behind it.

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

**The window's 960 pt width floor is unchanged, and that is deliberately unfinished.** It is issue
#85's crash guard, and #85 already measured that the editor is fine at 800 pt with `.inspector`
removed — which is what this ADR does. The floor should therefore come down, and it has not, because
the measurement has not been *re-taken against this code*. It is not lowered on a strong inference.
Issue #85 owns the re-measurement and the number.

**Two other things become possible and are not taken here.** The bottom bar can probably become a
real `safeAreaBar(edge: .bottom)` — it aborts today only because of the inspector — and the editor
window can probably open during launch. Both are for whoever re-measures the floor, and both are
recorded so nobody has to rediscover them.

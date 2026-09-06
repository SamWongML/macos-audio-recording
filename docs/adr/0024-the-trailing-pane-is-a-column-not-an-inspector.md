---
status: accepted
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
detail view** — an `HStack`, a hairline `Divider`, and a fixed 276 pt width.

## What this costs, and why it is cheap

`.inspector` gave two things for free: a toggle button and a drag-to-resize divider. **Neither is
rebuilt, so neither is a cost.** The pane is permanently visible at one width, which is what issue
#7 decided in the first place; all that changes is the mechanism that delivers it. The whole
replacement is an `HStack` and a `Divider`.

The alternative was to keep the modifier and work around a bug that has survived five OS releases
without anyone publishing a workaround, on a window whose minimum width is a crash guard because of
it. Owning three lines is cheaper than renting a defect.

## Considered options

**Keeping `.inspector` and mitigating was considered and rejected.** An explicit `columnVisibility`
binding and more slack in the three columns' widths might have suppressed the collapse; nothing
would have touched the abort, and the 960 pt width guard would have stayed. Betting on finding a
workaround that the reporters of two open Feedback issues did not find is not a durable fix.

**A hand-built hide/show toggle was written, run, and then deleted.** With the modifier gone, the
toolbar button and the resize gesture could be ours: about forty lines, a persisted `@AppStorage`
preference, and an animation keyed to it. It was built on the argument that issue #7's
*permanently-visible inspector* was decided when the pane held the Export ladder and nothing else,
and that issue #76's pinned Export control and issue #77's brief had since given the window content
of its own — so a pane you cannot dismiss is a harder claim to defend.

**It was reversed on the human's call: the editor stays simple.** The counter-argument is the one
that holds. The pane's whole content is the Export ladder and the one line that explains its
absence — there is nothing in it a window with a 960 pt floor needs to put away. Against that, a
toggle buys a second pane control, a stored preference, an animation, a resize gesture with its own
drag-origin state, and a width that is two numbers instead of one. **Issue #7's *exactly one pane
control* and *permanently-visible inspector* therefore both stand, and this ADR supersedes
neither.** It changes only how they are implemented.

**`InspectorCommands()` is still not added.** Issue #7 found that `SidebarCommands()` and
`InspectorCommands()` left the app with zero windows (ADR-0017), and nothing here revisits that.
With no trailing pane control at all, there is nothing for it to command.

## Consequences

**The editor window has no toolbar items.** It had none before the toggle and has none again, so
`toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`, `CommandGroup(replacing: .toolbar) { }`
and `EditorWindowLifecycle.trimViewMenu()` all keep doing exactly what they did.

**The pane's width is a constant, `EditorView.inspectorWidth`.** 276 was the ideal the resizable
version defaulted to and the width every screenshot in issue #77 was judged at.

**Issue #73's finding 24 stays fixed.** The column is attached above all three detail branches, not
inside the one that has a Recording to export, so selecting a can't-open file or deselecting shows
the pane's own empty state rather than making the column disappear.

**The window's 960 pt width floor is unchanged, and that is deliberately unfinished.** It is issue
#85's crash guard, and #85 already measured that the editor is fine at 800 pt with `.inspector`
removed — which is what this ADR does. The floor should therefore come down, and it has not, because
the measurement has not been *re-taken against this code*. It is not lowered on a strong inference.
Issue #85 owns the re-measurement and the number.

**Two other things become possible and are not taken here.** The bottom bar can probably become a
real `safeAreaBar(edge: .bottom)` — it aborts today only because of the inspector — and the editor
window can probably open during launch. Both are for whoever re-measures the floor, and both are
recorded so nobody has to rediscover them.

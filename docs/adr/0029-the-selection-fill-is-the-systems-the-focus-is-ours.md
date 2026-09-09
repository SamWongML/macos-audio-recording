---
status: accepted
---

# The selection fill is the system's, the focus is ours

Issue [#95](https://github.com/SamWongML/macos-audio-recording/issues/95) asked what switches the
Library sidebar between an accent-filled selected row and a grey one. Two earlier tickets had seen
it — [#78](https://github.com/SamWongML/macos-audio-recording/issues/78) guessed keyboard focus and
said so was unverified, [#88](https://github.com/SamWongML/macos-audio-recording/issues/88) ruled it
out of the motion language — and nobody had established the mechanism.

**The mechanism is AppKit's emphasized/unemphasized selection, and it tracks exactly one thing: is
the sidebar's `List` the first responder of the *key* window?** Accent if it is, mid grey if it is
not. Both fills are macOS's own and **neither is AppTape's to draw**.
[ADR-0025](0025-the-row-is-one-line-the-inspector-states-the-export.md) already assumed this and
made every colour in the row survive both.

**What was wrong was not the fill. It was the focus.**

## Measured, in the running app

Driven with synthesised clicks and read back through `AXFocusedUIElement`, on the real 39-Recording
Library:

| State | First responder | Fill |
| --- | --- | --- |
| Editor just opened | `AXOutline` "Sidebar" | accent |
| AppTape not frontmost | (unchanged) | grey |
| Search field focused, by Tab or by click | `AXTextField` | grey |
| Search field focused, then a row clicked | `AXTextField` — **unchanged** | grey |

The last row is the defect. Clicking a Library row changed the selection and left first responder in
the search field, so the row the user was looking straight at wore the *inactive* fill, and ↑/↓ and
Return still belonged to the search. **Nothing else in the window released the field either** — not
the waveform, not the inspector, both of which are unfocusable — and the window's key-view loop has
exactly two stops, the field and the list. Only Tab or Escape got focus back.

`.searchFocused($isSearchFocused)` is **not** the cause: a build with that modifier removed behaves
identically. This is SwiftUI's sidebar `List`, which takes first responder on a click that also makes
the window key and does not take it when the window is key already. `NSTableView` has always taken
it, and Finder's own search field gives it up on the next click in the window.

## The decision

**Picking a row moves the keyboard focus into the list** — one line in `selectionBinding`'s setter
(`EditorView.swift`), against a `@FocusState` on the `List`. That setter is the right home because it
is driven only by the list's own selection UI: a click or an arrow key. It is *not* called when a
query filters the selected row out of view, so typing in the search field keeps its focus; that was
measured too, not reasoned about.

The rejected alternative was to make the row *look* selected regardless — our own fill, or forcing
the emphasized style. It fixes the screenshot and lies about the app: the keyboard really was in the
search field, and a row that looks active while ↑/↓ does nothing is worse than one that admits it.
The grey is honest feedback; it was being shown at the wrong moment.

This is not [ADR-0019](0019-content-is-the-colour.md) territory. The accent in that fill is the
*system* accent — `AccentColor.colorset` is deliberately empty
([#81](https://github.com/SamWongML/macos-audio-recording/issues/81)) — not `Signal`, and chrome
drawn by macOS is chrome AppTape does not colour.

## Amended by issue [#113](https://github.com/SamWongML/macos-audio-recording/issues/113): the first row of that table was true at every size but the shipped one

The table above says *Editor just opened → `AXOutline` → accent*. That was measured at whatever
window size the session happened to use, and it is true at 960 × 552, 1040 × 560, 1120 × 620,
1160 × 680, 1200 × 640, 1200 × 681 and 1201 × 680. At **1200 × 680 — the frame `.defaultSize`
declares, and the one every first run gets** — the freshly-opened editor had `AXFocusedUIElement` =
the `AXWindow`, the selected row wore the inactive grey `(72, 72, 73)` in Dark and `(214, 214, 216)`
in Light, and ↓ changed nothing (the before and after screenshots were byte-identical).

**The mechanism is a race, and the window's restored frame is what decides it.** Read off a
swizzled `makeFirstResponder` with a stack trace: `-[NSWindow _setUpFirstResponder]` →
`_selectFirstKeyView` runs from inside `-[NSWindow _doOrderWindow:]` — the moment the window is
first ordered on screen, **exactly once** — walks the key view loop and makes the first focusable
view the first responder. Whether SwiftUI has installed the sidebar list by then is the race:

| | 1200 × 680 | 1201 × 680 |
| --- | --- | --- |
| restored frame vs. the frame the window was created at | same **size**, a pure move | size differs |
| `setFrame` → `makeKeyAndOrderFront` | **1 ms** | 48 ms |
| the list, at order-in | **absent** | `SwiftUIOutlineListView` present |
| `_selectFirstKeyView` | finds nothing; the window stays its own first responder | `makeFirstResponder(SwiftUIOutlineListView) -> true` |

A restored frame whose *size* differs from `.defaultSize` forces a layout pass before the order-in,
and SwiftUI builds the content inside it. A frame of the same size is a pure move, which forces
nothing — so the window is ordered in one millisecond later with an empty content tree, and the
keyboard lands nowhere. **`_setUpFirstResponder` never runs again**, which is why deactivating and
re-activating the app does not repair it: measured, and the focus stayed on the window.

So `.defaultSize` is not a magic number here — **any** saved frame matching the size the window was
created at reproduces it. That happens to be every install that has never been resized, which is
why this defect sat on the path nobody has to do anything to reach while five sessions photographed
the editor at other sizes and saw the accent.

**The fix is one `.onAppear` on the sidebar list**, setting the same `@FocusState` this ADR already
introduced. The list's own appearance is the one place that knows the list exists;
[#96](https://github.com/SamWongML/macos-audio-recording/pull/96)'s `selectionBinding` setter cannot
cover it, because it only fires on a click or an arrow key — after the user has already found the
keyboard missing. It is guarded on the search field, so a reopened window cannot pull focus off a
field being typed into.

**This is not the rejected alternative below.** It does not force the emphasized *fill*; it moves
the *keyboard*, and the fill then tells the truth about where the keyboard is, which is what this
ADR asks of it. Verified on screen at 1200 × 680 and at the 960 × 552 floor, in both appearances: *(That floor was **552**; [#114](https://github.com/SamWongML/macos-audio-recording/issues/114) moved it to **656** — the code declares a content height of 604 and the window adds the 52 pt title bar ([ADR-0038](0038-the-dock-has-a-fill-and-it-is-the-bars-own.md); `safeAreaBar` itself costs nothing). The verification stands as taken; the number it names is historical.)*
the row opens on the accent — `(47, 108, 248)` Dark, `(43, 98, 236)` Light — ↓ moves the selection,
and Tab into the search field then typing (including a query that matches nothing) leaves
`AXFocusedUIElement` an `AXSearchField` throughout.

## What stays

**The grey when AppTape is not frontmost stays, untouched.** Every macOS sidebar does it, it is the
window telling you where your keyboard is, and an app that suppressed it would be the odd one out.
The two fills are a feature; only their timing was broken.

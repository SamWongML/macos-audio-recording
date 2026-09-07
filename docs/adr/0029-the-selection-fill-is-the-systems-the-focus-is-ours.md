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

## What stays

**The grey when AppTape is not frontmost stays, untouched.** Every macOS sidebar does it, it is the
window telling you where your keyboard is, and an app that suppressed it would be the odd one out.
The two fills are a feature; only their timing was broken.

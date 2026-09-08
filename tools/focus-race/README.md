# The focus-race harness (issue #113)

Throwaway. It reproduces, names and then verifies the defect where **the editor opens at its own
default size with the keyboard nowhere**; it is **never merged**. The scripts are the third sweep's
([`prototype/editor-third-sweep`](https://github.com/SamWongML/macos-audio-recording/tree/prototype/editor-third-sweep/tools/third-sweep))
plus five of this ticket's own, and they obey every rule that README lists — shoot in Release,
launch fresh at a saved frame rather than resizing, `AXRaise` before any synthetic click, address
the process by `unix id`.

## Reproducing

```
./launch.sh 1200x680 dark   # the shipped frame: focus nowhere
./focus.sh                  # AXWindow | AXStandardWindow
./launch.sh 1201x680 dark   # one pixel wider: focus in the sidebar
./focus.sh                  # AXOutline | desc=Sidebar
```

## The instrument that named the mechanism

`AXFocusedUIElement` says *where* the focus is, never *who* put it there, and the fill says even
less. `FocusProbe.swift` swizzles four `NSWindow` methods and prints a stack from
`makeFirstResponder` — that is what produced `-[NSWindow _setUpFirstResponder]` →
`_selectFirstKeyView`, called once from `_doOrderWindow:`. Drop it into `AppTape/AppTape/`, add
`_ = FocusProbe.install` to `applicationDidFinishLaunching` and `.focusProbe()` to the editor's
body, then `PROBE_LOG=… ./launchprobe.sh 1200x680 dark`. The two logs it produced are kept here:

| | `setFrame` → `makeKeyAndOrderFront` | the list, at order-in | `_selectFirstKeyView` |
|---|---|---|---|
| `probe-1200x680.log` | 1 ms (a pure move: same size) | **absent** | picks nothing |
| `probe-1201x680.log` | 48 ms (a resize, so a layout pass) | present | `makeFirstResponder(SwiftUIOutlineListView) -> true` |

**Two things the probe is worth keeping for.** `outline=` in every line is the difference between
"the focus is wrong" and "the list was not there to be chosen" — the second is the actual finding.
And the swizzle logs the window's `frame` on `setFrame`, which is what showed the trigger is not the
number 1200 × 680 but *any restored frame whose size the window already has*.

## Verifying

| | |
|---|---|
| `verify.sh <WxH> <dark\|light> <prefix>` | Launch, read the focus, shoot, press ↓, shoot again, and diff the two — `NOTHING` means ↓ did nothing. |
| `rowfill.py <png> <logical-width>` | Group a column of the sidebar into bands of uniform colour: the selection fill, read off the pixel rather than the palette (ADR-0032). |
| `searchtest.sh <WxH> <dark\|light>` | Tab into the search field, type, then type a query that matches nothing, reading the focus after each. |
| `focus.sh` / `key.sh <keycode>` | Read `AXFocusedUIElement`; send a key (125 = ↓). |

`shots/` holds the before-and-after at the default size in both appearances, the after at the 960
floor in both, and one after-↓ frame. The numbers they carry: grey `(72, 72, 73)` Dark and
`(214, 214, 216)` Light before; accent `(47, 108, 248)` Dark and `(43, 98, 236)` Light after.

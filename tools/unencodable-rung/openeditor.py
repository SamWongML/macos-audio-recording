"""Click the panel's `Open Editor` link.

By measured offset inside the panel's own CGWindow bounds, not by absolute screen coordinates:
the panel is anchored to the status item and the status item moves. The AX route is closed —
`entire contents` of the panel window returns nothing at all for this SwiftUI panel, so there is
no AXLink to find.

**The second click is conditional, and that is the whole bug this file was rewritten for.** #98's
rule is that the panel does not accept first mouse, so the harness sent every click twice. When
the *first* click does land, the panel closes and the editor opens underneath the pointer — and
the second click goes into the editor, selecting the first Library row and hitting the transport.
Five 'empty column' shots came back with `hhh` selected and playing at 0:06.57. So: click, look
for the editor, and only click again if it is not there.
"""
import sys, time, Quartz

def windows():
    opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    return [w for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
            if w.get('kCGWindowOwnerName') == 'AppTape']

def panel():
    for w in windows():
        if w.get('kCGWindowLayer', 0) > 0:
            b = w['kCGWindowBounds']
            return b['X'], b['Y'], b['Width'], b['Height']
    return None

def editor():
    return any(w['kCGWindowBounds']['Width'] >= 500 for w in windows())

def click(x, y):
    pt = (x, y)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, pt, 0))
    time.sleep(0.15)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, pt, Quartz.kCGMouseButtonLeft))
    time.sleep(0.06)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, pt, Quartz.kCGMouseButtonLeft))

p = panel()
if not p:
    print("no panel"); sys.exit(1)
X, Y, W, H = p
x, y = X + 60, Y + H - 28          # the link sits in the panel's bottom bar, hard left
for attempt in range(4):
    click(x, y)
    time.sleep(1.2)
    if editor():
        print("editor open after", attempt + 1, "click(s)"); sys.exit(0)
    if not panel():                # the click dismissed the panel without opening anything
        print("panel gone, no editor"); sys.exit(1)
print("gave up"); sys.exit(1)

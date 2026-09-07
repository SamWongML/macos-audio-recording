"""Command-click, for deselecting the sidebar's one selected row.

*Nothing selected* is the third route into the empty trailing column (#111): an empty Library, a
can't-open file, or the user deselecting. Only the last one is reachable with the Library intact.
"""
import sys, time, Quartz
x, y = float(sys.argv[1]), float(sys.argv[2])
p = (x, y)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, p, 0))
time.sleep(0.2)
for kind in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
    e = Quartz.CGEventCreateMouseEvent(None, kind, p, Quartz.kCGMouseButtonLeft)
    Quartz.CGEventSetFlags(e, Quartz.kCGEventFlagMaskCommand)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
    time.sleep(0.06)
print("cmd-clicked", p)

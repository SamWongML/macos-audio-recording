import sys, time, Quartz
x, y = float(sys.argv[1]), float(sys.argv[2])
p = (x, y)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, p, 0))
time.sleep(0.15)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, p, Quartz.kCGMouseButtonLeft))
time.sleep(0.06)
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, p, Quartz.kCGMouseButtonLeft))
print("clicked", p)

import sys, time, Quartz
x, y, ticks = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventMouseMoved, (x, y), 0))
time.sleep(0.3)
for _ in range(abs(ticks)):
    e = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, -3 if ticks > 0 else 3)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
    time.sleep(0.05)
print("scrolled", ticks)

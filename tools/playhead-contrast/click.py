import sys, time
import Quartz

def click(x, y, times=2, delay=0.35):
    for _ in range(times):
        for kind, is_down in ((Quartz.kCGEventLeftMouseDown, True),
                              (Quartz.kCGEventLeftMouseUp, False)):
            ev = Quartz.CGEventCreateMouseEvent(None, kind, (x, y), Quartz.kCGMouseButtonLeft)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, ev)
            time.sleep(0.05)
        time.sleep(delay)

if __name__ == "__main__":
    x, y = float(sys.argv[1]), float(sys.argv[2])
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    click(x, y, n)
    print(f"clicked {x},{y} x{n}")

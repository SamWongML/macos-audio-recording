"""Press at a point, travel to another, and HOLD — or release.

The loupe only exists while a Trim handle is under the hand, so the shot has to happen with the
button down: `screencapture -x -o -l <id>` does return a correct image mid-drag (#103's harness
note, contradicting #73). Travel is stepped, because a single jump does not read as a drag.

  drag.py hold  <x0> <y0> <x1> <y1>
  drag.py release <x> <y>
"""
import sys, time, Quartz

def post(kind, pt, btn=Quartz.kCGMouseButtonLeft):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateMouseEvent(None, kind, pt, btn))

mode = sys.argv[1]
if mode == "hold":
    x0, y0, x1, y1 = (float(v) for v in sys.argv[2:6])
    post(Quartz.kCGEventMouseMoved, (x0, y0)); time.sleep(0.3)
    post(Quartz.kCGEventLeftMouseDown, (x0, y0)); time.sleep(0.25)
    steps = 24
    for i in range(1, steps + 1):
        post(Quartz.kCGEventLeftMouseDragged, (x0 + (x1-x0)*i/steps, y0 + (y1-y0)*i/steps))
        time.sleep(0.03)
    print("holding at", x1, y1)
else:
    x, y = (float(v) for v in sys.argv[2:4])
    post(Quartz.kCGEventLeftMouseDragged, (x, y)); time.sleep(0.25)
    post(Quartz.kCGEventLeftMouseUp, (x, y))
    print("released at", x, y)

import sys, Quartz
pid = int(sys.argv[1])
wl = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements,
    Quartz.kCGNullWindowID)
for w in wl:
    if w.get('kCGWindowOwnerPID') != pid:
        continue
    b = w.get('kCGWindowBounds')
    print(w['kCGWindowNumber'], int(b['X']), int(b['Y']), int(b['Width']), int(b['Height']),
          repr(w.get('kCGWindowName', '')))

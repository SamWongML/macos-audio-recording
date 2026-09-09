import Quartz, sys
opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID):
    if w.get('kCGWindowOwnerName') != 'AppTape':
        continue
    b = w['kCGWindowBounds']
    if b['Width'] < 500:      # the panel, not the editor
        continue
    print(w['kCGWindowNumber'], int(b['X']), int(b['Y']), int(b['Width']), int(b['Height']))
    sys.exit(0)
print("none"); sys.exit(1)

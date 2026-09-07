#!/bin/bash
# PROTOTYPE harness (#98): start a real capture of QuickTime Player, open the editor on it,
# and shoot each lane variant. Two clicks per press: AppTape's panel does not accept first
# mouse, so the first synthetic click is swallowed by window activation.
set -e
SP="$1"
APP=/Users/demon/Library/Developer/Xcode/DerivedData/AppTape-fbylfxhrhjwkuohgbegywcrbzppo/Build/Products/Debug/AppTape.app
click() { python3 "$SP/click.py" "$1" "$2" >/dev/null; }

osascript -e 'tell application "QuickTime Player"
  activate
  set d to front document
  set looping of d to true
  play d
end tell' >/dev/null 2>&1 || true

open -a "$APP"; sleep 3
osascript "$SP/statusclick.applescript" >/dev/null
sleep 1.2
click 1305 88; sleep 0.7; click 1305 88     # QuickTime row = record
sleep 3
click 1281 343; sleep 0.5; click 1281 343   # Open Editor
sleep 2.5
osascript "$SP/statusclick.applescript" >/dev/null   # dismiss panel
sleep 1
echo "capture running, editor open"

#!/bin/zsh
# Read AppTape's AXFocusedUIElement (role / subrole / description / title).
PID=$(pgrep -f "Release/AppTape.app/Contents/MacOS/AppTape" | tail -1)
osascript <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $PID)
    try
      set el to value of attribute "AXFocusedUIElement"
    on error errmsg
      return "no focused element: " & errmsg
    end try
    set r to ""
    try
      set r to r & (value of attribute "AXRole" of el)
    end try
    set r to r & " | subrole="
    try
      set r to r & (value of attribute "AXSubrole" of el)
    end try
    set r to r & " | desc="
    try
      set r to r & (value of attribute "AXDescription" of el)
    end try
    set r to r & " | title="
    try
      set r to r & (value of attribute "AXTitle" of el)
    end try
    return r
  end tell
end tell
APPLESCRIPT

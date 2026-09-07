#!/bin/zsh
# Report the AppTape editor window's frame via System Events.
osascript <<'AS'
tell application "System Events"
  if not (exists process "AppTape") then return "no process"
  tell process "AppTape"
    if (count of windows) is 0 then return "no window"
    set p to position of window 1
    set s to size of window 1
    return "pos " & (item 1 of p) & "," & (item 2 of p) & "  size " & (item 1 of s) & "x" & (item 2 of s)
  end tell
end tell
AS

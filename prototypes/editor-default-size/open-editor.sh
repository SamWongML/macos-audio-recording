#!/bin/zsh
# Click AppTape's status item, then its "Open Editor" button.
osascript <<'AS'
tell application "System Events"
  tell process "AppTape"
    click menu bar item 1 of menu bar 2
  end tell
end tell
AS
sleep 1
osascript <<'AS'
tell application "System Events"
  tell process "AppTape"
    set out to ""
    repeat with w in windows
      set out to out & "WIN: " & (name of w) & " role=" & (role of w) & return
    end repeat
    return out
  end tell
end tell
AS

tell application "System Events"
  tell process "AppTape"
    repeat with i from 1 to (count of menu bars)
      repeat with j from 1 to (count of menu bar items of menu bar i)
        try
          if (description of menu bar item j of menu bar i) is "AppTape" then
            click menu bar item j of menu bar i
            return "clicked " & i & "/" & j
          end if
        end try
      end repeat
    end repeat
    return "not found"
  end tell
end tell

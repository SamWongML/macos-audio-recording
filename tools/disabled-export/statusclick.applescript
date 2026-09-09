-- Click AppTape's status item. Targets the process by unix id, because a *second* AppTape —
-- a Debug build sitting stopped under Xcode's debugger, STAT `SX` — is also called AppTape and
-- System Events hands `process "AppTape"` whichever it likes.
on run argv
  set thePid to (item 1 of argv) as integer
  tell application "System Events"
    tell (first process whose unix id is thePid)
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
end run

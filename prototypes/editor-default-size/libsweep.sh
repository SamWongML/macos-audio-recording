#!/bin/zsh
SP=/private/tmp/claude-501/-Users-demon-codes-macos-audio-recording-AppTape/7e9bdbc4-e4d7-45f2-855d-5664befe784c/scratchpad
H=$1
osascript -e "tell application \"AppTape\" to activate" >/dev/null
osascript -e "tell application \"System Events\" to tell process \"AppTape\" to tell window 1 to set position to {40, 60}" >/dev/null
osascript -e "tell application \"System Events\" to tell process \"AppTape\" to tell window 1 to set size to {1120, $H}" >/dev/null
sleep 1
osascript -e 'tell application "System Events" to click at {110, 197}' >/dev/null
sleep 1.5
bad=0
for i in {1..39}; do
  screencapture -x -R 40,60,1120,$H "$SP/lib.png"
  res=$(python3 "$SP/scroller.py" "$SP/lib.png" 1120)
  if [[ "$res" == SCROLLER* ]]; then print -n "$i "; bad=$((bad+1)); fi
  osascript -e 'tell application "System Events" to key code 125' >/dev/null   # Down
  sleep 1.1
done
print "\nheight $H -> $bad of 39 Recordings scroll the trailing column"

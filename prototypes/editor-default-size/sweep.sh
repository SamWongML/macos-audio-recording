#!/bin/zsh
SP=/private/tmp/claude-501/-Users-demon-codes-macos-audio-recording-AppTape/7e9bdbc4-e4d7-45f2-855d-5664befe784c/scratchpad
W=$1
for H in $@[2,-1]; do
  osascript -e "tell application \"System Events\" to tell process \"AppTape\" to tell window 1 to set size to {$W, $H}" >/dev/null
  sleep 0.7
  screencapture -x -R 80,60,$W,$H "$SP/w${W}h${H}.png"
  printf "%sx%s  " $W $H
  python3 "$SP/lane.py" "$SP/w${W}h${H}.png" $W
done

#!/bin/bash
# PROTOTYPE (#79): shoot the candidates in a real Finder window, both appearances.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
WAS=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
restore() { osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WAS" || true; }
trap restore EXIT
osascript >/dev/null <<OSA
tell application "Finder"
  activate
  set w to make new Finder window to POSIX file "$DIR/preview4"
  set current view of w to icon view
  set bounds of w to {200, 160, 1180, 620}
  set icon size of icon view options of w to 128
  set arrangement of icon view options of w to arranged by name
end tell
OSA
for mode in false true; do
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $mode"
  sleep 3
  screencapture -x -t png "$DIR/finder-$([ $mode = true ] && echo dark || echo light).png"
done
osascript -e 'tell application "Finder" to close front window' >/dev/null || true

#!/bin/bash
# PROTOTYPE (#79): put the four candidates in the real Dock, shoot it, put the Dock back.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP=/tmp/cc-dock-backup.plist
restore() { cp "$BACKUP" ~/Library/Preferences/com.apple.dock.plist; killall cfprefsd 2>/dev/null || true; killall Dock; }
trap restore EXIT
for v in A F G H; do
  defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$DIR/preview4/AppTape$v.app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
done
killall Dock
sleep 5
screencapture -x -t png "$DIR/dock-full.png"

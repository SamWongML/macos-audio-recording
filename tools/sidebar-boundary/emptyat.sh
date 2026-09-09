#!/bin/zsh
# empty.sh, but at a caller-chosen origin (#115): the like-for-like against Finder's empty
# content pane, needed because both panes are behind-window vibrancy and move with the desktop.
set -e
HERE=${0:a:h}
LIB=$HOME/Music/AppTape; ASIDE=$HOME/Music/AppTape.aside-115
BEFORE=$(ls -1 "$LIB" | wc -l | tr -d ' ')
restore() {
  pkill -f "Release/AppTape.app" 2>/dev/null || true; sleep 1
  if [[ -d $ASIDE ]]; then
    if [[ -d $LIB ]]; then
      local n=$(ls -1 "$LIB" | wc -l | tr -d ' ')
      if [[ $n == 0 ]]; then rmdir "$LIB"; else echo "REFUSING to remove $LIB — $n files"; return; fi
    fi
    mv "$ASIDE" "$LIB"
  fi
  echo "Library restored: $BEFORE -> $(ls -1 "$LIB" | wc -l | tr -d ' ')"
}
trap restore EXIT INT TERM
mv "$LIB" "$ASIDE"
for spec in "$@"; do
  IFS=: read X Y W H AP OUT <<< "$spec"
  zsh "$HERE/atpos.sh" $X $Y $W $H $AP >/dev/null
  zsh "$HERE/shoot.sh" "$HERE/shots/$OUT" >/dev/null
done

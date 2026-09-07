#!/bin/zsh
# PROTOTYPE harness (#111). The empty column cannot be reached with a full Library: the editor
# selects the newest Recording on first open (`EditorModel.reconcileSelection`), so "nothing
# selected" is not a state a fresh launch lands in. #106's method instead — the Library moved
# aside on the same volume and restored in the same shell invocation, counted both ways.
#   shoot-empty.sh <SP> <out-prefix> <A B C ...>
set -e
SP=$1; PREFIX=$2; shift 2
LIB=$HOME/Music/AppTape
ASIDE=$HOME/Music/AppTape.aside-111
BEFORE=$(ls -1 "$LIB" | wc -l | tr -d ' ')

restore() {
  pkill -f "Release/AppTape.app" 2>/dev/null || true
  sleep 1
  if [[ -d $ASIDE ]]; then
    # The app recreates the folder empty; only ever remove one that IS empty.
    if [[ -d $LIB ]]; then
      local n=$(ls -1 "$LIB" | wc -l | tr -d ' ')
      if [[ $n == 0 ]]; then rmdir "$LIB"; else echo "REFUSING to remove $LIB — $n files in it"; return; fi
    fi
    mv "$ASIDE" "$LIB"
  fi
  local AFTER=$(ls -1 "$LIB" | wc -l | tr -d ' ')
  echo "Library restored: $BEFORE -> $AFTER"
}
trap restore EXIT INT TERM

mv "$LIB" "$ASIDE"
for V in $@; do
  zsh "$SP/shoot.sh" "$SP" $V "$SP/${PREFIX}_${V}.png"
done

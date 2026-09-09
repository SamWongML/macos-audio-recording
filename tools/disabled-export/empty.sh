#!/bin/zsh
# THIRD-SWEEP harness (#108). Shoot the empty-Library state, in both appearances.
#
# The empty Library cannot be reached with a full one: `EditorModel.reconcileSelection` selects the
# newest Recording on first open, so *nothing selected* is not a state a fresh launch lands in
# (#111). #106's method: the Library moved aside on the **same volume**, restored in the **same
# shell invocation**, counted both ways. The app recreates the folder empty, so only ever remove
# one that IS empty.
set -e
HERE=${0:a:h}
LIB=$HOME/Music/AppTape
ASIDE=$HOME/Music/AppTape.aside-108
BEFORE=$(ls -1 "$LIB" | wc -l | tr -d ' ')

restore() {
  pkill -f "Release/AppTape.app" 2>/dev/null || true
  sleep 1
  if [[ -d $ASIDE ]]; then
    if [[ -d $LIB ]]; then
      local n=$(ls -1 "$LIB" | wc -l | tr -d ' ')
      if [[ $n == 0 ]]; then rmdir "$LIB"; else echo "REFUSING to remove $LIB — $n files in it"; return; fi
    fi
    mv "$ASIDE" "$LIB"
  fi
  echo "Library restored: $BEFORE -> $(ls -1 "$LIB" | wc -l | tr -d ' ')"
}
trap restore EXIT INT TERM

mv "$LIB" "$ASIDE"
for spec in "$@"; do
  SIZE=${spec%%:*}; rest=${spec#*:}; APP=${rest%%:*}; OUT=${rest#*:}
  zsh "$HERE/launch.sh" $SIZE $APP >/dev/null
  zsh "$HERE/shoot.sh" "$HERE/shots/$OUT"
done

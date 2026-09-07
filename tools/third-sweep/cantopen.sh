#!/bin/zsh
# THIRD-SWEEP harness (#108). Photograph the can't-open branch by putting one undecodable file in
# the Library, newest so `reconcileSelection` selects it on open, and removing it in the same shell
# invocation. #103 added three such fixtures and removed all three; this adds and removes exactly
# one, counted both ways.
set -e
HERE=${0:a:h}
LIB=$HOME/Music/AppTape
FIXTURE="$LIB/Not audio 2099-01-01 at 00.00.00.caf"
BEFORE=$(ls -1 "$LIB" | wc -l | tr -d ' ')
cleanup() {
  pkill -f "Release/AppTape.app" 2>/dev/null || true
  sleep 1
  rm -f "$FIXTURE"
  echo "Library: $BEFORE -> $(ls -1 "$LIB" | wc -l | tr -d ' ')"
}
trap cleanup EXIT INT TERM
printf 'this is not a CAF file, it is 44 bytes of text.' > "$FIXTURE"
for spec in "$@"; do
  SIZE=${spec%%:*}; rest=${spec#*:}; APPEARANCE=${rest%%:*}; OUT=${rest#*:}
  zsh "$HERE/launch.sh" $SIZE $APPEARANCE >/dev/null
  zsh "$HERE/shoot.sh" "$HERE/shots/$OUT"
done

#!/bin/bash
# PROTOTYPE — issue #14, the deny measurement.
#
# Two earlier attempts failed on instrumentation, not on the question:
#   1. Fixed-pace dialogs ran ahead of the human — tccd shows a prompt that was never answered,
#      and Core Audio timed out around it (60s in the IOProc create, then 30s in start).
#   2. The tccd watcher used `grep -A1` on AUTHREQ_PROMPTING, but the AUTHREQ_RESULT lands
#      seconds later with dozens of interleaved lines between. It never matched.
# This version matches AUTHREQ_RESULT on the *msgID* the prompt used, which is exact, and
# runs exactly one prompted run so nothing can desync.
set -uo pipefail
cd "$(dirname "$0")"
HERE="$PWD"; ID=com.samwongml.AppTape.PermProbe; APP="$HERE/build/PermProbe.app"

prompt_msgid() {
  /usr/bin/log show --start "$1" --style compact 2>/dev/null \
    | grep -E "AUTHREQ_PROMPTING.*kTCCServiceAudioCapture.*PermProbe" \
    | grep -oE "msgID=[0-9]+\.[0-9]+" | tail -1
}
result_for() {
  /usr/bin/log show --start "$1" --style compact 2>/dev/null \
    | grep -E "AUTHREQ_RESULT: $2," | grep -oE "authValue=[0-9]" | tail -1
}

tccutil reset AudioCapture "$ID" >/dev/null 2>&1
osascript -e 'display dialog "The system audio permission prompt is about to appear.\n\nClick DON'"'"'T ALLOW on it.\n\n(Not this dialog — the one that appears right after you dismiss this.)" buttons {"I am ready"} default button 1 with title "AppTape permission experiment"' >/dev/null 2>&1

STAMP=$(date "+%Y-%m-%d %H:%M:%S")
open -n "$APP"
CLICK=""
for i in $(seq 1 240); do
  M=$(prompt_msgid "$STAMP")
  if [ -n "$M" ]; then
    V=$(result_for "$STAMP" "$M")
    [ "$V" = "authValue=0" ] && { CLICK=denied; echo "tccd: DENIED after ${i}s (${M})"; break; }
    [ "$V" = "authValue=2" ] && { echo "tccd: ALLOWED after ${i}s (${M}) — wrong button"; exit 2; }
  fi
  sleep 1
done
[ "$CLICK" != "denied" ] && { echo "no deny landed in 240s"; exit 1; }

pkill -f PermProbe >/dev/null 2>&1; sleep 3
BEFORE=$(ls logs/perm-*.txt 2>/dev/null | wc -l | tr -d ' ')
echo; echo "======= MEASUREMENT: settled DENIED — no prompt, no human ======="
open -n "$APP"
for _ in $(seq 1 200); do
  NEW=$(ls -t logs/perm-*.txt 2>/dev/null | head -1)
  if [ -n "$NEW" ] && [ "$(ls logs/perm-*.txt | wc -l | tr -d ' ')" -gt "$BEFORE" ] && grep -q probe.done "$NEW"; then
    cat "$NEW"; break
  fi
  sleep 1
done

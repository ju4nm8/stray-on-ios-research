#!/bin/bash
# Controlled 60s ICU test: launch, hold 60s, SIGKILL, verify termination.
set -u
UDID="<TARGET_DEVICE_UDID>"
BID="com.ju4nm8.strayios"
D="artifacts/logs/icu_test"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$D/launch_icu_console_$TS.log"
JSON="$D/launch_icu_$TS.json"
PROC="$D/processes_at_55s_$TS.log"

xcrun devicectl device process launch --device "$UDID" --console --terminate-existing \
  --timeout 180 --json-output "$JSON" "$BID" > "$LOG" 2>&1 &
LP=$!
echo "launch_pid=$LP log=$LOG"

sleep 55
xcrun devicectl device info processes --device "$UDID" > "$PROC" 2>&1
sleep 5

PID=$(awk '/Stray-Mac-Shipping/{print $1; exit}' "$PROC")
echo "remote_pid=${PID:-none} (at 55s)"
if [ -n "$PID" ]; then
  xcrun devicectl device process terminate --device "$UDID" --pid "$PID" --kill \
    --timeout 30 > "$D/terminate_$TS.log" 2>&1
  echo "terminate_exit=$?"
fi

for i in $(seq 1 25); do kill -0 "$LP" 2>/dev/null || break; sleep 1; done
if kill -0 "$LP" 2>/dev/null; then
  echo "launch_console_still_attached=yes -> killing local client"
  kill "$LP" 2>/dev/null
fi
wait "$LP" 2>/dev/null
echo "launch_console_exit=$?"

sleep 2
xcrun devicectl device info processes --device "$UDID" > "$D/processes_final_$TS.log" 2>&1
if grep -qi "Stray-Mac-Shipping" "$D/processes_final_$TS.log"; then
  echo "FINAL: stray process STILL RUNNING"
else
  echo "FINAL: stray process gone"
fi
echo "RESULT_LOG=$LOG"

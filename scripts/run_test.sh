#!/bin/bash
# Controlled Execution Runner for Stray iOS Test
# Enforces watchdog, log capture, and post-run cleanup verification

set -e

DEVICE_ID="<TARGET_DEVICE_UDID>"
TIMEOUT_SECS=${1:-40}
TEST_ID=${2:-"run_$(date +%Y%m%d_%H%M%S)"}
shift 2 2>/dev/null || true
EXTRA_ARGS=("$@")
LOG_DIR="artifacts/logs/session_20261123"
mkdir -p "$LOG_DIR"

CONSOLE_LOG="$LOG_DIR/${TEST_ID}_console.log"
WATCHDOG_LOG="$LOG_DIR/${TEST_ID}_watchdog.log"
RESULT_LOG="$LOG_DIR/${TEST_ID}_result.log"

echo "=== STRAY TEST RUNNER ===" | tee -a "$RESULT_LOG"
echo "Test ID: $TEST_ID" | tee -a "$RESULT_LOG"
echo "Device: $DEVICE_ID" | tee -a "$RESULT_LOG"
echo "Timeout limit: ${TIMEOUT_SECS}s (Safety limit <= 80s)" | tee -a "$RESULT_LOG"
echo "Extra args: ${EXTRA_ARGS[*]}" | tee -a "$RESULT_LOG"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$RESULT_LOG"

# 1. Verify device is connected
DEV_CHECK=$(xcrun devicectl list devices | grep "$DEVICE_ID" | grep "connected" || true)
if [ -z "$DEV_CHECK" ]; then
    echo "ERROR: Device $DEVICE_ID is NOT connected!" | tee -a "$RESULT_LOG"
    exit 1
fi
echo "Device connection verified: OK" | tee -a "$RESULT_LOG"

# 2. Start Independent Watchdog in background
tools/watchdog_stray.sh "$TIMEOUT_SECS" "$WATCHDOG_LOG" > /dev/null 2>&1 &
WATCHDOG_PID=$!
echo "Independent Watchdog spawned with PID $WATCHDOG_PID" | tee -a "$RESULT_LOG"

# 3. Launch Application with timeout
LAUNCH_START=$(date +%s)
echo "Launching Stray via devicectl..." | tee -a "$RESULT_LOG"

set +e
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    xcrun devicectl device process launch \
        --device "$DEVICE_ID" \
        --console \
        --terminate-existing \
        --timeout 120 \
        com.ju4nm8.strayios -- "${EXTRA_ARGS[@]}" > "$CONSOLE_LOG" 2>&1
else
    xcrun devicectl device process launch \
        --device "$DEVICE_ID" \
        --console \
        --terminate-existing \
        --timeout 120 \
        com.ju4nm8.strayios > "$CONSOLE_LOG" 2>&1
fi
LAUNCH_EXIT=$?
LAUNCH_END=$(date +%s)
LAUNCH_DURATION=$((LAUNCH_END - LAUNCH_START))
set -e

echo "Launch completed with exit code $LAUNCH_EXIT (duration: ${LAUNCH_DURATION}s)" | tee -a "$RESULT_LOG"

# 4. Mandatory Post-Run Cleanup & Verification
echo "Verifying process status on device..." | tee -a "$RESULT_LOG"
sleep 2

LEFTOVER=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search Stray-Mac-Shipping 2>/dev/null | grep "Stray-Mac-Shipping" || true)
if [ -n "$LEFTOVER" ]; then
    echo "WARNING: Leftover process detected: $LEFTOVER" | tee -a "$RESULT_LOG"
    LEFTOVER_PID=$(echo "$LEFTOVER" | awk '{print $1}')
    echo "Force-terminating leftover PID $LEFTOVER_PID with SIGKILL..." | tee -a "$RESULT_LOG"
    xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$LEFTOVER_PID" --kill >> "$RESULT_LOG" 2>&1 || true
    sleep 2
fi

# Final check
FINAL_CHECK=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search Stray-Mac-Shipping 2>/dev/null | grep "Stray-Mac-Shipping" || true)
if [ -z "$FINAL_CHECK" ]; then
    echo "CONFIRMATION: Stray is COMPLETELY CLOSED. No running or suspended process." | tee -a "$RESULT_LOG"
else
    echo "CRITICAL ERROR: Stray process still detected after termination: $FINAL_CHECK" | tee -a "$RESULT_LOG"
    exit 2
fi

echo "=== TEST RUN FINISHED ===" | tee -a "$RESULT_LOG"

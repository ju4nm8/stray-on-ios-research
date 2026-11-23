#!/bin/bash
# Independent Watchdog for Stray iOS
# Enforces maximum execution time (<= 80s) independently of agent process

DEVICE_ID="<TARGET_DEVICE_UDID>"
MAX_SECONDS=${1:-75}
LOG_FILE=${2:-"artifacts/logs/session_20261123/watchdog.log"}

if [ "$MAX_SECONDS" -gt 80 ]; then
    echo "ERROR: MAX_SECONDS ($MAX_SECONDS) cannot exceed 80 seconds under safety rules!" | tee -a "$LOG_FILE"
    MAX_SECONDS=80
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog started. Target device: $DEVICE_ID, Max runtime: ${MAX_SECONDS}s, Log: $LOG_FILE" | tee -a "$LOG_FILE"

PID=""
START_TIME=""
ELAPSED=0

# Phase 1: Wait for process to appear (timeout 60s for launch)
WAIT_START=$(date +%s)
while [ -z "$PID" ]; do
    NOW=$(date +%s)
    if [ $((NOW - WAIT_START)) -gt 60 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: No Stray process appeared within 60s. Exiting." | tee -a "$LOG_FILE"
        exit 0
    fi
    
    # Query running processes
    PROC_LINE=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search Stray-Mac-Shipping 2>/dev/null | grep "Stray-Mac-Shipping" | head -n 1)
    if [ -n "$PROC_LINE" ]; then
        PID=$(echo "$PROC_LINE" | awk '{print $1}')
        if [[ "$PID" =~ ^[0-9]+$ ]]; then
            START_TIME=$(date +%s)
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: Detected Stray-Mac-Shipping PID: $PID" | tee -a "$LOG_FILE"
            break
        fi
        PID=""
    fi
    sleep 1
done

# Phase 2: Monitor running process and enforce time limit
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    
    # Check if process is still running
    CHECK_LINE=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search "$PID" 2>/dev/null | grep "$PID" | head -n 1)
    if [ -z "$CHECK_LINE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: Process $PID exited normally after ${ELAPSED}s." | tee -a "$LOG_FILE"
        exit 0
    fi
    
    if [ "$ELAPSED" -ge "$MAX_SECONDS" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: LIMIT REACHED (${ELAPSED}s >= ${MAX_SECONDS}s). TERMINATING PID $PID..." | tee -a "$LOG_FILE"
        
        # 1. Attempt graceful terminate
        xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$PID" >> "$LOG_FILE" 2>&1
        sleep 2
        
        # 2. Check and force kill if still alive
        CHECK_STILL=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search "$PID" 2>/dev/null | grep "$PID" | head -n 1)
        if [ -n "$CHECK_STILL" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: Process $PID still present. Sending SIGKILL..." | tee -a "$LOG_FILE"
            xcrun devicectl device process terminate --device "$DEVICE_ID" --pid "$PID" --kill >> "$LOG_FILE" 2>&1
            sleep 2
        fi
        
        # 3. Final verification
        FINAL_CHECK=$(xcrun devicectl device info processes --device "$DEVICE_ID" --search "$PID" 2>/dev/null | grep "$PID" | head -n 1)
        if [ -z "$FINAL_CHECK" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: Process $PID successfully terminated." | tee -a "$LOG_FILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: ALERT! Process $PID could not be confirmed terminated: $FINAL_CHECK" | tee -a "$LOG_FILE"
        fi
        exit 0
    fi
    
    sleep 1
done

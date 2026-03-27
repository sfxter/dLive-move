#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/dLive Director V2.11 copy.app/Contents/MacOS/dLive Director V2.11"
LOG="$DIR/movechannel.log"
SHOW_LOG="${MC_SHOW_LOG:-1}"
TAIL_PID=""

cleanup() {
  if [[ -n "$TAIL_PID" ]]; then
    kill "$TAIL_PID" >/dev/null 2>&1 || true
    wait "$TAIL_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT INT TERM

if [[ "$SHOW_LOG" != "0" ]]; then
  touch "$LOG"
  echo "[launch] Following $LOG"
  echo "[launch] Set MC_SHOW_LOG=0 to disable live log output"
  tail -n 0 -F "$LOG" &
  TAIL_PID=$!
fi

DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" "$APP"
exit $?

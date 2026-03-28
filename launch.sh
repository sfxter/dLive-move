#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11"
APP="${DLIVE_APP:-$DEFAULT_APP}"
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

if [[ ! -x "$APP" ]]; then
  echo "[launch] dLive Director binary not found:"
  echo "[launch]   $APP"
  echo "[launch] Set DLIVE_APP to the correct binary path and try again."
  exit 1
fi

if [[ "$SHOW_LOG" != "0" ]]; then
  touch "$LOG"
  echo "[launch] Following $LOG"
  echo "[launch] Set MC_SHOW_LOG=0 to disable live log output"
  tail -n 0 -F "$LOG" &
  TAIL_PID=$!
fi

DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" "$APP"
exit $?

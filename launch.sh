#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11"
APP="${DLIVE_APP:-$DEFAULT_APP}"
LOG="$DIR/movechannel.log"
SHOW_LOG="${MC_SHOW_LOG:-0}"
LOG_LEVEL="${MC_LOG_LEVEL:-1}"
TAIL_PID=""
BASE_TMPDIR="${TMPDIR%/}"
RUN_TMPDIR=""
SAVED_STATE_DIR="$HOME/Library/Saved Application State/com.allen-heath.dLive.Director.savedState"
DIRECTOR_TMP_DIR="$HOME/Library/Application Support/AllenAndHeath/AllenHeath/TLDV2.11/TLDData/Director/Tmp/TempShow"
BOOST_WAVES_DIR="/private/tmp/boost_waves_interprocess"

if [[ -z "$BASE_TMPDIR" ]]; then
  BASE_TMPDIR="/tmp"
fi

cleanup() {
  if [[ -n "$TAIL_PID" ]]; then
    kill "$TAIL_PID" >/dev/null 2>&1 || true
    wait "$TAIL_PID" 2>/dev/null || true
  fi
  if [[ -n "$RUN_TMPDIR" && -d "$RUN_TMPDIR" ]]; then
    rm -rf "$RUN_TMPDIR" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

if [[ ! -x "$APP" ]]; then
  echo "[launch] dLive Director binary not found:"
  echo "[launch]   $APP"
  echo "[launch] Set DLIVE_APP to the correct binary path and try again."
  exit 1
fi

: > "$LOG"
echo "[launch] Writing fresh log to $LOG"

RUN_TMPDIR="$(mktemp -d "${BASE_TMPDIR}/dlive-patch.XXXXXX")"
echo "[launch] Using isolated TMPDIR $RUN_TMPDIR"

if ! pgrep -f "$APP" >/dev/null 2>&1; then
  if [[ -d "$SAVED_STATE_DIR" ]]; then
    echo "[launch] Clearing stale saved state"
    rm -rf "$SAVED_STATE_DIR"
  fi
  if [[ -d "$DIRECTOR_TMP_DIR" ]]; then
    echo "[launch] Clearing Director temp show state"
    rm -rf "$DIRECTOR_TMP_DIR"
  fi
  if [[ -d "$BOOST_WAVES_DIR" ]] && ! lsof +D "$BOOST_WAVES_DIR" >/dev/null 2>&1; then
    echo "[launch] Clearing stale shared-memory files in $BOOST_WAVES_DIR"
    rm -f "$BOOST_WAVES_DIR"/NxSharedMemoryName_v2 \
          "$BOOST_WAVES_DIR"/wvExtMem_SMBR \
          "$BOOST_WAVES_DIR"/wvExtMem_SMNX
  fi
  QT_SINGLETON_FILES=()
  while IFS= read -r singleton_file; do
    QT_SINGLETON_FILES+=("$singleton_file")
  done < <(
    find "$BASE_TMPDIR" -maxdepth 1 \
      \( -name 'qipc_systemsem_dLiveDirectorRunning*' \
         -o -name 'qipc_sharedmemory_dLiveDirectorRunning*' \) \
      -print 2>/dev/null
  )
  if (( ${#QT_SINGLETON_FILES[@]} > 0 )) && ! lsof "${QT_SINGLETON_FILES[@]}" >/dev/null 2>&1; then
    echo "[launch] Clearing stale Qt singleton IPC files in $BASE_TMPDIR"
    rm -f "${QT_SINGLETON_FILES[@]}"
  fi
fi

if [[ "$SHOW_LOG" != "0" ]]; then
  echo "[launch] Following $LOG"
  echo "[launch] Set MC_SHOW_LOG=0 to disable live log output"
  tail -n 0 -F "$LOG" &
  TAIL_PID=$!
else
  echo "[launch] Live log output disabled by default"
  echo "[launch] Set MC_SHOW_LOG=1 to follow the log live"
fi

echo "[launch] Using MC_LOG_LEVEL=$LOG_LEVEL (0=quiet, 1=normal, 2=verbose)"
TMPDIR="$RUN_TMPDIR" MC_LOG_LEVEL="$LOG_LEVEL" DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" "$APP" >>"$LOG" 2>&1
exit $?

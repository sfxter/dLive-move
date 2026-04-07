#!/bin/bash
set -u -o pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11"
SUPPORTED_APPS=(
  "/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11"
  "/Applications/dLive Director V2.12.app/Contents/MacOS/dLive Director V2.12"
)
APP=""
LOG="$DIR/movechannel.log"
SHOW_LOG="${MC_SHOW_LOG:-0}"
LOG_LEVEL="${MC_LOG_LEVEL:-1}"
FILTER_SOCKET_TYPE_ERRORS="${MC_FILTER_SOCKET_TYPE_ERRORS:-1}"
TAIL_PID=""
BASE_TMPDIR="${TMPDIR%/}"
RUN_TMPDIR=""
SAVED_STATE_DIR="$HOME/Library/Saved Application State/com.allen-heath.dLive.Director.savedState"
DIRECTOR_TMP_DIR=""
BOOST_WAVES_DIR="/private/tmp/boost_waves_interprocess"

director_version_for_app() {
  local app_path="$1"
  local app_name
  app_name="$(basename "$app_path")"
  if [[ "$app_name" =~ V([0-9]+\.[0-9]+)$ ]]; then
    printf 'V%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  local bundle_name
  bundle_name="$(basename "$(dirname "$(dirname "$app_path")")")"
  if [[ "$bundle_name" =~ V([0-9]+\.[0-9]+)\.app$ ]]; then
    printf 'V%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

director_tmp_dir_for_app() {
  local app_path="$1"
  local version
  if ! version="$(director_version_for_app "$app_path")"; then
    return 1
  fi

  printf '%s\n' "$HOME/Library/Application Support/AllenAndHeath/AllenHeath/TLD${version}/TLDData/Director/Tmp/TempShow"
}

pick_supported_app() {
  local discovered=()
  local labels=()

  for candidate in "${SUPPORTED_APPS[@]}"; do
    if [[ -x "$candidate" ]]; then
      discovered+=("$candidate")
      if version="$(director_version_for_app "$candidate")"; then
        labels+=("$version")
      else
        labels+=("$(basename "$candidate")")
      fi
    fi
  done

  if (( ${#discovered[@]} == 0 )); then
    APP="$DEFAULT_APP"
    return 0
  fi

  if (( ${#discovered[@]} == 1 )); then
    APP="${discovered[0]}"
    return 0
  fi

  if [[ -n "${MC_SKIP_VERSION_PICKER:-}" ]]; then
    APP="${discovered[0]}"
    return 0
  fi

  if command -v osascript >/dev/null 2>&1; then
    local apple_list=""
    local i
    for (( i=0; i<${#labels[@]}; i++ )); do
      if (( i > 0 )); then
        apple_list+=", "
      fi
      apple_list+="\"${labels[i]}\""
    done

    local selected=""
    selected="$(osascript <<EOF 2>/dev/null
set choices to {${apple_list}}
set picked to choose from list choices with title "dLive Patch" with prompt "Choose which supported dLive Director version to launch with the patch:" default items {(item 1 of choices)} OK button name "Launch" cancel button name "Cancel"
if picked is false then
  return ""
end if
return item 1 of picked
EOF
)"
    if [[ -z "$selected" ]]; then
      echo "[launch] Launch cancelled."
      exit 1
    fi

    for (( i=0; i<${#labels[@]}; i++ )); do
      if [[ "${labels[i]}" == "$selected" ]]; then
        APP="${discovered[i]}"
        return 0
      fi
    done
  fi

  echo "[launch] Multiple supported Director versions were found:"
  local i
  for (( i=0; i<${#discovered[@]}; i++ )); do
    echo "[launch]   $((i + 1)). ${labels[i]} -> ${discovered[i]}"
  done
  echo -n "[launch] Select version [1-${#discovered[@]}]: "
  local selection=""
  read -r selection
  if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#discovered[@]} )); then
    echo "[launch] Invalid selection."
    exit 1
  fi
  APP="${discovered[selection - 1]}"
}

if [[ -n "${DLIVE_APP:-}" ]]; then
  APP="$DLIVE_APP"
else
  pick_supported_app
fi

if [[ -z "$APP" ]]; then
  APP="$DEFAULT_APP"
fi

if ! DIRECTOR_TMP_DIR="$(director_tmp_dir_for_app "$APP")"; then
  DIRECTOR_TMP_DIR="$HOME/Library/Application Support/AllenAndHeath/AllenHeath/TLDV2.11/TLDData/Director/Tmp/TempShow"
fi

running_director_pids() {
  ps -axo pid=,stat=,command= \
    | awk -v app="$APP" '
        index($0, app) {
          pid = $1
          stat = $2
          if (stat ~ /^UE/ || stat ~ /^Z/)
            next
          if (pid != "")
            print pid
        }
      '
}

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

if [[ -z "$(running_director_pids)" ]]; then
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
    find "$BASE_TMPDIR" -maxdepth 2 \
      \( -name 'qipc_systemsem_dLiveDirectorRunning*' \
         -o -name 'qipc_sharedmemory_dLiveDirectorRunning*' \) \
      -print 2>/dev/null
  )
  if (( ${#QT_SINGLETON_FILES[@]} > 0 )) && ! lsof "${QT_SINGLETON_FILES[@]}" >/dev/null 2>&1; then
    echo "[launch] Clearing stale Qt singleton IPC files in $BASE_TMPDIR"
    rm -f "${QT_SINGLETON_FILES[@]}"
  fi
  OLD_PATCH_TMP_DIRS=()
  while IFS= read -r patch_tmp; do
    OLD_PATCH_TMP_DIRS+=("$patch_tmp")
  done < <(
    find "$BASE_TMPDIR" -maxdepth 1 -type d -name 'dlive-patch.*' -print 2>/dev/null
  )
  if (( ${#OLD_PATCH_TMP_DIRS[@]} > 0 )); then
    echo "[launch] Clearing stale dLive patch temp dirs in $BASE_TMPDIR"
    rm -rf "${OLD_PATCH_TMP_DIRS[@]}" >/dev/null 2>&1 || true
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
if [[ "$FILTER_SOCKET_TYPE_ERRORS" != "0" ]]; then
  echo "[launch] Filtering known harmless Director log noise: Unhandled Socket Type"
  TMPDIR="$RUN_TMPDIR" MC_LOG_LEVEL="$LOG_LEVEL" DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" "$APP" 2>&1 \
    | awk 'index($0, "ERROR: Unhandled Socket Type") == 0 { print }' >>"$LOG"
  exit ${PIPESTATUS[0]}
else
  TMPDIR="$RUN_TMPDIR" MC_LOG_LEVEL="$LOG_LEVEL" DYLD_INSERT_LIBRARIES="$DIR/libmovechannel.dylib" "$APP" >>"$LOG" 2>&1
  exit $?
fi

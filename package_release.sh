#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT/dist"
PKG_NAME="dLive-move-patch-beta"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$DIST_DIR/$PKG_NAME-$STAMP"
ZIP_PATH="$DIST_DIR/$PKG_NAME-$STAMP.zip"
LATEST_DIR="$DIST_DIR/$PKG_NAME-latest"
LATEST_ZIP="$DIST_DIR/$PKG_NAME-latest.zip"
DEFAULT_SIGN_ID="Developer ID Application: KAZYS RISKUS (X8345YNH39)"
SIGN_ID="${SIGN_ID:-$DEFAULT_SIGN_ID}"

pick_sign_mode() {
  if [[ "${SIGN_ID:-}" == "-" ]]; then
    echo "adhoc"
    return 0
  fi

  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGN_ID"; then
    echo "developer_id"
    return 0
  fi

  echo "adhoc"
}

codesign_file() {
  local target="$1"
  local mode="$2"
  if [[ "$mode" == "developer_id" ]]; then
    codesign --force --sign "$SIGN_ID" --timestamp "$target"
  else
    codesign --force --sign - "$target"
  fi
}

mkdir -p "$OUT_DIR"

echo "[package] Building plugin"
make -C "$ROOT"

echo "[package] Generating app icon"
if "$ROOT/tools/generate_app_icon.py" >/dev/null 2>&1; then
  if ! /usr/bin/iconutil -c icns "$ROOT/assets/StartPatcheddLive.iconset" -o "$ROOT/assets/StartPatcheddLive.icns"; then
    echo "[package] (iconutil failed; using existing $ROOT/assets/StartPatcheddLive.icns)"
  fi
else
  echo "[package] (skipping icon regeneration; using existing $ROOT/assets/StartPatcheddLive.icns)"
fi

echo "[package] Preparing release folder: $OUT_DIR"
cp "$ROOT/libmovechannel.dylib" "$OUT_DIR/"
cp "$ROOT/launch.sh" "$OUT_DIR/_launch_internal.sh"

cat >"$OUT_DIR/Start Patched dLive.command" <<'EOF'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
MC_SHOW_LOG="${MC_SHOW_LOG:-0}" ./_launch_internal.sh
EOF

cat >"$OUT_DIR/Open Patch Log.command" <<'EOF'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
open -a Terminal "$DIR/movechannel.log"
EOF

cat >"$OUT_DIR/Remove Quarantine.command" <<'EOF'
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/xattr -dr com.apple.quarantine "$DIR" || true
/usr/bin/osascript -e 'display dialog "Quarantine attributes removed from this patch folder." buttons {"OK"} default button "OK"'
EOF

cat >"$OUT_DIR/Prepare Director For Patch.command" <<'EOF'
#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SUPPORTED_BUNDLES=(
  "/Applications/dLive Director V2.11.app"
  "/Applications/dLive Director V2.12.app"
)

pick_app_bundle() {
  local discovered=()
  local labels=()
  local bundle

  for bundle in "${SUPPORTED_BUNDLES[@]}"; do
    if [[ -d "$bundle" ]]; then
      discovered+=("$bundle")
      labels+=("$(basename "$bundle" .app)")
    fi
  done

  if (( ${#discovered[@]} == 0 )); then
    return 1
  fi

  if (( ${#discovered[@]} == 1 )); then
    printf '%s\n' "${discovered[0]}"
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
    selected="$(osascript <<OSA 2>/dev/null
set choices to {${apple_list}}
set picked to choose from list choices with title "Prepare Director For Patch" with prompt "Choose which supported dLive Director app to re-sign for the patch:" default items {(item 1 of choices)} OK button name "Continue" cancel button name "Cancel"
if picked is false then
  return ""
end if
return item 1 of picked
OSA
)"
    if [[ -n "$selected" ]]; then
      for (( i=0; i<${#labels[@]}; i++ )); do
        if [[ "${labels[i]}" == "$selected" ]]; then
          printf '%s\n' "${discovered[i]}"
          return 0
        fi
      done
    fi
  fi

  printf '%s\n' "${discovered[0]}"
}

APP_BUNDLE="${DLIVE_APP_BUNDLE:-}"
if [[ -z "$APP_BUNDLE" ]]; then
  APP_BUNDLE="$(pick_app_bundle || true)"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  /usr/bin/osascript <<OSA
display dialog "Could not find a supported dLive Director app to prepare.\n\nIf your app is installed somewhere else, run this command from Terminal with:\nDLIVE_APP_BUNDLE=\"/path/to/dLive Director V2.11.app\" ./Prepare Director For Patch.command\n\nor\n\nDLIVE_APP_BUNDLE=\"/path/to/dLive Director V2.12.app\" ./Prepare Director For Patch.command" buttons {"OK"} default button "OK" with icon caution
OSA
  exit 1
fi

/usr/bin/osascript <<OSA
display dialog "This helper will do 2 things:\n\n1. Remove quarantine from this patch folder\n2. Open Terminal and run the required sudo commands to re-sign your local dLive Director app with an ad-hoc signature so the community patch can be injected on Macs that block the stock signed app\n\nApp to modify:\n$APP_BUNDLE\n\nThis changes the code signature of your local Director install. If you want to undo it later, reinstall Director.\n\nTerminal will open and ask for an administrator password.\n\nContinue?" buttons {"Cancel", "Continue"} default button "Continue" with icon caution
OSA

/usr/bin/xattr -dr com.apple.quarantine "$DIR" >/dev/null 2>&1 || true

TMP_SCRIPT="$(mktemp /tmp/dlive-prepare-director.XXXXXX.sh)"
cat >"$TMP_SCRIPT" <<EOS
#!/bin/bash
set -euo pipefail
trap 'rm -f "$0"' EXIT
clear
echo "Preparing Director for patch:"
echo "  $APP_BUNDLE"
echo
echo "You may be asked for your administrator password."
echo
sudo /usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" || true
sudo /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
echo
echo "Director is now prepared for the patch."
echo "You can close this Terminal window and launch the patch normally."
EOS
chmod 700 "$TMP_SCRIPT"

if ! /usr/bin/osascript <<OSA
tell application "Terminal"
  activate
  do script quoted form of POSIX path of "$TMP_SCRIPT"
end tell
OSA
then
  /usr/bin/osascript <<OSA
display dialog "Could not open Terminal for the preparation step.\n\nPlease make sure Terminal is available on this Mac and try again." buttons {"OK"} default button "OK" with icon caution
OSA
  exit 1
fi
EOF

cat >"$OUT_DIR/README.txt" <<'EOF'
dLive Move Patch BETA
=====================

What is included
- libmovechannel.dylib
- Start Patched dLive.command
- Start Patched dLive.app
- Open Patch Log.command
- Remove Quarantine.command
- Prepare Director For Patch.command

What the target Mac needs
- dLive Director V2.11.app or dLive Director V2.12.app
- No LLDB is needed at runtime
- No Homebrew Qt is needed at runtime

Why no extra libraries are needed
- The plugin links to Qt via @rpath
- At runtime it uses the Qt frameworks already bundled inside the dLive Director app

Important runtime requirements
- The plugin is x86_64
- The target Director binary must also be x86_64-compatible
- On Apple Silicon, Rosetta may be required if the Director app runs under Rosetta

How to run
1. Put this folder anywhere on the target Mac.
2. First launch only:
   right-click `Remove Quarantine.command` and choose `Open`
3. Then:
   right-click `Start Patched dLive.app` and choose `Open`
4. If Finder still warns later, use the same right-click `Open` flow again.
5. If Director starts but the patch does not load on this Mac, run:
   `Prepare Director For Patch.command`
   If macOS blocks that helper on first open, go to System Settings -> Privacy & Security
   and press Open Anyway for the blocked helper, then run it again.
6. If both supported Director versions are installed, the launcher will ask which one to start.

Alternative launchers
- Double-click `Start Patched dLive.command`

If macOS blocks the app
- Use `Remove Quarantine.command`
- Then launch `Start Patched dLive.app` with right-click `Open`

If Director opens but the patch still does not load
- Run `Prepare Director For Patch.command`
- If macOS blocks that helper, go to `System Settings -> Privacy & Security`
- Press `Open Anyway` for the blocked helper, then run it again
- This helper re-signs your local Director app with an ad-hoc signature
- It is an opt-in workaround for Macs that refuse third-party dylib injection into the stock signed app
- If you want to undo it later, reinstall Director

Changing the app path
- If needed, edit `_launch_internal.sh` so `DLIVE_APP` points to the correct dLive Director app.

Alternative app path
- You can override the app path without editing the script:
  DLIVE_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" ./_launch_internal.sh
  or
  DLIVE_APP="/Applications/dLive Director V2.12.app/Contents/MacOS/dLive Director V2.12" ./_launch_internal.sh

If macOS blocks the files
- Remove quarantine from the extracted folder:
  xattr -dr com.apple.quarantine .

Notes
- Beta release
- Adds support for dLive Director V2.12
- Tested offline; to be tested online
- Fixed mix copy/paste with Cmd+C / Cmd+V
- The launcher app and plugin are Developer ID signed during packaging.
- This package is not notarized.
- If the target Mac has a different Director app name/path, update DLIVE_APP.
- `Start Patched dLive.app` launches with log tailing disabled, so it behaves like a normal app.
EOF

cp "$ROOT/README.md" "$OUT_DIR/PROJECT_README.md"
cp "$ROOT/DISCLAIMER.md" "$OUT_DIR/DISCLAIMER.md"
cp "$ROOT/docs/RELEASE_NOTES_2026-04-07.md" "$OUT_DIR/RELEASE_NOTES.txt"

chmod +x "$OUT_DIR/_launch_internal.sh"
chmod +x "$OUT_DIR/Start Patched dLive.command"
chmod +x "$OUT_DIR/Open Patch Log.command"
chmod +x "$OUT_DIR/Remove Quarantine.command"
chmod +x "$OUT_DIR/Prepare Director For Patch.command"

echo "[package] Building native macOS app launcher"
APP_DIR="$OUT_DIR/Start Patched dLive.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RES_DIR="$APP_CONTENTS/Resources"
mkdir -p "$APP_MACOS" "$APP_RES_DIR"

cat >"$APP_CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Start Patched dLive</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.sfxter.dlive-move.launcher</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Start Patched dLive</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

clang -arch arm64 -arch x86_64 \
  -framework Foundation \
  -framework CoreFoundation \
  "$ROOT/tools/launcher_main.m" \
  -o "$APP_MACOS/Start Patched dLive"
chmod +x "$APP_MACOS/Start Patched dLive"

cp "$OUT_DIR/libmovechannel.dylib" "$APP_RES_DIR/libmovechannel.dylib"
cp "$OUT_DIR/_launch_internal.sh" "$APP_RES_DIR/_launch_internal.sh"
cp "$ROOT/assets/StartPatcheddLive.icns" "$APP_RES_DIR/AppIcon.icns"
chmod +x "$APP_RES_DIR/_launch_internal.sh"

SIGN_MODE="$(pick_sign_mode)"
if [[ "$SIGN_MODE" == "developer_id" ]]; then
  echo "[package] Signing with Developer ID: $SIGN_ID"
else
  echo "[package] Developer ID identity not available; using ad-hoc signing"
fi
codesign_file "$APP_RES_DIR/libmovechannel.dylib" "$SIGN_MODE"
codesign_file "$OUT_DIR/libmovechannel.dylib" "$SIGN_MODE"
codesign_file "$OUT_DIR/Start Patched dLive.app" "$SIGN_MODE"

echo "[package] Creating zip: $ZIP_PATH"
rm -f "$ZIP_PATH"
(cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$OUT_DIR")" "$(basename "$ZIP_PATH")")

echo "[package] Updating stable latest package"
rm -rf "$LATEST_DIR"
cp -R "$OUT_DIR" "$LATEST_DIR"
rm -f "$LATEST_ZIP"
(cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$LATEST_DIR")" "$(basename "$LATEST_ZIP")")

echo "[package] Done"
echo "[package] Folder: $OUT_DIR"
echo "[package] Zip:    $ZIP_PATH"
echo "[package] Latest folder: $LATEST_DIR"
echo "[package] Latest zip:    $LATEST_ZIP"

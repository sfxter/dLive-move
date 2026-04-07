#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT/dist"
PKG_NAME="dLive-move-patch"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$DIST_DIR/$PKG_NAME-$STAMP"
ZIP_PATH="$DIST_DIR/$PKG_NAME-$STAMP.zip"
LATEST_DIR="$DIST_DIR/$PKG_NAME-latest"
LATEST_ZIP="$DIST_DIR/$PKG_NAME-latest.zip"
DEFAULT_SIGN_ID="Developer ID Application: KAZYS RISKUS (X8345YNH39)"
SIGN_ID="${SIGN_ID:-$DEFAULT_SIGN_ID}"

mkdir -p "$OUT_DIR"

echo "[package] Building plugin"
make -C "$ROOT"

echo "[package] Generating app icon"
if "$ROOT/tools/generate_app_icon.py" >/dev/null 2>&1; then
  /usr/bin/iconutil -c icns "$ROOT/assets/StartPatcheddLive.iconset" -o "$ROOT/assets/StartPatcheddLive.icns"
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
DEFAULT_APP_BUNDLE="/Applications/dLive Director V2.11.app"
APP_BUNDLE="${DLIVE_APP_BUNDLE:-$DEFAULT_APP_BUNDLE}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  /usr/bin/osascript <<OSA
display dialog "Could not find dLive Director at:\n\n$APP_BUNDLE\n\nIf your app is installed somewhere else, run this command from Terminal with:\nDLIVE_APP_BUNDLE=\"/path/to/dLive Director V2.11.app\" ./Prepare Director For Patch.command" buttons {"OK"} default button "OK" with icon caution
OSA
  exit 1
fi

/usr/bin/osascript <<OSA
display dialog "This helper will do 2 things:\n\n1. Remove quarantine from this patch folder\n2. Re-sign your local dLive Director app with an ad-hoc signature so the community patch can be injected on Macs that block the stock signed app\n\nApp to modify:\n$APP_BUNDLE\n\nThis changes the code signature of your local Director install. If you want to undo it later, reinstall Director.\n\nContinue?" buttons {"Cancel", "Continue"} default button "Continue" with icon caution
OSA

/usr/bin/xattr -dr com.apple.quarantine "$DIR" || true
/usr/bin/xattr -dr com.apple.quarantine "$APP_BUNDLE" || true
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

/usr/bin/osascript <<OSA
display dialog "Director is now prepared for the patch.\n\nYou can launch the patch normally with Start Patched dLive.app or Start Patched dLive.command." buttons {"OK"} default button "OK"
OSA
EOF

cat >"$OUT_DIR/README.txt" <<'EOF'
dLive Move Patch
================

What is included
- libmovechannel.dylib
- Start Patched dLive.command
- Start Patched dLive.app
- Open Patch Log.command
- Remove Quarantine.command
- Prepare Director For Patch.command

What the target Mac needs
- dLive Director V2.11.app, or another compatible Director app build
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

Alternative launchers
- Double-click `Start Patched dLive.command`

If macOS blocks the app
- Use `Remove Quarantine.command`
- Then launch `Start Patched dLive.app` with right-click `Open`

If Director opens but the patch still does not load
- Run `Prepare Director For Patch.command`
- This helper re-signs your local Director app with an ad-hoc signature
- It is an opt-in workaround for Macs that refuse third-party dylib injection into the stock signed app
- If you want to undo it later, reinstall Director

Changing the app path
- If needed, edit `_launch_internal.sh` so `DLIVE_APP` points to the correct dLive Director app.

Alternative app path
- You can override the app path without editing the script:
  DLIVE_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" ./_launch_internal.sh

If macOS blocks the files
- Remove quarantine from the extracted folder:
  xattr -dr com.apple.quarantine .

Notes
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

echo "[package] Signing with Developer ID: $SIGN_ID"
codesign --force --sign "$SIGN_ID" --timestamp "$APP_RES_DIR/libmovechannel.dylib"
codesign --force --sign "$SIGN_ID" --timestamp "$OUT_DIR/libmovechannel.dylib"
codesign --force --sign "$SIGN_ID" --timestamp "$OUT_DIR/Start Patched dLive.app"

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

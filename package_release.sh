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

mkdir -p "$OUT_DIR"

echo "[package] Building plugin"
make -C "$ROOT"

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

APPLESCRIPT="$OUT_DIR/Start Patched dLive.applescript"
cat >"$APPLESCRIPT" <<'EOF'
on run
	set appPath to POSIX path of (path to me)
	set pkgDir to do shell script "/usr/bin/dirname " & quoted form of appPath
	set cmd to "cd " & quoted form of pkgDir & " && /usr/bin/env MC_SHOW_LOG=0 ./_launch_internal.sh >/dev/null 2>&1 &"
	do shell script cmd
end run
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
2. Double-click `Start Patched dLive.app`
3. If Finder warns, remove quarantine from the folder and try again.

Alternative launchers
- Double-click `Start Patched dLive.command`

If macOS blocks the app
- Double-click `Remove Quarantine.command`
- Then launch `Start Patched dLive.app` again

Changing the app path
- If needed, edit `_launch_internal.sh` so `DLIVE_APP` points to the correct dLive Director app.

Alternative app path
- You can override the app path without editing the script:
  DLIVE_APP="/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" ./_launch_internal.sh

If macOS blocks the files
- Remove quarantine from the extracted folder:
  xattr -dr com.apple.quarantine .

Notes
- The plugin is ad-hoc signed during packaging.
- If the target Mac has a different Director app name/path, update DLIVE_APP.
- `Start Patched dLive.app` launches with log tailing disabled, so it behaves like a normal app.
EOF

cp "$ROOT/README.md" "$OUT_DIR/PROJECT_README.md"
cp "$ROOT/DISCLAIMER.md" "$OUT_DIR/DISCLAIMER.md"

chmod +x "$OUT_DIR/_launch_internal.sh"
chmod +x "$OUT_DIR/Start Patched dLive.command"
chmod +x "$OUT_DIR/Open Patch Log.command"
chmod +x "$OUT_DIR/Remove Quarantine.command"

echo "[package] Building macOS app launcher"
osacompile -o "$OUT_DIR/Start Patched dLive.app" "$APPLESCRIPT"
rm -f "$APPLESCRIPT"

echo "[package] Ad-hoc signing dylib"
codesign --force --sign - "$OUT_DIR/libmovechannel.dylib"
codesign --force --sign - "$OUT_DIR/Start Patched dLive.app"

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

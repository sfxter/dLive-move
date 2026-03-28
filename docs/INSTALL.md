# Install And Run

## For End Users

1. Download the latest packaged release from `dist/`.
2. Unzip it.
3. If macOS blocks it, double-click `Remove Quarantine.command`.
4. Double-click `Start Patched dLive.app`.

## If The App Path Is Different

The packaged launcher expects:

`/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11`

If your app is somewhere else, edit `_launch_internal.sh` inside the packaged folder and set `DLIVE_APP` to the correct binary path.

## Notes

- The patch launches your installed Director app with `DYLD_INSERT_LIBRARIES`
- No LLDB is required for normal use
- The packaged launcher disables live log tailing by default so it behaves more like a normal app

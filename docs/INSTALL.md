# Install And Run

## For End Users

1. Download the latest packaged release from `dist/`.
2. Unzip it.
3. First launch only:
   right-click `Remove Quarantine.command` and choose `Open`.
4. Then:
   right-click `Start Patched dLive.app` and choose `Open`.
5. If macOS still blocks the launcher later, use the same right-click `Open` action again.

## If The App Path Is Different

The packaged launcher expects:

`/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11`

If your app is somewhere else, edit `_launch_internal.sh` inside the packaged folder and set `DLIVE_APP` to the correct binary path.

## Notes

- The patch launches your installed Director app with `DYLD_INSERT_LIBRARIES`
- No LLDB is required for normal use
- The packaged launcher disables live log tailing by default so it behaves more like a normal app

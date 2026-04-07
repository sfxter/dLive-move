# Install And Run

## For End Users

1. Download the latest packaged release from `dist/`.
2. Unzip it.
3. First launch only:
   right-click `Remove Quarantine.command` and choose `Open`.
4. Then:
   right-click `Start Patched dLive.app` and choose `Open`.
5. If macOS still blocks the launcher later, use the same right-click `Open` action again.
6. If Director starts but the patch still does not load, run:
   `Prepare Director For Patch.command`
7. If both supported Director versions are installed, the launcher will ask which one to start.

## If The App Path Is Different

The packaged launcher supports:

- `/Applications/dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11`
- `/Applications/dLive Director V2.12.app/Contents/MacOS/dLive Director V2.12`

If your app is somewhere else, edit `_launch_internal.sh` inside the packaged folder and set `DLIVE_APP` to the correct binary path.

## Notes

- The patch launches your installed Director app with `DYLD_INSERT_LIBRARIES`
- No LLDB is required for normal use
- The packaged launcher disables live log tailing by default so it behaves more like a normal app
- On some Macs, the stock signed Director app refuses third-party dylib injection even after quarantine removal
- `Prepare Director For Patch.command` is an opt-in workaround for that case
- It now supports both `dLive Director V2.11.app` and `dLive Director V2.12.app`
- It opens Terminal and runs the required `sudo` commands there
- Terminal may ask for an administrator password because it modifies the app inside `/Applications`
- It re-signs the user's local Director app with an ad-hoc signature
- If the user wants to undo that change later, the safe path is reinstalling Director

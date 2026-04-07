# dLive Move Patch

Date: 2026-04-07

Maintenance release focused on stereo channel moves and insert state preservation.

## What's New

- Fixed stale preamp gain values left behind in the UI after stereo channel moves.
  Moving a stereo pair could leave the wrong analogue gain shown on the destination
  channels until the next reload. The plugin now reapplies the full input stereo
  configuration through the same path Director itself uses, so preamp gain, pad and
  phantom always match the moved channel immediately.
- Insert bypass state is now carried with the channel when moving.
  Previously the Insert A / Insert B `BYPASS` toggle would stay on the source slot
  while the rest of the insert routing followed the channel. Bypass is now snapshot
  and restored through the high-level insert path, so UI, FPGA and scene state all
  agree after a move.

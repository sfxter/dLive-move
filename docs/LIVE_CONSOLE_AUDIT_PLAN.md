# Live Console Audit Plan

This file is the current working snapshot of what has been hardened for live-console use, what has been verified, and what still needs focused testing.

## Status Markers

- `[x]` implemented and verified
- `[-]` implemented, but still needs a focused live check
- `[ ]` not yet hardened

## Confirmed Root Cause Pattern

The main failure pattern we uncovered was:

1. channel state was restored locally with `safeWrite(...)` or direct object mutation
2. Director's editor view updated
3. the live console did not always receive an authoritative update

That pattern was confirmed first on DCA replay, then again on mixer state and proc order.

## Confirmed Live Results

- [x] DCA replay
- [x] Main LR / main mono routing
- [x] Main gain
- [x] Main mute
- [x] Main pan / image sync
- [x] Aux on/off
- [x] Aux gain
- [x] Aux pre/post
- [x] Aux pan
- [x] Matrix on/off
- [x] Matrix pre/post
- [x] Matrix gain
- [x] Matrix pan
- [x] Proc order
- [x] Mute-group assignments
- [x] Gang-linked parameter behavior
- [x] True socket-backed analogue preamp gain
- [x] True socket-backed analogue preamp pad
- [x] True socket-backed analogue preamp polarity
- [x] Input `Cmd+C` / `Cmd+V` works offline
- [x] Input `Cmd+C` / `Cmd+V` works online

## Confirmed Offline Results Still Worth Live Spot Checks

- [-] Regular sidechain restore
- [-] Dyn8 insert sidechain source remap after moving the source channel
- [-] Stereo Image `mode`
- [-] Stereo Image `width`

These paths now have explicit replay/readback handling and pass focused offline tests, but they should still be sanity-checked on the live console.

## Current Feature Coverage

### Reorder / Move

- [x] Type A processing blocks
  - DigiTube
  - HPF
  - LPF
  - Compressor
  - Gate SC/PEQ
  - Gate
  - PEQ
- [x] Type B processing blocks
  - Digital Trim
  - Delay
  - Proc Order
  - Stereo Image
  - SideChain1 / SideChain2
- [x] Mixer state replay
  - main routing
  - main gain
  - main mute
  - main pan / image
  - aux sends
  - matrix sends
  - DCA
  - mute groups
- [x] Patch replay
- [x] ABCD / active input handling
- [x] Dyn8 insert assignment and Dyn8 data replay
- [x] Input gang membership restore
- [x] Stereo / mono move handling

### Copy / Paste

- [x] Input `Cmd+C` / `Cmd+V` custom full-strip copy path
- [x] Aux `Cmd+C` / `Cmd+V` built-in Copy Mix / Paste Mix path
- [x] Dyn8 mono copy/paste
- [x] Dyn8 stereo copy/paste

Input copy/paste intentionally includes:

- strip processing
- mixer state
- mute groups
- preamp values on the target's existing valid socket-backed source
- Dyn8 inserts and Dyn8 data

Input copy/paste intentionally excludes:

- patch assignment
- ABCD socket/source assignment
- preamp socket reassignment
- non-Dyn8 external / rack inserts

## Important Handling Rules

### MixRack I/O Port

- [x] MixRack I/O Port is treated as channel trim / polarity territory, not as analogue preamp state
- [x] gain / pad / phantom are no longer treated as valid movable preamp values for MixRack I/O Port

### Non-Dyn8 Inserts

- [x] External / rack inserts are intentionally not copied by input `Cmd+C` / `Cmd+V`
- [x] Dyn8 inserts are the only insert type explicitly preserved by input copy/paste

## Known Issues / Notes

- [x] Wrong DCA-on-console issue was fixed by moving final replay onto the wrapper MIDI path and replaying the final clear state for all moved targets.
- [x] Earlier wrong trim on `Guest` / `Guest mo` was traced to source state already being dirty at snapshot time, not to trim remapping during move.
- [x] Copy/paste online instability was traced to the native mac shortcut monitor. `Cmd+C` / `Cmd+V` now rely on the Qt shortcut/global-filter path instead.
- [x] Online lag seen while connected to the console is not currently treated as a plugin bug. The same lag reproduces in stock Director without the plugin loaded.

## Remaining Focused Live Tests

These are the most useful spot checks to run on the next live session:

1. Dyn8 sidechain source after moving the source channel
2. Regular compressor/gate sidechain source after move
3. Stereo Image `mode`
4. Stereo Image `width`

## Release Readiness Summary

For the current local test build:

- [x] good candidate for another-machine testing
- [x] no publishing needed yet
- [x] package should be treated as a local validation build, not a public release

## Working Assumption

Any future restore path that depends mainly on raw `safeWrite(...)` into live objects should still be treated as suspicious until it has either:

1. an explicit wrapper / task / setter replay path, or
2. a focused live-console verification result

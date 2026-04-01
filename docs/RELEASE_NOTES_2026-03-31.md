# dLive Move Patch

Date: 2026-04-01

This release adds a full Channel Reorder workflow alongside the move and copy/paste improvements.

## What Changed

- Added a Channel Reorder Panel:
  - open it from the new `Reorder` button in the top bar
  - drag channels into their final order
  - press `Apply` to move channel settings into the new layout
  - stereo pairs stay protected and invalid layouts are blocked before apply
  - manual main-patch overrides remain available inside the panel
- Improved the Channel Reorder Panel UX:
  - dragged rows are ghosted while moving
  - the drop target now shows a full-width insertion marker
- Hardened live-console replay for major mixer state:
  - main routing
  - main gain
  - main mute
  - main pan / image sync
  - aux on/off, gain, pre/post, pan
  - matrix on/off, pre/post, gain, pan
  - DCA
- Fixed proc-order replay so the live console now follows the moved channel.
- Added explicit mute-group replay support and verified it live.
- Hardened copy/paste for input channels so `Cmd+C` / `Cmd+V` now copies full strip state under plugin control instead of relying on Director's built-in input copy.
- Added Dyn8-aware copy/paste for mono and stereo cases.
- Fixed online copy/paste instability by removing native mac `Cmd+C` / `Cmd+V` handling and keeping those shortcuts on the Qt path.
- Fixed a startup crash that could happen when Director showed the system-selection popup and startup initialization was delayed.
- Hardened preamp handling:
  - true socket-backed analogue gain / pad / polarity verified live
  - MixRack I/O Port no longer treated as analogue preamp state
- Added stronger offline replay for:
  - regular sidechains
  - Dyn8 sidechain source remap
  - Stereo Image mode / width
- Added `Prepare Director For Patch.command` as an explicit opt-in helper for Macs that refuse to load the patch into the stock signed Director app:
  - removes quarantine from the patch folder
  - re-signs the user's local Director app with an ad-hoc signature
  - intended only for Macs where Director opens but the patch does not load

## What Input Copy/Paste Includes

- strip processing
- mixer state
- mute groups
- preamp values on the target's existing valid analogue source
- Dyn8 inserts and Dyn8 data

## What Input Copy/Paste Still Excludes

- patch assignment
- ABCD source / socket assignment
- preamp socket reassignment
- non-Dyn8 external / rack inserts

## Known Notes

- Online lag seen with a live console connected is not currently blamed on the plugin. The same lag reproduces in stock Director without the plugin loaded.
- The most valuable remaining live spot checks are:
  - Dyn8 sidechain source after moving the source channel
  - regular sidechain source after move
  - Stereo Image mode / width

# dLive Move Patch

Unofficial community patch for `dLive Director V2.11` on macOS.

This project adds quality-of-life features to the dLive offline editor, with the main focus on moving channel data safely across mono and stereo layouts.

## What It Does

- Moves mono channels safely
- Moves stereo channels as stereo blocks
- Moves larger channel blocks while protecting stereo pairs
- Preserves most channel processing and routing state during moves
- Handles many difficult cases such as:
  - Dyn8 reassignment
  - ABCD / redundant source setup
  - sidechain source remap
  - ganging
  - preamp socket move / shift behavior

It also includes extra usability features:

- `Cmd+Shift+M` opens the move dialog on macOS
- `Cmd+C` / `Cmd+V` copies and pastes input channel settings
- `Cmd+C` / `Cmd+V` uses built-in `Copy Mix` / `Paste Mix` when an Aux is selected

## Important

This is an unofficial patch. It is not affiliated with or endorsed by Allen & Heath or Apple.

Read [DISCLAIMER.md](/Users/sfx/Programavimas/dLive-patch/DISCLAIMER.md) before sharing or using it.

## Quick Start

For most users, use the packaged build in [`dist/`](./dist):

- unzip the latest package
- if macOS blocks it, run `Remove Quarantine.command`
- launch `Start Patched dLive.app`

The package is built by:

```bash
./package_release.sh
```

That script produces:

- a Finder-friendly launcher app
- a command-line fallback launcher
- a packaged zip in `dist/`

## Repo Layout

- [`src/plugin_main.mm`](/Users/sfx/Programavimas/dLive-patch/src/plugin_main.mm): main patch implementation
- [`package_release.sh`](/Users/sfx/Programavimas/dLive-patch/package_release.sh): creates a shareable package
- [`Makefile`](/Users/sfx/Programavimas/dLive-patch/Makefile): builds the injected dylib
- [`docs/`](./docs): install and sharing documentation

## Requirements

- macOS
- a user-installed copy of `dLive Director V2.11`
- compatible `x86_64` runtime setup

No LLDB is required for normal use.

## Building

```bash
make
```

## Packaging

```bash
./package_release.sh
```

The release package is designed so end users do not need Terminal for normal launching.

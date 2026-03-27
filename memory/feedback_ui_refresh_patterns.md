---
name: UI refresh patterns — what works, what doesn't, and why
description: Master guide for refreshing dLive Director UI after writing data. Covers all discovered patterns and the key lesson about using existing app code paths.
type: feedback
---

# UI Refresh in dLive Director — Master Guide

## The #1 Rule: Use the App's Own Code Paths

**Before trying low-level notification methods, find how the app itself does the same operation** (scene recall, CSV import, MIDI handler, etc.) and call that same function. This is ALWAYS faster and more reliable than trying to reverse-engineer notification chains.

Every time we tried to shortcut around the app's systems (direct array writes + manual notifications), we burned tokens and failed. Every time we found the app's own function for the operation, it worked immediately.

## Pattern Hierarchy (try in this order)

### 1. HIGH-LEVEL: Call the app's own API function (BEST)
Find the function the app uses for the same operation and call it directly.

**Examples that worked immediately:**
- **Patching (socket assignment):** `cChannel::SetInputChannelSource()` at `0x1006d8410` — same path as CSV Import. Handles cChannelMapper arrays + UI refresh + preamp association in one call.
- **Preamp gain:** `MIDISetGain()` at `0x1004ecf80` — same as MIDI handler. Writes value + calls InformOtherObjects.
- **Delay:** `SetDelayAndInformOthers()` at `0x100202590` — single call writes field + notifies UI.
- **Type A processors:** `DirectlyRecallStatus()` + `ReportData()` — same as scene recall.

**How to find these:** `nm -C binary | grep ClassName` → look for Set*, MIDI*, Inform*, Apply* methods.

### 2. MID-LEVEL: Write fields + InformObjectsOfNewSettings() (Type B objects)
For per-channel net objects where no high-level setter exists.

**Works for:** cDigitalAttenuator (trim/mute/polarity)
**Pattern:** `writeTypeBFields(obj, desc, buf)` → `InformObjectsOfNewSettings(obj)` at `0x1002046d0`
**Why it works:** Reads current field values from the object and pushes to UI chain. No FPGA/network involvement.

### 3. LOW-LEVEL: Write fields + InformOtherObjects (limited)
Only works when dependent objects read from the source object's fields, not from FPGA.

**Works for:** Sidechain (with embedded message at obj+0x60)
**Fails for:** DigitalAttenuator (dependents re-read from FPGA → returns -24.0 offline)

## What NEVER Works

| Approach | Why it fails |
|----------|-------------|
| Direct array writes only | Data written but UI never learns about it |
| `InformOtherObjects` on global objects (cChannelMapper) | UI widgets don't subscribe to these notifications |
| Writing to internal arrays + `ActionTick()` | ActionTick processes dirty flags but doesn't trigger UI widget refresh |
| `ConfigurePatchBay()` + any notification | Updates internal routing but UI doesn't refresh |
| Casting non-QObject drivers to QObject | Crash — most drivers are NOT QObjects |

## Key Lesson: Patching (cChannelMapper) Failure Analysis

**What we tried (all failed):**
1. `writePatchData()` → data written, no UI refresh
2. `writePatchData()` + `InformObjectsOfChannelPatch()` → no refresh
3. `ConfigurePatchBay()` + `InformObjectsOfChannelPatch()` → no refresh
4. `ConfigurePatchBay()` + `ActionTick()` → no refresh

**What worked immediately:** `cChannel::SetInputChannelSource()` — the same function CSV Import uses. Found by disassembling `cImportDataManager::SendChannelInputPatch()`.

**Why the low-level approaches failed:** `cChannelMapper` is a single global object. Its `InformOtherObjects` notifies dependent *net objects*, but the UI patching widgets subscribe to `cChannel`-level task notifications, not to `cChannelMapper` messages. The only way to refresh the patching UI is to go through the `cChannel` task system.

**Bonus discovery:** `SetInputChannelSource` also moves preamp settings (gain/pad/phantom) with the socket — so when using it in Scenario B, you must SKIP separate preamp writes to avoid double-move.

## Finding the Right Function: Checklist

1. **What app feature does the same thing?** (CSV import, scene recall, MIDI, surface control)
2. `nm -C binary | grep FeatureClassName` — find the class
3. Look for `Set*`, `Apply*`, `MIDI*`, `Send*`, `Import*` methods
4. Disassemble the app's handler for that feature to find the call chain
5. Cache any singleton pointers at init time (cUIManagerHolder::Instance(), etc.)

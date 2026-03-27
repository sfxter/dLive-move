---
name: Dyn8 settings transfer — solution and architecture
description: How Dyn8 move was solved, the split notification architecture, and remaining known issues
type: feedback
---

# Dyn8 Settings Transfer — SOLVED (2026-03-25)

## The Problem

Moving a channel's Dyn8 insert settings works in Scenario 1 (all channels already have Dyn8) but failed in Scenario 2 (some channels don't have Dyn8). Specifically:
- DynEQ4 curve refreshed correctly
- MultiBD4 crossover curve stayed flat after settings transfer
- Knobs and dB readouts showed correct values for both types

## Root Cause: Split Notification Architecture

dLive Director has TWO separate object hierarchies for dynamics:

1. **cDynamicsNetObject** (64 in registry) — stores sDynamicsData at obj+0x98. Used by `SetAllDataAndUpdateUI`, `DirectlyRecallStatus`, etc. Its `InformOtherObjects` reaches cDynamicsSystem and drivers but NOT the DUC's CC intermediates.

2. **cDynamicsUnitClient (DUC)** (64 via DynamicsRack) — QObject with:
   - Embedded cNetObject at DUC+0x10 (separate from registry net object)
   - Own copy of sDynamicsData at DUC+0x2d0
   - CC intermediates (cDyncCCIntermediate) registered as dependents of DUC+0x10
   - Qt signals: NetworkSelectedBandsWide (idx 1), DynamicsTypeChanged (idx 4), etc.

The **crossover curve** data chain:
```
DUC+0x10 InformOtherObjects → CC intermediates update → ValueChanged signal
→ MultiBCompBandXFrequencyChanged slot → SetBandFreqs → curve redraws
```

`SetAllDataAndUpdateUI` on the cDynamicsNetObject sends messages via InformOtherObjects on the **registry net object**, which does NOT reach the DUC's CC intermediates (they're on DUC+0x10). So the curve never got the notification to redraw.

## The Solution

After writing data to the net object via `SetAllDataAndUpdateUI`, craft proper cAHNetMessage packets and send them through `cDynamicsUnitClient::EntrypointMessage`:

1. **0x1001 (type)** — sets dynamics type at DUC+0x2d0, emits DynamicsTypeChanged
2. **0x1002 (bands wide)** — unpacks crossover data via UnPackBandsWideMessage into DUC+0x2d0, emits NetworkSelectedBandsWide
3. **0x1003 (sidechain)** — unpacks sidechain data, emits NetworkSelectedSource

EntrypointMessage processes each message AND calls `InformOtherObjects` on DUC+0x10, which reaches the CC intermediates. This is the **exact same path** used when real network data arrives from hardware.

## Key Addresses

| Symbol | Address |
|--------|---------|
| cDynamicsUnitClient::EntrypointMessage | 0x1005e9140 |
| nDynamicsDataNet::PackBandsWideMessage | 0x1000cded0 |
| nDynamicsDataNet::PackSideChainMessage | 0x1000cdfd0 |
| cAHNetMessage::cAHNetMessage() | 0x1000e9790 |
| cAHNetMessage::~cAHNetMessage() | 0x1000e9810 |
| cAHNetMessage::SetLength | 0x1000e9ee0 |
| cAHNetMessage::SetDataBufferUBYTE | 0x1000ebde0 |
| DUC key at DUC+0x68 (uint32) | — |
| DUC sDynamicsData at DUC+0x2d0 | — |

## Message Format for EntrypointMessage

Stack-allocated cAHNetMessage (64 bytes buffer):
- msg+0x10: flags (uint16, set 0)
- msg+0x14: src key (uint32 from DUC+0x68)
- msg+0x18: dst key (uint32 from DUC+0x68)
- msg+0x1c: message type (0x1001/0x1002/0x1003)
- Then SetLength + Pack function to fill data payload

## EntrypointMessage Dispatch (0x1005e9140)

Switch on `msg[0x1c] - 0x1001` (cases 0-5):
- 0x1001: read type byte → write to DUC+0x2d0 → DynamicsTypeChanged()
- 0x1002: UnPackBandsWideMessage → DUC+0x2d0 → NetworkSelectedBandsWide()
- 0x1003: UnPackSideChainMessage → DUC+0x2d0 → NetworkSelectedSource()
- 0x1004: read bool → InsertIn(bool)
- 0x1005: → SetStatusWarning()
- default (0x1000 etc): → cNetObject::EntrypointMessage on DUC+0x10

ALL cases then call `cNetObject::InformOtherObjects(msg)` on DUC+0x10.

## UI Widget Architecture for MultiBD4 Curve

- **cOctiveControlForm** — main dynamics control form, stores DUC at +0x118, MultiBCompWidget at +0x120
- **cDynamicsMultiBCompWidget** — parent widget with `SetBandFreqs`, `UpdateMBCBandsForCrossOver`
- **cDynamicsMultiBCompCrossOverWidget** — actual curve widget with `PaintBandCurve`, `SetFreqValues`
- **cDynamicsInsertForm** — manages OctiveControlForm instances, `SetDynamicsUnit(duc, channel)` creates/reuses forms

Signal chain: CC intermediate ValueChanged → OctiveControlForm::MultiBCompBandXFrequencyChanged → MultiBCompWidget::SetBandFreqs → curve redraws

## Failed Approaches (before finding root cause)

1. Writing to DUC+0x2d0 + emitting Qt signals directly — signals fired but InformOtherObjects on DUC+0x10 was missing, so CC intermediates never updated
2. SetAllDataAndUpdateUI alone — updates net object but InformOtherObjects doesn't reach DUC
3. SetDynamicsData + FullDriverUpdate — writes to system array but drivers only write to FPGA
4. ReportData — is a complete NO-OP (just ret)
5. Manual 0xca9 flag + FullDriverUpdate — same as #3

## Known Pre-existing App Bug

MultiBD4 crossover curve doesn't render correctly on the FIRST scene recall after a cold app launch. Must recall another scene and back to see correct curve. This is NOT caused by our plugin — it's a pre-existing dLive Director bug. Doesn't affect our move operation (which works correctly through the dialog).

## Implementation Notes

- The full Dyn8 transfer in `moveChannel()` does: SetAllDataAndUpdateUI (net object) → SetDynamicsData+FullDriverUpdate (system) → EntrypointMessage with 0x1001+0x1002+0x1003 (DUC)
- Only 64 cDynamicsNetObject instances exist (not 128). One per Dyn8 pool unit.
- sDynamicsData is 0x94 (148) bytes at net obj+0x98 and DUC+0x2d0

---
name: Type B data objects — write technique and UI refresh
description: Type B objects need direct field writes + InformObjectsOfNewSettings() for UI refresh. SetStatus hangs offline but InformObjectsOfNewSettings() works.
type: feedback
---

Type B data objects (cDigitalAttenuator, cStereoImage, cDelay, cDirectOutput) have hang points in offline Director mode:

1. **GetStatus** tail-calls `SyscallSendMessage` → hangs
2. **SetStatus** calls `InformObjectsOfNewSettings` which triggers SyscallSendMessage on dependent objects → hangs

**Write technique**: Write fields directly via pointer-chain dereference (vm_write through obj+0x98 etc.), then call **`cDigitalAttenuator::InformObjectsOfNewSettings()`** at `0x1002046d0` for UI refresh.

**Why InformObjectsOfNewSettings() works but InformOtherObjects doesn't:**
- `InformOtherObjects(obj, embMsg)` sends embedded message to DEPENDENT objects, which re-read from the FPGA/network layer → returns -24.0 dB (offline default). The embedded message data is IGNORED.
- `InformObjectsOfNewSettings()` (parameterless, called on the net object) reads the CURRENT state from the object's own fields and pushes to the UI chain directly. Since we wrote correct values to the fields first, the UI gets the right data.

**What DOESN'T work for UI refresh (all tried and failed):**
- InformOtherObjects(obj, embMsg) → UI shows -24.0 regardless of message content
- EntrypointMessage on net object (version 0x1001) → no visible effect
- Driver's EntrypointMessage (vt[6], version 0x101) → crash (SyscallSendMessage)
- Driver's vt[9] setValue → crash (accesses beyond 192-byte object bounds)
- QObject::setProperty on driver → crash (not a QObject)
- QObject::metaObject on cFPGAInputProc, InputMixerWrapper → crash (not QObjects)

**Key architecture facts discovered:**
- cDigitalAttenuatorDriver is only 0xC0 (192) bytes, NOT a QObject
- driver+0x20 = cFPGAInputProc (SHARED across all channels, not per-channel)
- Gain values stored in external array at stride 0x120, accessed via pointer deref from net object
- driver vtable methods vt[7] and vt[9] access offsets beyond 192 bytes — they're for a larger subclass

**Similar functions likely exist for other Type B objects:**
- `nm -C binary | grep InformObjectsOfNewSettings` to find equivalents for cStereoImage, cDelay, etc.

**How to apply:** For any Type B object: (1) write raw fields, (2) call InformObjectsOfNewSettings() on the net object.

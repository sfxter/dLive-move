---
name: cAHNetMessage version field required for DirectlyRecallStatus
description: DirectlyRecallStatus checks msg[0x1c] for version 10 or 14 — must set after FillGetStatus or it silently no-ops
type: feedback
---

After calling FillGetStatus to fill a cAHNetMessage, the version field at struct offset 0x1c must be set to 0x0a (10) before passing to DirectlyRecallStatus. FillGetStatus only fills the external data buffer (at the pointer stored at offset 0x08), it does NOT set the message header fields. DirectlyRecallStatus checks msg[0x1c] and silently returns without applying data if it's not 10 or 14.

**Why:** All DirectlyRecallStatus implementations (cCompressor, cGate, cHighPassFilter, cBiquadOneBandNetObject, cBiquadFourBandNetObject, cGateSideChainPEQNetObject, cPreampModel) share this version check pattern.

**How to apply:** Always set `*(uint32_t*)(msg + 0x1c) = 0x0a` after FillGetStatus and before DirectlyRecallStatus.

cAHNetMessage struct layout:
- offset 0x00: uint32_t length (set by SetLength)
- offset 0x04: uint32_t capacity
- offset 0x08: void* data_ptr (heap allocated)
- offset 0x10: uint16_t objectId (0xFFFF = unset)
- offset 0x14: uint32_t (0xFFFFFFFF)
- offset 0x18: uint32_t (0xFFFFFFFF)
- offset 0x1c: uint32_t version (must be 10 or 14 for DirectlyRecallStatus)

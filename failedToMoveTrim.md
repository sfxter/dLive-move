# Failed Attempts to Move Digital Trim

## Goal
Move the digital trim (and polarity) value when moving a channel. These are part of the preamp section in dLive Director.

## What Was Tried

### Attempt 1: Type B Direct Field Write (WRONG OBJECT)
- Original ProcDescB had DigitalAtten at `ch[55]` with vtable `0x106c78188`
- **Both were wrong.** `ch[55]` contains the integer `3`, not a pointer. The vtable address was also incorrect.
- Result: writes went to address 0x3 → silently failed. Self-test appeared to pass because it read/wrote the same garbage path.

### Attempt 2: Find Correct Object Location
- Scanned ch0 fields 0-120 with correct cDigitalAttenuator vtable (`0x106c78198`)
- Found 7 DigitalAttenuator objects per channel at driver offsets: **4, 22, 40, 58, 76, 94, 112** (stride 18)
- Access pattern: `ch[N]` = cDigitalAttenuatorDriver, `ch[N][1]` = cDigitalAttenuator net object
- The **first one at ch[4][1]** is the preamp digital trim
- The other 6 correspond to processing positions (some have invalid/garbage pointers — writing to those crashed the app)

### Attempt 3: Type B Direct Field Write (CORRECT OBJECT, still fails)
- Updated descriptor to `chOffset=4, subFieldIdx=1`
- Reading works: `gainPtr=0x128a27998, gainVal=259` for 1.0 dB trim (encoding: 256*dB + 3)
- Writing works in memory: `wrote=515, readback=515 OK`
- **But the value doesn't persist.** Even saving to a scene and recalling doesn't show the new value.
- The pointer at `obj+0x98` points to a **read-only cache** (or a derived value), not the source of truth.

### Attempt 4: Convert to Type A (FillGetStatus/DirectlyRecallStatus)
- This approach works perfectly for HPF, compressor, gate, PEQ, etc.
- Found HPF's FillGetStatus at vtable index 10, DirectlyRecallStatus at index 11
- **cDigitalAttenuator's vtable is shorter** — only 9 primary entries (vt[0]-vt[8]). Index 10+ is a secondary vtable for cDigitalAttenuatorDriver.
- cDigitalAttenuator does NOT have FillGetStatus/DirectlyRecallStatus virtual methods. It inherits from cNetObject (simpler), not the deep cAudioObject hierarchy that HPF uses.
- Dead end.

## Why It's Hard

1. **cDigitalAttenuator is a cNetObject, not a full cAudioObject.** The HPF/compressor/gate/PEQ objects inherit from a deeper hierarchy that includes FillGetStatus/DirectlyRecallStatus virtual methods. DigitalAttenuator doesn't have these — it uses `EntrypointMessage` (vfunc[2]) which dispatches on message version.

2. **EntrypointMessage needs proper messages via SyscallSendMessage.** The versions are:
   - 0x1001: set gain (UWORD) — same as CSV import `SendPreampData`
   - 0x1003: set phantom (UBYTE)
   - 0x1004: set pad (UBYTE)
   - 0x0a-0x12: various SetStatus/GetStatus

   But SyscallSendMessage in offline mode routes to SendNetworkMessage (objectId != 0), which drops messages because the network connection table has no entries.

3. **Direct memory writes don't persist.** The value pointed to by `obj+0x98` is a cache populated from somewhere else. Writing to it changes the in-memory value temporarily, but the actual "source of truth" is elsewhere (likely in the driver or in a scene/show storage layer).

4. **No MIDI handler found for digital trim.** Unlike analog gain (MIDISetGain), there's no obvious MIDISetTrim function. The MIDI handler approach that worked for preamp gain doesn't apply here.

## Promising Paths Not Yet Explored

1. **RegistryRouter scan for DigitalAttenuator objects**: Code was added to scan `gRegistryRouter+0x3a9820` for DA vtable matches. This would give us the objectId and handle needed for message-based writes. Not yet tested (probe was just added).

2. **EntrypointMessage with version 0x0a (ResetToDefault/SetStatus)**: The EntrypointMessage handler has a switch for versions 0x0a-0x12. One of these might be a local SetStatus that doesn't require network. Disassembling the switch cases might reveal a local write path.

3. **cDigitalAttenuatorDriver::setValue**: The driver at `ch[4]` wraps the net object. It likely has a setter method that updates both the driver's internal state AND the net object, going through proper Qt signal/slot notification. Finding and calling this method would be the clean approach.

4. **Library preset recall path**: The user confirmed that saving a channel preset and recalling it DOES restore digital trim. Tracing `cLibraryFileManager::RecallObjectFromLibrary` → how it sets trim would reveal the correct write mechanism.

5. **Scene save/recall mechanism**: Understanding how scenes store and recall trim values would reveal the source of truth.

## Key Addresses

| Item | Address |
|------|---------|
| cDigitalAttenuator vtable+16 | 0x106c78198 |
| cDigitalAttenuatorDriver vtable+16 | 0x106c781f0 |
| cDigitalAttenuator::EntrypointMessage | 0x100204a00 |
| cDigitalAttenuator vfunc[6] (dispatch) | 0x100204890 |
| Driver offset in InputChannel | ch[4] (first of 7, stride 18) |
| Net object in driver | driver[1] |
| Gain pointer offset | obj+0x98 (SWORD, ptr deref) |
| Pad pointer offset | obj+0xa0 (UBYTE_BOOL, ptr deref) |
| Phantom pointer offset | obj+0xa8 (UBYTE_BOOL, ptr deref) |
| Gain encoding | 256 * dB + 3 (approximate) |

## Also Applies To
- **Polarity**: stored on cSocket via cQtSignalSlotSwitchDriver at `cSocket+0x48`. Accessed through cSocketProxy. Same problem — direct writes likely don't persist.
- **StereoImage and Delay**: Also Type B objects with the same issue. Their correct driver offsets in InputChannel are not yet determined (scan was added but not yet run).

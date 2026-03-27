# Plan: Add "Move Channel" Feature to dLive Director V2.11

## Context

dLive Director V2.11 is Allen & Heath's Qt 5.15.2 mixing console editor (x86_64, 119MB binary). It lacks a "Move Channel" feature — reordering channels currently requires tedious manual copy/paste of presets one-by-one across up to 128 channels. We'll create a dylib patch that injects this feature via `DYLD_INSERT_LIBRARIES`.

**User requirements:**
- Move a channel (with ALL processing: EQ, dynamics, inserts, sidechain, routing/sends) to a new position
- Other channels shift to fill the gap (like list insertion)
- Preamp VALUES move with the channel, preamp SOURCE stays tied to position
- Must handle MONO and STEREO channels
- ALL direct GetStatus/SetStatus (NOT Copy/Paste system, NOT Library system)

---

## Confirmed Discoveries (from runtime exploration)

### Struct layouts
- **sChannelStripKey** = `{uint32_t type; uint8_t number; pad[3]}` = 8 bytes. `MAKE_KEY(type, ch) = type | (ch << 32)`. type=1=Input, 0-indexed.
- **sAudioSource** = `{uint32_t sourceType; uint32_t channelNumber}` = 8 bytes. sourceType=5 for local inputs.
- **Return values**: bool functions return garbage in upper bytes (`setae` only sets low byte). Must mask: `& 0xFF`.

### Object hierarchy (confirmed at runtime)
```
cApplication::Instance()          → 0x100d5a120 (NOT the QApplication)
  └─ app[23][9]                   → cAudioCoreDM (vtable static 0x106c77998)
       └─ dm[47..174]            → 128 × cInputChannel (vtable static 0x106c79978)
            └─ ch[2]  = cPreampModel
            └─ ch[3]  = cStereoImageDriver
            └─ ch[5]  = cHighPassFilter
            └─ ch[6]  = cBiquadOneBandNetObject (LPF)
            └─ ch[7]  = cCompressor
            └─ ch[8]  = cGateSideChainPEQNetObject
            └─ ch[9]  = cGate
            └─ ch[10] = cBiquadFourBandNetObject (PEQ 4-band)
            └─ ch[11] = cDirectOutputDriver
            └─ ch[12] = cInsertDriver (Insert 1)
            └─ ch[13] = cInsertDriver (Insert 2)
            └─ ch[14] = cSideChainSelectDriver (SC 1)
            └─ ch[15] = cSideChainSelectDriver (SC 2)
            └─ ch[16] = cProcessingOrderingSelectDriver
            └─ ch[17] = cInputDelayDriver
            └─ ch[18] = cStereoImage
            └─ ch[21] = cFPGAInputProc
            └─ ch[55] = cDigitalAttenuator
```

### Data read/write mechanism
- **Read**: `FillGetStatus(cAHNetMessage&)` — fills message with all parameters
- **Write**: `DirectlyRecallStatus(cAHNetMessage&)` — applies parameters from message
- These are non-virtual, class-specific methods (NOT the network GetStatus/SetStatus)
- `cAHNetMessage` constructor: default `0x1000e9790`, with capacity `0x1000ed490`

### FillGetStatus addresses (all confirmed in symbol table)
| Class | FillGetStatus | DirectlyRecallStatus |
|-------|--------------|---------------------|
| cCompressor | 0x1001f1040 | 0x1001f1700 |
| cGate | 0x100287a00 | 0x100287b30 |
| cPreampModel | 0x1002d4170 | 0x1002d42c0 |
| cHighPassFilter | 0x10028d4d0 | 0x10028d5c0 |
| cBiquadOneBandNetObject (LPF) | 0x100b1e790 | 0x100b1e8d0 |
| cBiquadFourBandNetObject (PEQ) | 0x100b1cdc0 | 0x100b1cf00 |
| cGateSideChainPEQNetObject | 0x1002d0d30 | 0x1002d0ed0 |
| cDynamicsNetObject | 0x100238c90 | 0x100238d30 |
| cIFXNetObject (ext insert) | 0x10026eb60 | 0x10026ec50 |

### Key singletons & utilities
| Symbol | Static address | Notes |
|--------|---------------|-------|
| CPRHelpers::Instance() | 0x100403270 | Returns helpers with ChannelExists, etc. |
| App::Instance() | 0x100d5a120 | NOT QApplication; separate cApplication object |
| AudioCoreDM::GetChannelName | 0x1001a3750 | (audioDM, stripType=1, ch) → const char* |
| AudioCoreDM::SetChannelName | 0x1001a3670 | (audioDM, stripType=1, ch, name) |
| AudioCoreDM::GetChannelColour | 0x1001a34a0 | returns uint8_t |
| AudioCoreDM::SetChannelColour | 0x1001a3580 | |
| cAHNetMessage ctor (default) | 0x1000e9790 | |
| cAHNetMessage ctor (capacity) | 0x1000ed490 | |
| cAHNetMessage dtor | 0x1000e9810 | |

### UI findings
- App uses QML (NOT QWidgets) for main UI — **no QMenuBar exists**
- Top-level widgets include cFormHolder objects for each screen
- Must use **standalone QDialog** for our UI (not menu injection)
- `QApplication::topLevelWidgets()` works for finding visible windows

### Network findings
- `SyscallSendMessageCallback` is **NULL** in offline Director mode
- `SeekObject::FindObject()` returns NULL for all objects in offline mode
- Processing objects are only reachable through AudioCoreDM → cInputChannel hierarchy
- This is fine — we access objects directly, not through the network layer

---

## Implementation Plan

### Step 1: Validate FillGetStatus / DirectlyRecallStatus ← NEXT
**File:** `src/plugin_main.mm`

Test that the read/write cycle works:
1. Call `Compressor::FillGetStatus(msg)` on ch0 → verify message has non-zero data
2. Call `Compressor::DirectlyRecallStatus(msg)` on ch1 → verify it applies
3. Call `Gate::FillGetStatus(msg)` on ch0 → verify
4. Test on all processing object types

**Critical**: The previous test called `GetStatus` (the network handler at 0x1001f1000) instead of `FillGetStatus` (0x1001f1040). The message was empty because GetStatus dispatches via the network system which is null in offline mode. `FillGetStatus` writes directly to the message buffer — this should work.

### Step 2: Build channel snapshot module
**File:** `src/channel_snapshot.h`

```cpp
struct ChannelSnapshot {
    uint8_t compressorMsg[MSG_SIZE];    // from ch[7] FillGetStatus
    uint8_t gateMsg[MSG_SIZE];          // from ch[9]
    uint8_t peqMsg[MSG_SIZE];           // from ch[10]
    uint8_t hpfMsg[MSG_SIZE];           // from ch[5]
    uint8_t lpfMsg[MSG_SIZE];           // from ch[6]
    uint8_t preampMsg[MSG_SIZE];        // from ch[2]
    uint8_t gateSCPeqMsg[MSG_SIZE];     // from ch[8]
    uint8_t directOutMsg[MSG_SIZE];     // from ch[11]
    uint8_t delayMsg[MSG_SIZE];         // from ch[17]
    uint8_t digitalAttenMsg[MSG_SIZE];  // from ch[55]
    uint8_t stereoImageMsg[MSG_SIZE];   // from ch[18]
    uint8_t insert1Msg[MSG_SIZE];       // from ch[12]
    uint8_t insert2Msg[MSG_SIZE];       // from ch[13]
    uint8_t scSelect1Msg[MSG_SIZE];     // from ch[14]
    uint8_t scSelect2Msg[MSG_SIZE];     // from ch[15]
    char name[64];
    uint8_t colour;
    uint64_t audioSource;
    bool isStereo;
};
```

Read: iterate each processing object offset, call class-specific `FillGetStatus`
Write: iterate, call class-specific `DirectlyRecallStatus`

### Step 3: Implement move algorithm
**File:** `src/move_engine.h`

Move UP (source > dest): snapshot D..S, write S→D, shift D..S-1 → D+1..S
Move DOWN (source < dest): snapshot S..D, write S→D, shift S+1..D → S..D-1
After all writes: restore preamp audio sources per position

### Step 4: Handle dynamics inserts
- `cInsertDriver` at ch[12], ch[13] — snapshot/recall insert state
- For pooled dynamics units: `cDynamicsRack::FindFirstFreeUnit`, assign, copy settings
- Unassign old unit, find nearest free, assign, write settings + sidechain

### Step 5: Handle stereo reconfiguration
- Pre-scan range for stereo channels via `ChannelIsStereo`
- If stereo channels move to positions that need re-pairing:
  - Build new `sIPStereoConfigurationData`
  - Call `AudioCoreDM::NewInputStereoConfiguration`
  - Wait for reconfiguration, then write data
- Warn user about audio interruption

### Step 6: Build UI
**Standalone QDialog** (no menu bar — app uses QML):
```cpp
auto* dlg = new QDialog();
dlg->setWindowTitle("Move Channel");
// QSpinBox source (1-128), QSpinBox dest (1-128)
// QPushButton Move / Cancel
// QLabel status
dlg->show();
```

Trigger: global keyboard shortcut Ctrl+Shift+M via `QShortcut` on a top-level widget.

### Step 7: Mix assignments / routing (sends)
- DataType 20 = "Mix Assignments Copy Paste Reset Manager" — this is a net object
- Need to find the corresponding processing object in InputChannel for sends
- May need additional exploration of InputChannel fields beyond ch[55]

---

## Build System
**File:** `Makefile` (already working)
- Compile step uses homebrew Qt 5.15 headers (`-iframework`)
- Link step uses app's bundled x86_64 Qt frameworks (`-F`)
- Separate .o compile and dylib link to avoid arch mismatch

---

## Testing & Verification

1. **FillGetStatus validation**: Dump compressor data for ch0 — should be non-zero bytes
2. **Round-trip test**: FillGetStatus ch0 → DirectlyRecallStatus ch1 → FillGetStatus ch1 → compare bytes
3. **Visual verification**: After move, open channel in Director UI and verify EQ/comp/gate match
4. **Mono move**: Move ch3→pos1, verify processing and names shifted correctly
5. **Stereo move**: Move stereo pair, verify both L/R move
6. **Preamp check**: After move, verify audio sources stayed at original positions
7. **Edge cases**: ch0→ch127, ch127→ch0, adjacent channels, no-op (same position)

---
name: Move Channel implementation status
description: Current state of Move Channel feature — what works, techniques used, and remaining work
type: project
---

## Working Features

### Type A Processors (7 total)
DigiTube, HPF, LPF, Compressor, GateSCPEQ, Gate, PEQ
**Technique:** FillGetStatus → snapshot cAHNetMessage → DirectlyRecallStatus → ReportData for UI update.
msg[0x1c] (version) MUST be set to 10 before DirectlyRecallStatus.

### Type B Processors
DigitalTrim (gain+mute+polarity), ProcOrder, Insert1, Insert2
**Technique:** Direct field read/write via vm_read/vm_write through pointer-chain dereference. Two access patterns: FT_SWORD/FT_UBYTE_BOOL (pointer deref) and FT_DIRECT_UBYTE (direct offset).
**UI refresh:** Call `cDigitalAttenuator::InformObjectsOfNewSettings()` at `0x1002046d0` on the net object AFTER writing raw fields. This pushes current values to UI without going through the FPGA/network layer.

### Sidechain Source (SC1/SC2)
cSideChainSelect objects accessed via ch[14]/ch[15] → driver subfield 1.
**Technique:** Direct write to *(obj+0x138) (stripType) and *(obj+0x140) (channel), plus update "old value" cache at obj+0x168/0x16c. Then use embedded message at obj+0x60 with InformOtherObjects for UI notification. Bypasses RefreshSource which validates via ChannelMapper and resets values.
**Critical:** Channel references must be remapped during move to account for position shifts.

### Mixer Sends / Fader / DCA / Mute Groups
sInputAttributes at cMixerModule+0x200, stride 0xAC8 per channel.
**Technique:** Bulk copy entire sInputAttributes block via vm_write. Then call cInputMixer::SyncMainGain(ch, gain) at 0x1002927e0 for fader UI update.

### Channel Name and Colour
Via AudioCoreDM methods g_setChannelName/g_setChannelColour.

### Preamp (Gain, Pad, Phantom)
512 cAnalogueInput objects in gRegistryRouter local table at offset 0x3a9820.
**Technique:** Write via MIDISetGain(0x1004ecf80), MIDISetPad(0x1004ed020), MIDISetPhantomPower(0x1004ed0a0) — these store values directly and call InformOtherObjects for UI notification.

### Digital Trim + Polarity (NEWLY WORKING 2026-03-23)
cDigitalAttenuator at ch[4] → driver[1] (net object).
**Fields:** +0x98→gain(SWORD,BE), +0xa0→mute(UBYTE_BOOL), +0xa8→polarity(UBYTE_BOOL)
**Technique:** writeTypeBFields() + InformObjectsOfNewSettings(0x1002046d0).
**Key symbols found via `nm`:**
- SetAttenuation(0x100204310), SetPhase(0x100204380), SetMute(0x1002043e0)
- InformObjectsOfNewSettings(0x1002046d0), Refresh(0x100204850)
- LinkDigitalAttenuator on cChannelSelector(0x1001e2840)

### Delay (NEWLY WORKING 2026-03-23)
cDelay via cInputDelayDriver at ch[17] → driver[1] (net object).
**Fields:** +0x98→delay(UWORD,BE), +0xa0→bypass(UBYTE_BOOL)
**Technique:** Use SetDelayAndInformOthers(0x100202590) and SetBypassAndInformOthers(0x100202660) directly on net object — these write fields AND notify UI in one call.

### Input Patching Scenario B (NEWLY WORKING 2026-03-24)
Socket assignment moves with channel via `cChannel::SetInputChannelSource()` at `0x1006d8410`.
**Technique:** Uses CSV Import code path — `cImportDataManager::SendChannelInputPatch()` disassembly revealed the chain:
1. `cUIManagerHolder::Instance()` → `0x10076d170` → singletons at +0x78 (cChannelManager) and +0x20 (cAudioSRPManager)
2. `cChannelManager::GetChannel(stripType=1, chNum)` → `0x1006e3f90` → cChannel*
3. `cAudioSendReceivePointManager::GetSendPoint(sourceType, sourceNum)` → `0x1006ce8e0` → cAudioSendPoint*
4. `cChannel::SetInputChannelSource(eActiveInputSource=1, sendPoint, nullptr)` → full update + UI refresh

**Critical:** `SetInputChannelSource` also moves preamp (gain/pad/phantom) with the socket. When Scenario B is active, `recallChannel()` MUST skip preamp writes (`skipPreamp=true`) to avoid double-move bug.

**Failed approaches (all wrote data but no UI refresh):**
- `writePatchData()` alone
- `writePatchData()` + `InformObjectsOfChannelPatch()`
- `ConfigurePatchBay()` + `ActionTick()`
- `ConfigurePatchBay()` + `InformObjectsOfChannelPatch()`

**Key lesson:** cChannelMapper is a global object — its InformOtherObjects doesn't reach the UI patching widgets. Only the cChannel task system refreshes the patching UI. Always look for the app's own code path first (CSV import, scene recall, MIDI handler).

### Insert Routing — FX Insert Move (NEWLY WORKING 2026-03-24)
Insert A sends/returns correctly moved using per-channel audio routing point reassignment.

**Challenges overcome:**
1. `CreateStandardChannelInsertTasks(cFXUnit*, cChannel*, insertPoint)` treats FX unit as a shared resource — assigning to one channel unassigns from others. Dual mono racks (L+R) on two channels broke.
2. `CreateDualMonoChannelInsertTasks` only works for adjacent channels and always assigns L→first, R→second — doesn't preserve original L/R side mapping.
3. FX unit-level APIs don't let you specify which SIDE (L or R) to assign.

**Solution:** Bypass FX unit-level APIs entirely. Snapshot and reassign the **specific audio routing points** per channel:
- `cChannel::GetInsertReturnPoint(ip)` → returnPt+0x20 = connected FX send point (FX output)
- `cChannel::GetInsertSendPoint(ip)` → `cAudioSendPoint::GetFirstReceivePoint()` = connected FX receive point (FX input)
- Recall via `CreateSetInsertSendTargetTask(fxRecvPt, ip, true)` + `CreateSetInsertReturnSourceTask(fxSendPt, ip)`
- Both use hidden struct return ABI: rdi=&retBuf, rsi=cChannel*, rdx=audioPoint, ecx=insertPoint
- Execute each via `PerformTasks(audioSRPManager, taskBuf)`

**Key addresses:**
- `cChannel::GetInsertSendPoint(ip)` → `0x1006d9780`
- `cChannel::GetInsertReturnPoint(ip)` → `0x1006d9850`
- `cAudioSendPoint::GetFirstReceivePoint()` → `0x1006cd7b0`
- `cAudioSendPoint::GetParentType()` → `0x1006cd690` (2=FXUnit, 6=AHFXUnit)
- `cChannel::CreateSetInsertSendTargetTask()` → `0x1006da210`
- `cChannel::CreateSetInsertReturnSourceTask()` → `0x1006da450`
- `cAudioSendReceivePointManager::PerformTasks()` → `0x1006d19c0`

**Hidden struct return ABI:** Many cChannel/cFXUnit task-creating methods return QList<sASRPMTask> via hidden first parameter (rdi=&retBuf). Real params shift: rsi=this, rdx=param1, ecx=param2, etc.

### Insert A+B Routing — Rack FX, External, and all types (WORKING 2026-03-24)
Both Insert A (ip=0) and Insert B (ip=1) correctly moved for all insert types including Rack FX and External.
Same per-channel audio routing point technique as described above. parentType filter removed to handle all types.

### Dyn8 Insert — Full Settings Transfer (WORKING 2026-03-25)
Both DynEQ4 and MultiBD4 settings now transfer correctly, including crossover curve refresh.
**Technique:** Three-layer write:
1. `SetAllDataAndUpdateUI` on cDynamicsNetObject (registry) — updates net object + knob widgets
2. `SetDynamicsData` + `FullDriverUpdate` on cDynamicsSystem — updates system array + drivers
3. **Craft cAHNetMessage packets (0x1001 type + 0x1002 bands wide + 0x1003 sidechain) and send through `cDynamicsUnitClient::EntrypointMessage`** — this is the critical step that reaches the DUC's CC intermediates via InformOtherObjects on DUC+0x10, triggering the crossover curve redraw.

**Key discovery:** cDynamicsNetObject and cDynamicsUnitClient have completely separate notification chains. The net object's InformOtherObjects does NOT reach the DUC's CC intermediates. Must send messages through DUC's EntrypointMessage (same path as network data arrival).

**Known pre-existing app bug:** MultiBD4 curve doesn't render on first scene recall after cold launch. Not caused by our plugin.

See `memory/dyn8_solution.md` for full architecture details.

## Remaining Work

1. **StereoImage** — Need to find correct ch offset and InformObjectsOfNewSettings equivalent
2. **Stereo channel handling** — detect linked pairs, move both channels together

# Dyn8 Settings Transfer — Failed Approaches & Analysis

## Context

dLive Director V2.11 "Move Channel" plugin needs to transfer Dyn8 (dynamics pool) insert settings when moving a channel. There are two scenarios:

- **Scenario 1 — All channels in the move range already have Dyn8 inserts**: This works. Settings transfer correctly via `DirectlyRecallStatus` + `ReportData`.
- **Scenario 2 — Some channels in the range do NOT have Dyn8 inserts**: This fails. The target channel's Dyn8 unit gets assigned but its settings show as defaults in the UI.

## What Works (Scenario 1: All Have Dyn8)

When ALL channels in the move range already have Dyn8 inserts assigned, the move works:

1. **Snapshot**: `FillGetStatus` on each channel's `cDynamicsNetObject` captures the full settings into a `cAHNetMessage`.
2. **Insert reassignment**: `SetInserts` routes each target channel to its OWN Dyn8 unit (unit index == channel index). Since the unit was already assigned/active, this just re-routes it.
3. **Settings restore**: `DirectlyRecallStatus` (with method byte `0x0a` at message offset `0x1c`) writes the captured settings into the target `cDynamicsNetObject`. `ReportData` then triggers UI update.
4. **Result**: 143/144 bytes match, UI updates correctly.

**Why this works**: The Dyn8 units were already initialized and actively assigned to their channels. Re-routing them just changes the audio path; the `cDynamicsNetObject` was already in a valid state, so `DirectlyRecallStatus` can write settings into it and the UI picks them up.

## What Fails (Scenario 2: Mixed — Some Channels Without Dyn8)

When a channel with Dyn8 moves to a position where the previous channel did NOT have Dyn8:

1. The target channel's Dyn8 unit (unit index == channel index) was **not previously assigned/active**.
2. `SetInserts` assigns/routes it, which **initializes it to default settings**.
3. `DirectlyRecallStatus` writes the source settings into memory — verified by reading `obj+0xa0` through `obj+0x12F`, showing **143/144 bytes match**.
4. **But the UI still shows default settings.**
5. **Even recalling the original scene (which should restore everything) still shows default Dyn8 settings.**
6. **Only an app restart fixes it** — suggesting the insert assignment corrupted internal state.

### Root Cause Analysis

The `SetInserts` call to assign a previously-unassigned Dyn8 unit appears to put the `cDynamicsNetObject` (or its parent `cInsertNetObject`) into a state where:
- Memory writes to the settings region (`+0xa0` to `+0x12F`) are accepted but ignored by the UI layer.
- The object is "initialized" in a way that prevents proper settings recall.
- Even scene recall (which normally works via the scene manager) cannot override this corrupted state.
- Only a full app restart re-initializes the objects correctly.

This suggests the problem is NOT in the settings data itself (which is written correctly) but in the **object lifecycle/initialization state** that `SetInserts` triggers when assigning a Dyn8 unit for the first time. There may be internal flags, observer registrations, or initialization callbacks that only happen during proper app startup or hardware discovery, and our runtime `SetInserts` call doesn't replicate all of them.

## All Approaches Tried

### 1. Raw memcpy / vm_write to DynNetObj settings region
- **Result**: Data in memory matches (143/144 bytes), but UI does not update. SIGILL crash when trying to show a dialog afterwards.
- **Why failed**: Writing raw bytes to the object's memory does not trigger any UI notification mechanism.

### 2. SetStatus + ReportData on cDynamicsNetObject
- **Result**: Data in memory matches (143/144 bytes), but UI does not update.
- **Why failed**: `SetStatus` writes the internal fields but `ReportData` alone doesn't trigger the full UI refresh chain. The dynamics UI panel reads from some cached/derived state, not directly from the object memory.

### 3. vm_write (Mach VM API) to DynNetObj settings
- **Result**: Same as memcpy — data in memory but no UI update.
- **Why failed**: Same root cause. Raw memory writes bypass the object's internal change-notification mechanism.

### 4. SetAllDataAndUpdateUI
- **Result**: Abort trap / crash.
- **Why failed**: This function has preconditions or expects a specific object state that we couldn't reproduce.

### 5. Re-routing approach (swap Dyn8 units between channels)
- **Result**: Did not work (details from earlier chat context).
- **Why failed**: Dyn8 pool units have a fixed 1:1 relationship with channels. You cannot route channel 4 to use channel 1's Dyn8 unit — the routing system rejects or ignores cross-unit assignments.

### 6. Library Save/Recall approach
- `cLibraryManagerClient::CreateLibrary` — **works**, creates library entry without crashes.
- `cLibraryManagerClient::RecallObjectFromLibrary` — **returns OK but is a no-op in offline mode**.
- **Pure test**: Stored unit 1's settings, recalled onto unit 0, verified: "0 bytes changed in unit 0".
- **Why failed**: The library recall mechanism dispatches a network command. In offline dLive Director (no hardware connected), the `SeekObject`/network mechanism that would apply the library data simply doesn't execute. The function returns success but does nothing.

### 7. DirectlyRecallStatus (method 0x0a) + ReportData
- **Result**: In Scenario 1 (all channels have Dyn8), works perfectly — 143/144 bytes match AND UI updates.
- **Result**: In Scenario 2 (mixed), 143/144 bytes match in memory BUT UI shows defaults. Scene recall also broken. Requires app restart.
- **Why failed in Scenario 2**: `SetInserts` to assign a previously-unassigned Dyn8 unit puts the object into a corrupted lifecycle state. `DirectlyRecallStatus` writes correct data but the UI/scene system no longer reads from this object properly.

### 8. DirectlyRecallStatus with method byte 0x0e
- **Not fully tested** — `DirectlyRecallStatus` accepts both `0x0a` and `0x0e` at offset `0x1c`, then delegates to `SetStatus(msg, 0xffff, 0xffffffff)`. Was planned as a variant but unlikely to fix the core issue since `0x0a` already writes the data correctly.

## Key Technical Details

### cDynamicsNetObject Memory Layout
- Each object is **0x130 bytes**
- Settings live at **+0xa0 to +0x12F** (0x90 = 144 bytes)
- 64 objects exist (one per Dyn8 pool unit), contiguous in the registry
- `CURRENT_DYNAMICS_VERSION = 2` (at binary offset `0x10179e22a`)

### FillGetStatus / DirectlyRecallStatus Message Format
- Uses `cAHNetMessage` (constructor at `0x1002e0ca0`, capacity 512)
- `FillGetStatus` (at `0x100238c90`) serializes the DynNetObj state into the message
- `DirectlyRecallStatus` (at `0x100238d30`) checks offset `0x1c` for method `0x0a` or `0x0e`, then calls `SetStatus(msg, 0xffff, 0xffffffff)` which deserializes back
- `ReportData` (at `0x10023a290`) triggers UI notification

### Insert Assignment (SetInserts)
- `cChannel::SetInserts` at `0x1006d9920`
- Takes `sInsertPts { recvPt, recvPt, sendPt, sendPt }` and insert point index (0 or 1)
- For Dyn8: `getDyn8SendPoint(unitIdx)` and `getDyn8RecvPoint(unitIdx)` provide the audio endpoints
- **Assigning a Dyn8 unit that wasn't previously active resets it to defaults and corrupts the object state**

### Library API (works for store, fails for recall in offline)
- `cLibraryManagerClient` at `UIManagerHolder+0x98`
- `CreateLibrary` at `0x1006f2020` — stores preset (confirmed working)
- `RecallObjectFromLibrary` at `0x1006f3f80` — no-op in offline mode
- `DeleteLibrary` at `0x1006f1cb0` — cleanup (works)
- `eLibraryType = 0xb` (dynamics), `eLibraryLocation = 1` (local/SBC)
- `eLibraryObject = 0x0f` for dynamics
- `sLibraryKey`: 16 bytes `{QString* name, uint32_t location, uint32_t type}`

### Dynamics Unit Naming
- Format: `"%sDynamics Unit %02d"` where prefix comes from `cDiscovery::GetStageBoxDiscoveryObject()+0x99` (empty string in offline mode), and index is 1-based.
- Example: `"Dynamics Unit 02"` for unit index 1.

## Untried Ideas

1. **Find the initialization callback that `SetInserts` triggers** and call it manually before `DirectlyRecallStatus`. The Dyn8 unit may need a specific initialization sequence before it can accept settings.

2. **Don't use `SetInserts` for Dyn8 at all** — instead, find how the scene manager assigns Dyn8 inserts during scene recall (which presumably handles the full lifecycle) and replicate that mechanism.

3. **WarnUIOfSetStatus** (at `0x100239480`) — a different UI notification path that might work where `ReportData` doesn't. Was identified but never tested.

4. **Call the Dyn8 insert assignment through the scene manager** rather than through `SetInserts` directly. If scene recall can properly assign a Dyn8 unit with settings, there may be a scene-level API that handles both assignment and settings in one atomic operation.

5. **Pre-initialize all 64 Dyn8 units at plugin startup** so they're never in the "unassigned" state. This is speculative — the initialization state may depend on more than just the assignment flag.

6. **Use the cDynamicsForm / cDynamicsLibraryForm UI-level API** to recall settings, which might handle all the UI refresh internally. These are the actual UI panels that users interact with.

7. **Post-process via scene save/recall**: After moving the channel, save to a temp scene, manipulate the scene data to include correct Dyn8 settings, then recall that scene. This is indirect but might work since scene recall handles the full lifecycle.

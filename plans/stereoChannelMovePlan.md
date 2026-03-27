# Stereo Channel Move — Type A Settings Preservation

## Context

The `moveChannel()` function works for mono channels. When a channel changes between mono and stereo, `AudioCoreDM::NewStereoConfig` reconfigures the mixer, resetting ALL channel settings. We need to snapshot Type A settings before the config change and restore them after.

A stereo channel occupies two consecutive positions (e.g., ch 1+2 become a stereo pair). Moving a stereo channel or converting mono↔stereo during a move requires preserving settings across the reset.

## Implementation Steps

### Step 1: Stereo Detection

Add `isChannelStereo(ch)` wrapper around `Helpers_ChannelIsStereo` (0x100405740).

**In `plugin_main.mm`:**
- Add typedef `fn_ChannelIsStereo` and resolved global near line 182
- Resolve in `resolveSymbols()` using `Addr::Helpers_ChannelIsStereo`
- Add convenience function:
  ```cpp
  static bool isChannelStereo(int ch) {
      void* helpers = g_CPRHelpersInstance();
      if (!helpers) return false;
      uint64_t key = MAKE_KEY(CST_Input, (uint8_t)ch);
      return g_channelIsStereo(helpers, key);
  }
  ```
- Log stereo status of ch 0-7 during init for validation

### Step 2: LLDB Probing of Stereo Config Functions

Before implementing config change, probe with LLDB to discover signatures. **Prioritize the highest-level API** (`App::NewInputConfig` at 0x100d6e0c0) — this pattern has consistently worked best in this project.

**LLDB Session Plan:**
1. Launch dLive Director with plugin loaded
2. Set breakpoints (highest-level first):
   ```
   br s -a <slide+0x100d6e0c0>   # App::NewInputConfig (try this FIRST)
   br s -a <slide+0x1001a0f10>   # AudioCoreDM::NewStereoConfig (backup)
   ```
3. Manually toggle stereo on a channel in the UI (right-click channel → stereo)
4. When breakpoint hits, dump registers:
   ```
   register read rdi rsi rdx rcx r8 r9
   ```
5. Identify: which function is called first (likely App level), what args
6. Step through to understand reset timing and what lower-level calls it makes

**After LLDB results**: Implement `setStereoConfig(ch, stereo)` using the highest-level API that works. Use `dispatch_after` (500ms-1s delay) before recalling settings, matching the existing codebase pattern.

### Step 3: Automated Self-Test (button in existing dialog)

Add a "Test Stereo" button to the existing Move Channel dialog (`showMoveDialog()`). No keyboard shortcuts — they don't work in dLive Director.

**Test flow** (uses source channel spinbox value as test channel):

1. Read test channel from source spinbox
2. Verify it's mono
3. Snapshot Type A data for ch and ch+1 using `readExtDataA()`
4. Call `setStereoConfig(ch, true)` — make ch+ch+1 stereo
5. Wait 1s (`dispatch_after`)
6. Verify `isChannelStereo(ch) == true`
7. Recall Type A settings to ch
8. Re-read Type A data, compare byte-by-byte with step 3
9. Report pass/fail per processor (DigiTube, HPF, LPF, Compressor, GateSCPEQ, Gate, PEQ)
10. Restore: `setStereoConfig(ch, false)`, wait 1s, recall original settings
11. Update status label with results

### Step 4: moveChannel Stereo Wrapper

Add `moveChannelStereo(src, dst, keepPatching)`:

```
1. srcStereo = isChannelStereo(src)
2. If !srcStereo → fall through to existing moveChannel()
3. If srcStereo:
   a. Stereo pair = [src, src+1]
   b. Snapshot ALL channels in affected range (both channels of pair)
   c. Determine target stereo config needed
   d. If target position requires config change:
      - Apply setStereoConfig()
      - Wait for reset (dispatch_after)
   e. Recall Type A settings to new positions
```

Update dialog's Move button (line 2087) to call `moveChannelStereo`.

### Step 5: UI Dialog Updates (reuse existing Move Channel dialog)

All UI goes into the existing `showMoveDialog()` — no new dialogs or keyboard shortcuts.

- Add stereo status labels next to source/destination spinboxes: `[Mono]` or `[Stereo (N+N+1)]`
- Connect spinbox `valueChanged` to update labels via `isChannelStereo()`
- Show warning when move involves stereo↔mono conversion
- Add "Test Stereo" button for the automated self-test (Step 3)

## Files to Modify

- `/Users/sfx/Programavimas/dLive-patch/src/plugin_main.mm` — all implementation changes
- `/Users/sfx/Programavimas/dLive-patch/src/lldb_findings.h` — addresses already present (`Addr::Helpers_ChannelIsStereo`, `Addr::AudioCoreDM_NewStereoConfig`, `Addr::App_NewInputConfig`)

## Key Existing Functions to Reuse

- `snapshotChannel()` / `recallChannel()` (lines 1226, 1416) — already handle Type A correctly
- `readExtDataA()` (line 2132) — reads Type A data for comparison
- `dumpChannelData()` (line 2166) — human-readable hex dump
- `MAKE_KEY()` macro (line 60) — creates sChannelStripKey as uint64_t
- `g_CPRHelpersInstance()` — CPRHelpers singleton
- `MCEventFilter` (line 2098) — add Ctrl+Shift+T here

## Implementation Order

1. **Step 1 + Step 5** — Stereo detection + UI labels (can build & test immediately)
2. **Step 2** — LLDB probing session (user does this manually, shares results)
3. **Step 3** — Automated self-test (after LLDB results confirm config change API)
4. **Step 4** — Full stereo move wrapper

## Verification

1. **Build**: `make` — must compile without errors
2. **Stereo detection**: Launch plugin, check logs for ch 0-7 stereo status
3. **Config change**: Run Ctrl+Shift+T test, verify settings survive round-trip in logs
4. **Move test**: Set up channels with distinct Type A settings, move with stereo conversion, verify in UI

## Risks

- **NewStereoConfig signature unknown**: Highest risk item. Will try most likely signature first, fall back to `App_NewInputConfig` or LLDB probing
- **Processing object offsets may differ for stereo**: The `chOffset` values (2,5,6,7,8,9,10) for Type A are hardcoded for mono. Test adds vtable verification scan after stereo change
- **Reset timing**: Config change reset is asynchronous. Start with 1s delay, adjust if needed

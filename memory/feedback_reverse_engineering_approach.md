---
name: Fastest reverse engineering approach for dLive objects
description: Proven techniques for finding and accessing net objects in dLive Director — avoid slow exploratory scanning, go straight to MIDI/CSV paths
type: feedback
---

Don't scan memory blindly for objects. Follow the **existing code paths** instead:

1. **Find the MIDI handler first** — `MIDISet*` functions show the exact object layout (field offsets, pointer dereference patterns) AND work offline because they use `InformOtherObjects` instead of `SyscallSendMessage`. Disassemble the MIDI function (~30 lines), get the full read/write recipe in one shot.

2. **Find objects via gRegistryRouter local table** — all net objects live at `router+0x3a9820[index]`. Scan by vtable to find them. Don't scan InputChannel fields, AudioCoreDM fields, or socket managers — those are dead ends for objects like cAnalogueInput that aren't stored on channels.

3. **Use CSV import path to understand message format** — `SendPreampData` shows exact message versions (0x1001=gain UWORD, 0x1004=pad UBYTE, 0x1003=phantom UBYTE) and the objectId/handle mechanism. But for offline writes, skip messages entirely and use MIDI functions.

**Why:** Previous session burned all tokens (~10 min) doing: vtable scans of ch0 fields (0x00-0x600), sub-object deep probes (ch0[16][28] false positive), socket proxy hunting, network connection exploration, PostLocalMessage disassembly — all dead ends. The answer was: disassemble MIDISetGain (30 lines) → see layout → find objects in router table → done.

**How to apply:** For any new data type (e.g., digital trim, output patching), first search for its MIDI handler or CSV import function. Disassemble that. It reveals the object layout and the write mechanism. Then find instances via router table vtable scan.

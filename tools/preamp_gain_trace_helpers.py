import lldb
import time
from pathlib import Path

TRACE_FILE = Path("/tmp/preamp_gain_trace.txt")


def init_trace():
    TRACE_FILE.write_text("")
    print(f"[LLDB] compact trace will be written to {TRACE_FILE}")


def _signed16(v):
    if v is None:
        return None
    v &= 0xFFFF
    return v - 0x10000 if (v & 0x8000) else v


def _reg_value(frame, reg_name):
    regs = frame.GetRegisters()
    for reg_set in regs:
        name = reg_set.GetName() or ""
        if "General Purpose" not in name:
            continue
        for i in range(reg_set.GetNumChildren()):
            reg = reg_set.GetChildAtIndex(i)
            if reg.GetName() != reg_name:
                continue
            value = reg.GetValue()
            if not value:
                return None
            try:
                return int(value, 16)
            except Exception:
                return None
    return None


def _read_u8(process, addr):
    if not addr:
        return None
    err = lldb.SBError()
    data = process.ReadMemory(addr, 1, err)
    if err.Success() and len(data) == 1:
        return int.from_bytes(data, "little")
    return None


def _read_s16(process, addr):
    if not addr:
        return None
    err = lldb.SBError()
    data = process.ReadMemory(addr, 2, err)
    if err.Success() and len(data) == 2:
        return _signed16(int.from_bytes(data, "little", signed=False))
    return None


def _write_trace(frame, label, extra=None, max_frames=8):
    thread = frame.GetThread()
    lines = [f"\n=== {label} @ {time.strftime('%H:%M:%S')} ==="]
    if extra:
        lines.append(extra)
    depth = min(thread.GetNumFrames(), max_frames)
    for idx in range(depth):
        f = thread.GetFrameAtIndex(idx)
        mod = f.GetModule().GetFileSpec().GetFilename()
        fn = f.GetDisplayFunctionName() or f.GetFunctionName() or "<unknown>"
        lines.append(f"#{idx} {mod}!{fn}")
    with TRACE_FILE.open("a") as fp:
        fp.write("\n".join(lines) + "\n")


def _continue(frame):
    process = frame.GetThread().GetProcess()
    process.Continue()
    return False


def _fmt_regs(frame, names):
    parts = []
    for name in names:
        value = _reg_value(frame, name)
        if value is not None:
            parts.append(f"{name}=0x{value:x}")
    return " ".join(parts)


def bp_gain_ui(frame, bp_loc, _dict):
    _write_trace(frame, "UI GainValuePress/Release")
    return _continue(frame)


def bp_high_rotary(frame, bp_loc, _dict):
    raw = _reg_value(frame, "rsi")
    _write_trace(frame, "HIGH DL5000PreampGainRotary", f"raw={raw}")
    return _continue(frame)


def bp_selector_uword(frame, bp_loc, _dict):
    _write_trace(frame, "HIGH DL5000ControlChanged(UWORD)", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]))
    return _continue(frame)


def bp_selector_ubyte(frame, bp_loc, _dict):
    _write_trace(frame, "HIGH DL5000ControlChanged(UBYTE)", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]))
    return _continue(frame)


def bp_high_update(frame, bp_loc, _dict):
    stereo = _reg_value(frame, "r9")
    _write_trace(frame, "HIGH UpdatePreampMembersByAudioSource", f"stereo={stereo}")
    return _continue(frame)


def bp_selector_inform_preamp(frame, bp_loc, _dict):
    _write_trace(frame, "HIGH InformDL5000ControlSurfacePreAmpControls", _fmt_regs(frame, ["rdi", "rsi", "rdx"]))
    return _continue(frame)


def bp_selector_update_surface(frame, bp_loc, _dict):
    _write_trace(frame, "HIGH UpdateDL5000ControlSurfaceControls", _fmt_regs(frame, ["rdi", "rsi", "rdx"]))
    return _continue(frame)


def bp_mid_midi_gain(frame, bp_loc, _dict):
    gain = _signed16(_reg_value(frame, "rsi"))
    _write_trace(frame, "MID cAnalogueInput::MIDISetGain", f"gain={gain}")
    return _continue(frame)


def bp_low_setstatus(frame, bp_loc, _dict):
    process = frame.GetThread().GetProcess()
    gain = _read_s16(process, _reg_value(frame, "rsi"))
    pad = _read_u8(process, _reg_value(frame, "rdx"))
    phantom = _read_u8(process, _reg_value(frame, "rcx"))
    _write_trace(frame, "LOW cAnalogueInput::SetStatus", f"gain={gain} pad={pad} phantom={phantom}")
    return _continue(frame)


def bp_low_inform_gain(frame, bp_loc, _dict):
    process = frame.GetThread().GetProcess()
    gain = _read_s16(process, _reg_value(frame, "rsi"))
    _write_trace(frame, "LOW InformOtherObjectsOfGainChange", f"gain={gain}")
    return _continue(frame)


def bp_stagebox_uword(frame, bp_loc, _dict):
    _write_trace(frame, "MID InputChannelUWordStageBoxParam", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]))
    return _continue(frame)


def bp_stagebox_changed_short(frame, bp_loc, _dict):
    _write_trace(frame, "MID StageBoxControlChanged(short*)", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]))
    return _continue(frame)


def bp_stagebox_changed_short2(frame, bp_loc, _dict):
    _write_trace(frame, "MID StageBoxControlChanged(short*,short*)", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]))
    return _continue(frame)


def bp_rotary_gesture(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "ROTARY"
    _write_trace(frame, f"UI {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx"]), max_frames=5)
    return _continue(frame)

import lldb
import time
from pathlib import Path

TRACE_FILE = Path("/tmp/scene_recall_trace.txt")


def init_trace():
    TRACE_FILE.write_text("")
    print(f"[LLDB] scene recall trace will be written to {TRACE_FILE}")


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


def _read_c_string(process, addr, limit=128):
    if not addr:
        return None
    err = lldb.SBError()
    out = bytearray()
    for i in range(limit):
        chunk = process.ReadMemory(addr + i, 1, err)
        if not err.Success() or len(chunk) != 1:
            break
        if chunk == b"\x00":
            break
        out.extend(chunk)
    if not out:
        return None
    try:
        return out.decode("utf-8", errors="replace")
    except Exception:
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
    frame.GetThread().GetProcess().Continue()
    return False


def _fmt_regs(frame, names):
    parts = []
    for name in names:
        value = _reg_value(frame, name)
        if value is not None:
            parts.append(f"{name}=0x{value:x}")
    return " ".join(parts)


def bp_scene_recalled_msg(frame, bp_loc, _dict):
    _write_trace(frame, "SCENE SceneRecalled(cAHNetMessage&)", _fmt_regs(frame, ["rdi", "rsi"]))
    return _continue(frame)


def bp_scene_recalled_target(frame, bp_loc, _dict):
    target = _reg_value(frame, "rsi")
    scene = _reg_value(frame, "rdx")
    extra = f"target={target} scene={scene}"
    _write_trace(frame, "SCENE SceneRecalled(target, scene)", extra)
    return _continue(frame)


def bp_scene_current_go(frame, bp_loc, _dict):
    _write_trace(frame, "SCENE CurrentAndGoSceneSet(cAHNetMessage&)", _fmt_regs(frame, ["rdi", "rsi"]))
    return _continue(frame)


def bp_scene_current_settings(frame, bp_loc, _dict):
    _write_trace(frame, "SCENE SceneCurrentSettingsRecalled()", _fmt_regs(frame, ["rdi"]))
    return _continue(frame)


def bp_scene_signal(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "SCENE SIGNAL"
    _write_trace(frame, f"SCENE {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx"]))
    return _continue(frame)


def bp_preamp_form(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "PREAMP"
    _write_trace(frame, f"PREAMP {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx"]), max_frames=6)
    return _continue(frame)


def bp_source_assign(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "SRC"
    _write_trace(frame, f"SRC {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx"]), max_frames=6)
    return _continue(frame)


def bp_preamp_overview(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "OVR"
    _write_trace(frame, f"OVR {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx"]), max_frames=6)
    return _continue(frame)


def bp_selector_preamp(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "SELECTOR"
    _write_trace(frame, f"SELECTOR {fn}", _fmt_regs(frame, ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]), max_frames=7)
    return _continue(frame)

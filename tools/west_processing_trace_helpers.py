import lldb
import time
from pathlib import Path

TRACE_FILE = Path("/tmp/west_processing_trace.txt")


def init_trace(path=None):
    global TRACE_FILE
    if path:
        TRACE_FILE = Path(path)
    TRACE_FILE.write_text("")
    print(f"[LLDB] west-processing trace will be written to {TRACE_FILE}")


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


def _read_c_string(process, addr, limit=64):
    if not addr:
        return None
    err = lldb.SBError()
    data = process.ReadCStringFromMemory(addr, limit, err)
    if err.Success():
        return data
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


def bp_west_method(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "<unknown>"
    process = frame.GetThread().GetProcess()
    rsi = _reg_value(frame, "rsi")
    rdx = _reg_value(frame, "rdx")
    extra_parts = []
    if rsi is not None:
        extra_parts.append(f"rsi=0x{rsi:x}")
        val = _read_u8(process, rsi)
        if val is not None:
            extra_parts.append(f"*rsi_u8={val}")
    if rdx is not None:
        extra_parts.append(f"rdx=0x{rdx:x}")
        val = _read_u8(process, rdx)
        if val is not None:
            extra_parts.append(f"*rdx_u8={val}")
    _write_trace(frame, fn, " ".join(extra_parts) if extra_parts else None)
    return _continue(frame)


def bp_log_marker(frame, bp_loc, _dict):
    fn = frame.GetDisplayFunctionName() or frame.GetFunctionName() or "<unknown>"
    _write_trace(frame, fn)
    return _continue(frame)

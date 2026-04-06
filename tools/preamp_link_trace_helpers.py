import lldb
import datetime

LOG = "/tmp/preamp_link_trace.log"

def _write(line):
    with open(LOG, "a") as f:
        f.write(line + "\n")

def _reg(frame, name):
    try:
        return int(frame.FindRegister(name).GetValue(), 16)
    except Exception:
        return 0

def _read_src(proc, addr):
    if not addr:
        return "(null)"
    err = lldb.SBError()
    typ = proc.ReadUnsignedFromMemory(addr, 4, err)
    if not err.Success():
        return "(badread)"
    num = proc.ReadUnsignedFromMemory(addr + 4, 2, err)
    return "type=0x%x num=0x%x" % (typ, num)

def _bt(frame, depth=5):
    thread = frame.GetThread()
    out = []
    for i in range(1, min(depth + 1, thread.GetNumFrames())):
        nm = thread.GetFrameAtIndex(i).GetFunctionName() or "?"
        out.append(nm)
    return " <- ".join(out)

def on_LinkInputPreAmp(frame, bp_loc, dict):
    rdi = _reg(frame, "rdi")
    rsi = _reg(frame, "rsi") & 0xff
    rdx = _reg(frame, "rdx") & 0xff
    rcx = _reg(frame, "rcx") & 0xff
    _write("[LinkInputPreAmp] this=0x%x chan=%d conn=%d arg3=%d" % (rdi, rsi, rdx, rcx))
    _write("  caller: " + _bt(frame))
    return False

def on_LinkSurfacePreAmp(frame, bp_loc, dict):
    proc = frame.GetThread().GetProcess()
    rdi = _reg(frame, "rdi")
    esi = _reg(frame, "rsi") & 0xff
    edx = _reg(frame, "rdx") & 0xff
    ecx = _reg(frame, "rcx") & 0xffff
    r8  = _reg(frame, "r8")
    src = _read_src(proc, r8)
    _write("[LinkSurfacePreAmp] this=0x%x type=%d chan=%d u16=0x%x src=%s" %
           (rdi, esi, edx, ecx, src))
    _write("  caller: " + _bt(frame))
    return False

def on_HaveChangedSource(frame, bp_loc, dict):
    proc = frame.GetThread().GetProcess()
    rdi = _reg(frame, "rdi")
    esi = _reg(frame, "rsi")
    rdx = _reg(frame, "rdx")
    ecx = _reg(frame, "rcx") & 0xffff
    r8  = _reg(frame, "r8") & 0xff
    src = _read_src(proc, rdx)
    _write("[HaveChangedSource] this=0x%x event=%d chan=%d stripType=%d src=%s" %
           (rdi, esi, ecx, r8, src))
    _write("  caller: " + _bt(frame))
    return False

def on_AboutToChangeSource(frame, bp_loc, dict):
    proc = frame.GetThread().GetProcess()
    rdi = _reg(frame, "rdi")
    esi = _reg(frame, "rsi")
    rdx = _reg(frame, "rdx")
    ecx = _reg(frame, "rcx") & 0xffff
    r8  = _reg(frame, "r8") & 0xff
    src = _read_src(proc, rdx)
    _write("[AboutToChangeSource] this=0x%x event=%d chan=%d stripType=%d src=%s" %
           (rdi, esi, ecx, r8, src))
    return False

def __lldb_init_module(debugger, internal_dict):
    _write("\n==== session start %s ====" % datetime.datetime.now().isoformat())
    print("preamp_link_trace: helpers loaded; logging to " + LOG)

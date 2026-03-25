"""
LLDB exploration script for dLive Director V2.11
Run with: lldb -s lldb_commands.txt "/Applications/dLive Director V2.11 copy.app/Contents/MacOS/dLive Director V2.11"
"""
import lldb

def explore_channel_exists(debugger, command, result, internal_dict):
    """Called when ChannelExists breakpoint is hit"""
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetFrameAtIndex(0)

    # x86_64 calling convention: this=rdi, arg1=rsi, arg2=rdx
    # ChannelExists is a static/non-member or member function
    # Need to check if 'this' pointer is used
    rdi = frame.FindRegister("rdi").GetValueAsUnsigned()
    rsi = frame.FindRegister("rsi").GetValueAsUnsigned()
    rdx = frame.FindRegister("rdx").GetValueAsUnsigned()

    print(f"[ChannelExists] rdi=0x{rdi:x} rsi=0x{rsi:x} rdx=0x{rdx:x}")
    print(f"  rsi bytes: {rsi & 0xFF} {(rsi >> 8) & 0xFF} {(rsi >> 16) & 0xFF} {(rsi >> 24) & 0xFF}")

def explore_channel_is_stereo(debugger, command, result, internal_dict):
    """Called when ChannelIsStereo breakpoint is hit"""
    target = debugger.GetSelectedTarget()
    process = target.GetProcess()
    thread = process.GetSelectedThread()
    frame = thread.GetFrameAtIndex(0)

    rdi = frame.FindRegister("rdi").GetValueAsUnsigned()
    rsi = frame.FindRegister("rsi").GetValueAsUnsigned()

    print(f"[ChannelIsStereo] rdi=0x{rdi:x} rsi=0x{rsi:x}")
    print(f"  rsi bytes: {rsi & 0xFF} {(rsi >> 8) & 0xFF}")

def __lldb_init_module(debugger, internal_dict):
    debugger.HandleCommand('command script add -f lldb_explore.explore_channel_exists ch_exists')
    debugger.HandleCommand('command script add -f lldb_explore.explore_channel_is_stereo ch_stereo')
    print("[lldb_explore] Commands registered: ch_exists, ch_stereo")

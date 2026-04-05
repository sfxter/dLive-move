#!/usr/bin/env python3
import argparse
import json
import os
import pty
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
LAUNCH = ROOT / "launch.sh"
LOG_PATH = ROOT / "movechannel.log"
ARTIFACTS_ROOT = ROOT / "tmp" / "self-test-runs"
DIRECTOR_COMM_NAMES = ("dLive Director V2.11", "dLive Director V2.02")
SCREENSHOT_SETTLE_SECONDS = 2.5
SHOW_NAME_LIMIT = 16


@dataclass
class Scenario:
    name: str
    description: str
    env: Dict[str, str]
    expected_channels: List[int]
    pre_hook: Optional[str] = None
    screenshot_hook: Optional[str] = None

DEFAULT_SCENARIOS = [
    Scenario(
        name="good_oh_9_10_to_1_2",
        description="Move stereo OH 9/10 to 1/2 (known good UI case)",
        env={
            "MC_AUTOTEST_SRC": "9",
            "MC_AUTOTEST_DST": "1",
            "MC_AUTOTEST_NO_PREP": "1",
            "MC_AUTOTEST_SKIP_CHANNEL_VERIFY": "1",
            "MC_AUTOTEST_MOVE_PATCH": "0",
            "MC_AUTOTEST_SHIFT_MIXRACK_IO": "0",
            "MC_AUTOTEST_DUMP_PREAMP_UI": "1",
            "MC_AUTOTEST_EXIT": "0",
        },
        expected_channels=[1, 2],
    ),
    Scenario(
        name="bad_shift_25_26_to_5_6",
        description="Move channels 25/26 to 5/6 so OH 9/10 lands on 11/12 (known stale UI case)",
        env={
            "MC_AUTOTEST_SRC": "25",
            "MC_AUTOTEST_DST": "5",
            "MC_AUTOTEST_BLOCK_SIZE": "2",
            "MC_AUTOTEST_MODE": "mono2",
            "MC_AUTOTEST_NO_PREP": "1",
            "MC_AUTOTEST_SKIP_CHANNEL_VERIFY": "1",
            "MC_AUTOTEST_MOVE_PATCH": "0",
            "MC_AUTOTEST_SHIFT_MIXRACK_IO": "0",
            "MC_AUTOTEST_DUMP_PREAMP_UI": "1",
            "MC_AUTOTEST_EXIT": "0",
        },
        expected_channels=[11, 12],
    ),
]

SELECT_SCENARIOS = [
    Scenario(
        name="select_set_only",
        description="Select channel using UIManagerHolder::SetCurrentlySelectedChannel only",
        env={
            "MC_AUTOTEST_SELECT_ONLY": "1",
            "MC_AUTOTEST_EXIT": "0",
            "MC_AUTOTEST_SELECT_USE_SET": "1",
            "MC_AUTOTEST_SELECT_USE_LISTEN": "0",
            "MC_AUTOTEST_SELECT_USE_LISTENER": "0",
        },
        expected_channels=[11],
    ),
    Scenario(
        name="select_listen_only",
        description="Select channel using UIListenManager::ChangeChannel only",
        env={
            "MC_AUTOTEST_SELECT_ONLY": "1",
            "MC_AUTOTEST_EXIT": "0",
            "MC_AUTOTEST_SELECT_USE_SET": "0",
            "MC_AUTOTEST_SELECT_USE_LISTEN": "1",
            "MC_AUTOTEST_SELECT_USE_LISTENER": "0",
        },
        expected_channels=[11],
    ),
    Scenario(
        name="select_listener_strip1_zero_only",
        description="Select channel using UIChannelSelectListener only, stripType=1, zero-based channel",
        env={
            "MC_AUTOTEST_SELECT_ONLY": "1",
            "MC_AUTOTEST_EXIT": "0",
            "MC_AUTOTEST_SELECT_USE_SET": "0",
            "MC_AUTOTEST_SELECT_USE_LISTEN": "0",
            "MC_AUTOTEST_SELECT_USE_LISTENER": "1",
            "MC_AUTOTEST_SELECT_KEY_STRIP": "1",
            "MC_AUTOTEST_SELECT_KEY_CH_OFFSET": "0",
        },
        expected_channels=[11],
    ),
    Scenario(
        name="select_combo_strip1_zero",
        description="Select channel with full combo path, stripType=1, zero-based channel in key",
        env={
            "MC_AUTOTEST_SELECT_ONLY": "1",
            "MC_AUTOTEST_EXIT": "0",
            "MC_AUTOTEST_SELECT_USE_SET": "1",
            "MC_AUTOTEST_SELECT_USE_LISTEN": "1",
            "MC_AUTOTEST_SELECT_USE_LISTENER": "1",
            "MC_AUTOTEST_SELECT_KEY_STRIP": "1",
            "MC_AUTOTEST_SELECT_KEY_CH_OFFSET": "0",
        },
        expected_channels=[11],
    ),
    Scenario(
        name="select_listener_strip1_onebased",
        description="Select channel with listener only, stripType=1, one-based channel in key",
        env={
            "MC_AUTOTEST_SELECT_ONLY": "1",
            "MC_AUTOTEST_EXIT": "0",
            "MC_AUTOTEST_SELECT_USE_SET": "0",
            "MC_AUTOTEST_SELECT_USE_LISTEN": "0",
            "MC_AUTOTEST_SELECT_USE_LISTENER": "1",
            "MC_AUTOTEST_SELECT_KEY_STRIP": "1",
            "MC_AUTOTEST_SELECT_KEY_CH_OFFSET": "1",
        },
        expected_channels=[11],
    ),
]


def sh(cmd: str, env: Optional[Dict[str, str]] = None, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["bash", "-lc", cmd],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        env=env,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def running_processes() -> List[str]:
    result = subprocess.run(
        ["bash", "-lc", "ps -axo pid=,stat=,command="],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )
    lines: List[str] = []
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        if "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" in line:
            lines.append(line)
            continue
        if "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" in line:
            lines.append(line)
            continue
        if re.search(r"(^|/| )lldb($| )", line):
            lines.append(line)
    return lines


def running_director_processes_strict() -> List[str]:
    result = subprocess.run(
        ["bash", "-lc", "ps -axo pid=,stat=,command="],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )
    lines: List[str] = []
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split(None, 2)
        stat = parts[1] if len(parts) >= 2 else ""
        # macOS can occasionally leave behind orphaned UE entries for Director
        # that are no longer launchable or killable. Treat those as dead ghosts
        # so they do not block the whole self-test loop.
        if stat.startswith("UE"):
            continue
        if "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" in line:
            lines.append(line)
            continue
        if "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" in line:
            lines.append(line)
            continue
        if re.search(r"(^|/| )lldb($| )", line):
            lines.append(line)
    return lines


def running_director_app_names() -> List[str]:
    names: List[str] = []
    for line in running_director_processes_strict():
        if "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" in line:
            if "dLive Director V2.11" not in names:
                names.append("dLive Director V2.11")
        elif "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" in line:
            if "dLive Director V2.02" not in names:
                names.append("dLive Director V2.02")
    return names


def running_director_process_lines() -> List[str]:
    result = subprocess.run(
        ["bash", "-lc", "ps -axo pid=,stat=,command="],
        cwd=str(ROOT),
        text=True,
        capture_output=True,
        check=False,
    )
    lines: List[str] = []
    for raw in result.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        parts = line.split(None, 2)
        stat = parts[1] if len(parts) >= 2 else ""
        if stat.startswith("UE"):
            continue
        if "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" in line:
            lines.append(line)
            continue
        if "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" in line:
            lines.append(line)
            continue
    return lines


def ensure_single_director_instance(context: str) -> None:
    lines = running_director_process_lines()
    if len(lines) > 1:
        raise RuntimeError(
            f"More than one Director instance detected {context}. Refusing to continue.\n"
            + "\n".join(lines)
        )


def ensure_clean_state() -> None:
    lines = running_director_processes_strict()
    if lines:
        raise RuntimeError(
            "Director/LLDB processes are still running. Refusing to launch until clean.\n"
            + "\n".join(lines)
        )


def kill_existing_instances() -> None:
    for app_name in ("dLive Director V2.11", "dLive Director V2.02"):
        try:
            subprocess.run(
                ["bash", "-lc", f"osascript -e 'tell application \"{app_name}\" to quit' || true"],
                cwd=str(ROOT),
                text=True,
                capture_output=True,
                check=False,
                timeout=2.0,
            )
        except subprocess.TimeoutExpired:
            pass
    sh('pkill -f "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" || true', check=False)
    sh('pkill -f "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" || true', check=False)
    sh('pkill -x "dLive Director V2.11" || true', check=False)
    sh('pkill -x "dLive Director V2.02" || true', check=False)
    sh('pkill -f "dLive Director" || true', check=False)
    sh("pkill -x lldb || true", check=False)
    deadline = time.time() + 10.0
    while time.time() < deadline:
        if not running_director_processes_strict():
            return
        time.sleep(0.25)
        sh('pkill -9 -f "dLive Director V2.11.app/Contents/MacOS/dLive Director V2.11" || true', check=False)
        sh('pkill -9 -f "dLive Director V2.02.app/Contents/MacOS/dLive Director V2.02" || true', check=False)
        sh('pkill -9 -x "dLive Director V2.11" || true', check=False)
        sh('pkill -9 -x "dLive Director V2.02" || true', check=False)
        sh('pkill -9 -f "dLive Director" || true', check=False)
        sh("pkill -9 -x lldb || true", check=False)
    lines = running_director_processes_strict()
    if lines:
        raise RuntimeError("Failed to kill existing Director/LLDB processes:\n" + "\n".join(lines))


def wait_for_log(pattern: str, timeout: float) -> str:
    deadline = time.time() + timeout
    compiled = re.compile(pattern)
    last_text = ""
    while time.time() < deadline:
        if LOG_PATH.exists():
            last_text = LOG_PATH.read_text(errors="replace")
            if "An instance of dLive Director is already running." in last_text:
                raise RuntimeError("Director reported a false single-instance collision during launch.")
            if compiled.search(last_text):
                return last_text
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for log pattern {pattern!r}")


def wait_for_any_log(patterns: List[str], timeout: float) -> tuple[str, str]:
    deadline = time.time() + timeout
    compiled = [(pattern, re.compile(pattern)) for pattern in patterns]
    last_text = ""
    while time.time() < deadline:
        if LOG_PATH.exists():
            last_text = LOG_PATH.read_text(errors="replace")
            if "An instance of dLive Director is already running." in last_text:
                raise RuntimeError("Director reported a false single-instance collision during scenario run.")
            for pattern, regex in compiled:
                if regex.search(last_text):
                    return pattern, last_text
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for any log pattern: {patterns!r}")


def launch_editor(extra_env: Dict[str, str]) -> subprocess.Popen:
    ensure_clean_state()
    env = os.environ.copy()
    env.update(extra_env)
    env.setdefault("MC_PATCH_DIRECTOR_SINGLETON_KEY", "1")
    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(
        ["bash", "-lc", str(LAUNCH)],
        cwd=str(ROOT),
        env=env,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        start_new_session=True,
        close_fds=True,
    )
    os.close(slave_fd)
    proc._pty_master_fd = master_fd
    return proc


def terminate_process_tree(proc: subprocess.Popen) -> None:
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
        pass
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        time.sleep(0.2)
    if proc.poll() is None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            pass
    master_fd = getattr(proc, "_pty_master_fd", None)
    if master_fd is not None:
        try:
            os.close(master_fd)
        except OSError:
            pass


def run_optional_hook(hook: Optional[str], label: str) -> None:
    if not hook:
        return
    print(f"[self-test] running {label}: {hook}")
    sh(hook)


def activate_director() -> None:
    for app_name in running_director_app_names():
        subprocess.run(
            [
                "bash",
                "-lc",
                f"osascript -e 'tell application \"{app_name}\" to reopen' "
                f"-e 'tell application \"{app_name}\" to activate' || true",
            ],
            cwd=str(ROOT),
            text=True,
            capture_output=True,
            check=False,
        )
    time.sleep(1.5)


def capture_screenshot(dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    activate_director()
    time.sleep(SCREENSHOT_SETTLE_SECONDS)
    sh(f'screencapture -x "{dest}"')


def wait_for_visual_settle() -> None:
    activate_director()
    time.sleep(1.5)


def wait_for_scenario_visual_settle(scenario: Scenario, status_path: Path) -> None:
    wait_for_visual_settle()
    if "MC_AUTOTEST_SRC" in scenario.env and "MC_AUTOTEST_DST" in scenario.env:
        append_status(status_path, "dLive Self-Test", "Waiting for UI to settle")
        activate_director()
        time.sleep(5.0)


def parse_final_preamp(log_text: str, channels: List[int]) -> Dict[str, Dict[str, str]]:
    out: Dict[str, Dict[str, str]] = {}
    pattern = re.compile(
        r"\[MC\]\[PREAMP\] final-verify ch (\d+): source=\{type=(\d+),num=(\d+)\} socket=(\d+) gain=(-?\d+) pad=(\d+) phantom=(\d+)"
    )
    wanted = {str(ch) for ch in channels}
    for match in pattern.finditer(log_text):
        ch = match.group(1)
        if ch not in wanted:
            continue
        out[ch] = {
            "source_type": match.group(2),
            "source_num": match.group(3),
            "socket": match.group(4),
            "gain": match.group(5),
            "pad": match.group(6),
            "phantom": match.group(7),
        }
    return out


def parse_recent_errors(log_text: str) -> List[str]:
    return [line for line in log_text.splitlines() if "ERROR:" in line][-20:]


def parse_selection_state(log_text: str) -> Dict[str, object]:
    out: Dict[str, object] = {}
    after_pattern = re.compile(
        r"selectInputChannelForUI: after select stripValid=(\d+) stripType=(\d+) stripCh=(-?\d+) selectedInput=(-?\d+)"
    )
    final_pattern = re.compile(
        r"\[(?:MC\]\[SELECTTEST|MC\]\[AUTOTEST)\] final selection: stripValid=(\d+) stripType=(\d+) stripCh=(-?\d+) selectedInput=(-?\d+)"
    )
    matches = list(after_pattern.finditer(log_text))
    if matches:
        m = matches[-1]
        out["after_select"] = {
            "strip_valid": int(m.group(1)),
            "strip_type": int(m.group(2)),
            "strip_channel": int(m.group(3)),
            "selected_input": int(m.group(4)),
        }
    final_matches = list(final_pattern.finditer(log_text))
    if final_matches:
        m = final_matches[-1]
        out["final_selection"] = {
            "strip_valid": int(m.group(1)),
            "strip_type": int(m.group(2)),
            "strip_channel": int(m.group(3)),
            "selected_input": int(m.group(4)),
        }
    return out


def parse_timing_breakdown(log_text: str) -> Dict[str, object]:
    out: Dict[str, object] = {"steps": {}, "move_phases": []}

    timing_pattern = re.compile(r"\[MC\]\[TIMING\] step=([A-Za-z0-9_]+) ms=(\d+)(?: detail=(.*))?")
    for match in timing_pattern.finditer(log_text):
        step = match.group(1)
        entry: Dict[str, object] = {"ms": int(match.group(2))}
        detail = match.group(3)
        if detail:
            entry["detail"] = detail.strip()
        out["steps"][step] = entry

    phase_pattern = re.compile(r"\[MC\]\[\s*(\d+)ms\] (Phase: .+)")
    phase_matches = list(phase_pattern.finditer(log_text))
    for idx, match in enumerate(phase_matches):
        absolute_ms = int(match.group(1))
        label = match.group(2).strip()
        duration_ms = None
        if idx + 1 < len(phase_matches):
            duration_ms = int(phase_matches[idx + 1].group(1)) - absolute_ms
        out["move_phases"].append(
            {
                "label": label,
                "absolute_ms": absolute_ms,
                "duration_to_next_ms": duration_ms,
            }
        )
    return out


def copy_log(dest: Path) -> str:
    text = LOG_PATH.read_text(errors="replace") if LOG_PATH.exists() else ""
    dest.write_text(text)
    return text


def write_status(status_path: Path, title: str, detail: str = "") -> None:
    status_path.parent.mkdir(parents=True, exist_ok=True)
    text = title.strip()
    if detail.strip():
        text += "\n" + detail.strip()
    status_path.write_text(text + "\n")


def append_status(status_path: Path, title: str, detail: str) -> None:
    existing: List[str] = []
    if status_path.exists():
        existing = [line.rstrip() for line in status_path.read_text(errors="replace").splitlines()]
    if not existing:
        existing = [title.strip()]
    elif existing[0].strip() != title.strip():
        existing[0] = title.strip()
    detail = detail.strip()
    if detail:
        existing.append(detail)
    existing = existing[:1] + existing[1:][-8:]
    status_path.write_text("\n".join(existing) + "\n")


def clear_status(status_path: Path) -> None:
    try:
        status_path.write_text("")
    except Exception:
        pass


def make_saved_show_name(scenario_name: str) -> str:
    base = re.sub(r"[^A-Za-z0-9_]+", "", scenario_name).upper()
    if not base:
        base = "AUTO"
    stamp = time.strftime("%H%M%S")
    room_for_base = max(1, SHOW_NAME_LIMIT - len(stamp) - 1)
    return f"{base[:room_for_base]}_{stamp}"[:SHOW_NAME_LIMIT]


def run_scenario(scenario: Scenario, run_dir: Path, launch_env: Dict[str, str], show_name: str, status_window=None) -> Dict[str, object]:
    print(f"[self-test] scenario: {scenario.name}")
    kill_existing_instances()
    ensure_clean_state()
    try:
        LOG_PATH.unlink()
    except FileNotFoundError:
        pass

    status_path = run_dir / f"{scenario.name}.status.txt"
    write_status(status_path, "dLive Self-Test", f"Launching editor for {scenario.name}")

    env = dict(scenario.env)
    env.update(launch_env)
    env["MC_AUTOTEST_STATUS_FILE"] = str(status_path)
    saved_show_name = None
    if show_name:
        env["MC_AUTOTEST_RECALL_SHOW"] = show_name
    if scenario.expected_channels:
        env["MC_AUTOTEST_SELECT_CH"] = str(scenario.expected_channels[0])
    enable_save_recall = env.get("MC_AUTOTEST_ENABLE_SAVE_RECALL", "0") == "1"
    if "MC_AUTOTEST_SRC" in scenario.env and "MC_AUTOTEST_DST" in scenario.env and enable_save_recall:
        saved_show_name = make_saved_show_name(scenario.name)
        env["MC_AUTOTEST_SAVE_RECALL_SHOW"] = saved_show_name
    proc = launch_editor(env)
    live_log_text = ""

    try:
        live_log_text = wait_for_log(r"\[MC\] ===== MoveChannel ready =====", timeout=40.0)
        ensure_single_director_instance("after launch")
        if show_name:
            append_status(status_path, "dLive Self-Test", f"Recalling SHOW {show_name}")
            live_log_text = wait_for_log(
                r"\[MC\] recallShowByName\('" + re.escape(show_name) + r"'\): recalling key",
                timeout=60.0,
            )
            ensure_single_director_instance(f"after recalling SHOW {show_name}")
            if f"[MC][AUTOTEST] failed to recall SHOW '{show_name}'" in live_log_text:
                raise RuntimeError(f"Failed to recall SHOW {show_name!r}")
        run_optional_hook(scenario.pre_hook, f"{scenario.name} pre-hook")

        if scenario.env.get("MC_AUTOTEST_SELECT_ONLY") == "1":
            detail = f"Selecting channel {scenario.expected_channels[0]}" if scenario.expected_channels else "Selecting channel"
            append_status(status_path, "dLive Self-Test", detail)
            completion_pattern, live_log_text = wait_for_any_log(
                [
                    r"\[MC\]\[SELECTTEST\] RESULT: PASS",
                    r"\[MC\]\[SELECTTEST\] RESULT: FAIL",
                    r"\[MC\] ERROR:",
                ],
                timeout=60.0,
            )
        elif "MC_AUTOTEST_SRC" in scenario.env and "MC_AUTOTEST_DST" in scenario.env:
            block_size = int(scenario.env.get("MC_AUTOTEST_BLOCK_SIZE", "1"))
            src = int(scenario.env["MC_AUTOTEST_SRC"])
            dst = int(scenario.env["MC_AUTOTEST_DST"])
            if block_size > 1:
                detail = f"Moving channels {src}-{src + block_size - 1} to {dst}-{dst + block_size - 1}"
            else:
                detail = f"Moving channel {src} to {dst}"
            append_status(status_path, "dLive Self-Test", detail)
            if saved_show_name:
                append_status(status_path, "dLive Self-Test", f"Saving and recalling SHOW {saved_show_name}")
                completion_patterns = [
                    r"\[MC\]\[AUTOTEST\] RESULT: PASS",
                    r"\[MC\]\[AUTOTEST\] RESULT: FAIL",
                    r"\[MC\] ERROR:",
                ]
                timeout = 240.0
            else:
                completion_patterns = [
                    r"\[MC\]\[AUTOTEST\] RESULT: PASS",
                    r"\[MC\]\[AUTOTEST\] RESULT: FAIL",
                    r"\[MC\]\[\s*\d+ms\] Phase: move complete",
                    r"\[MC\] ERROR:",
                ]
                timeout = 180.0
            completion_pattern, live_log_text = wait_for_any_log(
                completion_patterns,
                timeout=timeout,
            )
        elif "MC_AUTOTEST_COPY_SRC" in scenario.env and "MC_AUTOTEST_COPY_DST" in scenario.env:
            append_status(
                status_path,
                "dLive Self-Test",
                f"Copy/paste channels {scenario.env['MC_AUTOTEST_COPY_SRC']} -> {scenario.env['MC_AUTOTEST_COPY_DST']}",
            )
            completion_pattern, live_log_text = wait_for_any_log(
                [
                    r"\[MC\]\[COPYTEST\] RESULT: PASS",
                    r"\[MC\]\[COPYTEST\] RESULT: FAIL",
                    r"\[MC\] ERROR:",
                ],
                timeout=180.0,
            )
        else:
            completion_pattern, live_log_text = wait_for_any_log(
                [
                    r"\[MC\]\[\s*\d+ms\] Phase: move complete",
                    r"\[MC\] ERROR:",
                ],
                timeout=120.0,
            )
        if scenario.expected_channels:
            if len(scenario.expected_channels) == 1:
                append_status(status_path, "dLive Self-Test", f"Selecting channel {scenario.expected_channels[0]}")
            else:
                append_status(
                    status_path,
                    "dLive Self-Test",
                    f"Selecting channel {scenario.expected_channels[0]} ({len(scenario.expected_channels)}-channel target)",
                )
        time.sleep(1.5)
        wait_for_scenario_visual_settle(scenario, status_path)
        ensure_single_director_instance("before screenshot capture")
        append_status(status_path, "dLive Self-Test", "Capturing screenshot")
        run_optional_hook(scenario.screenshot_hook, f"{scenario.name} screenshot-hook")
        screenshot_path = run_dir / f"{scenario.name}.png"
        capture_screenshot(screenshot_path)
        scenario_log_path = run_dir / f"{scenario.name}.log"
        artifact_log_text = copy_log(scenario_log_path)
        effective_log_text = artifact_log_text
        if len(live_log_text) > len(effective_log_text):
            effective_log_text = live_log_text
        if artifact_log_text != effective_log_text:
            scenario_log_path.write_text(effective_log_text)
        final_preamp = parse_final_preamp(effective_log_text, scenario.expected_channels)
        selection_state = parse_selection_state(effective_log_text)
        timing = parse_timing_breakdown(effective_log_text)
        errors = parse_recent_errors(effective_log_text)
        status = "complete"
        if "RESULT: FAIL" in completion_pattern or "RESULT: FAIL" in effective_log_text or "[MC] ERROR:" in effective_log_text:
            status = "failed"
        append_status(status_path, "dLive Self-Test", f"Scenario {scenario.name}: {status.upper()}")
        return {
            "name": scenario.name,
            "description": scenario.description,
            "show_name": show_name,
            "status": status,
            "completion_pattern": completion_pattern,
            "saved_show_name": saved_show_name,
            "log_path": str(scenario_log_path),
            "screenshot_path": str(screenshot_path),
            "final_preamp": final_preamp,
            "selection_state": selection_state,
            "timing": timing,
            "errors": errors,
        }
    except Exception as exc:
        screenshot_path = run_dir / f"{scenario.name}.png"
        try:
            wait_for_scenario_visual_settle(scenario, status_path)
            append_status(status_path, "dLive Self-Test", "Capturing failure screenshot")
            capture_screenshot(screenshot_path)
        except Exception:
            pass
        scenario_log_path = run_dir / f"{scenario.name}.log"
        artifact_log_text = copy_log(scenario_log_path)
        effective_log_text = artifact_log_text
        if len(live_log_text) > len(effective_log_text):
            effective_log_text = live_log_text
        if effective_log_text and artifact_log_text != effective_log_text:
            scenario_log_path.write_text(effective_log_text)
        return {
            "name": scenario.name,
            "description": scenario.description,
            "show_name": show_name,
            "status": "exception",
            "exception": str(exc),
            "saved_show_name": saved_show_name,
            "log_path": str(scenario_log_path),
            "screenshot_path": str(screenshot_path),
            "final_preamp": parse_final_preamp(effective_log_text, scenario.expected_channels),
            "selection_state": parse_selection_state(effective_log_text),
            "timing": parse_timing_breakdown(effective_log_text),
            "errors": parse_recent_errors(effective_log_text),
        }
    finally:
        clear_status(status_path)
        terminate_process_tree(proc)
        kill_existing_instances()
        ensure_clean_state()


def make_run_dir() -> Path:
    run_dir = ARTIFACTS_ROOT / time.strftime("%Y%m%d-%H%M%S")
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir


def main() -> int:
    parser = argparse.ArgumentParser(description="Repeatable dLive patch self-test loop.")
    parser.add_argument("--show-name", default="TESTING", help="Expected baseline show name.")
    parser.add_argument(
        "--mode",
        choices=["move", "select"],
        default="move",
        help="Run move scenarios or pure selection scenarios.",
    )
    parser.add_argument(
        "--log-level", default="2", help="MC_LOG_LEVEL for launched app (default: 2)."
    )
    parser.add_argument(
        "--show-log", default="0", help="MC_SHOW_LOG for launched app (default: 0)."
    )
    parser.add_argument(
        "--filter-socket-errors",
        default="1",
        help="MC_FILTER_SOCKET_TYPE_ERRORS for launched app (default: 1).",
    )
    parser.add_argument(
        "--scenario",
        action="append",
        help="Run only selected scenario name(s). Defaults to all scenarios in the chosen mode.",
    )
    args = parser.parse_args()

    scenario_pool = DEFAULT_SCENARIOS if args.mode == "move" else SELECT_SCENARIOS
    valid_names = {s.name for s in scenario_pool}
    if args.scenario:
        invalid = [name for name in args.scenario if name not in valid_names]
        if invalid:
            parser.error(f"invalid --scenario for mode {args.mode}: {', '.join(invalid)}")
    selected = [s for s in scenario_pool if not args.scenario or s.name in args.scenario]
    run_dir = make_run_dir()

    launch_env = {
        "MC_LOG_LEVEL": args.log_level,
        "MC_SHOW_LOG": args.show_log,
        "MC_FILTER_SOCKET_TYPE_ERRORS": args.filter_socket_errors,
    }
    for key, value in os.environ.items():
        if key.startswith(("MC_AUTOTEST_", "MC_EXPERIMENT_", "MC_ENABLE_", "MC_DISABLE_")):
            launch_env[key] = value

    summary = {
        "run_dir": str(run_dir),
        "show_name": args.show_name,
        "mode": args.mode,
        "scenarios": [],
    }
    status_window = None

    for scenario in selected:
        result = run_scenario(
            scenario,
            run_dir,
            launch_env=launch_env,
            show_name=args.show_name,
            status_window=status_window,
        )
        summary["scenarios"].append(result)

    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"[self-test] wrote summary to {summary_path}")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

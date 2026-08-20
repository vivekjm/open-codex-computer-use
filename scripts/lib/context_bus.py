#!/usr/bin/env python3
"""Codex-style Computer Use context bus.

Window2 targeting (one cursor per window/app), compact AX handoff, and a
shared HANDOFF.md that any Cursor session can Read instead of ingesting
raw MCP screenshots.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOME = Path.home()
BUS = Path(os.environ.get("OPEN_COMPUTER_USE_BUS_DIR", HOME / ".cursor" / "computer-use")).expanduser()
SESSIONS_DIR = BUS / "sessions"
REGISTRY = BUS / "sessions.json"
HANDOFF = BUS / "HANDOFF.md"
SUMMARY = BUS / "SUMMARY.md"
EVENTS = BUS / "events.jsonl"
PIP_COMMAND = Path(os.environ.get("OPEN_COMPUTER_USE_PIP_COMMAND", "/tmp/computer-use-pip.json"))
PIP_BIN = ROOT / "dist" / "Computer Use PiP.app" / "Contents" / "MacOS" / "ComputerUsePiP"

PALETTE = ["#606acc", "#0E7490", "#F59E0B", "#EC4899", "#22C55E", "#8B5CF6"]
FOCUSED_RE = re.compile(r"The focused UI element is (\d+)\b", re.I)
ELEMENT_RE = re.compile(r"^\s*(\d+)\s+(.+)$", re.M)
CHROMIUM_HINTS = ("chrome", "chromium", "electron", "edge", "brave", "arc")


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def atomic_write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temp.write_text(text)
    temp.replace(path)


def ocu_env() -> dict[str, str]:
    env = os.environ.copy()
    # MultiCursorOverlay is the sole cursor renderer; avoid a second OCU cursor.
    env["OPEN_COMPUTER_USE_VISUAL_CURSOR"] = "0"
    env.pop("OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS", None)
    env.pop("OPEN_COMPUTER_USE_VISUAL_CURSOR_DISABLE", None)
    return env


def load_registry() -> dict:
    if REGISTRY.exists():
        return json.loads(REGISTRY.read_text())
    return {"sessions": [], "updated_at": now_iso()}


def save_registry(data: dict) -> None:
    BUS.mkdir(parents=True, exist_ok=True)
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    active = [item for item in data.get("sessions", []) if item.get("status") == "active"]
    stopped = [item for item in data.get("sessions", []) if item.get("status") != "active"]
    stopped.sort(key=lambda item: item.get("updated_at") or "", reverse=True)
    data["sessions"] = active + stopped[:40]
    data["updated_at"] = now_iso()
    atomic_write_text(REGISTRY, json.dumps(data, indent=2) + "\n")


def session_dir(session_id: str) -> Path:
    path = SESSIONS_DIR / session_id
    path.mkdir(parents=True, exist_ok=True)
    return path


def slug(app: str) -> str:
    cleaned = re.sub(r"[^a-z0-9]+", "-", app.lower()).strip("-")
    return (cleaned or "app")[:24]


def expire_stale_sessions(registry: dict, max_idle_seconds: int = 15 * 60) -> None:
    now = datetime.now(timezone.utc)
    for item in registry.get("sessions", []):
        if item.get("status") != "active":
            continue
        raw = item.get("updated_at") or item.get("created_at")
        try:
            updated = datetime.fromisoformat(raw)
        except (TypeError, ValueError):
            updated = datetime.fromtimestamp(0, timezone.utc)
        if updated.tzinfo is None:
            updated = updated.replace(tzinfo=timezone.utc)
        if (now - updated).total_seconds() > max_idle_seconds:
            item["status"] = "stopped"
            item["cursor"] = {"x": None, "y": None}
            item["updated_at"] = now_iso()


def parse_focused(text: str) -> dict:
    match = FOCUSED_RE.search(text or "")
    if not match:
        return {"index": None, "label": None}
    idx = int(match.group(1))
    label = None
    for element in ELEMENT_RE.finditer(text):
        if int(element.group(1)) == idx:
            label = re.sub(r"\s+", " ", element.group(2)).strip()[:96]
            break
    return {"index": idx, "label": label}


def _cursor_label(value: str) -> str | None:
    value = re.sub(r"\s+", " ", value).strip().split(", Secondary Actions:", 1)[0]
    description = re.search(r"(?:Description|Title|Value):\s*(.+)$", value, re.I)
    label = (description.group(1) if description else value).strip()
    label = re.sub(
        r"^(?:button|text|generic element|checkbox|radio button|menu item)\s+",
        "",
        label,
        flags=re.I,
    )
    return label[:100] or None


def element_cursor_hint(text: str, element: int | None) -> tuple[str | None, int | None]:
    if element is None:
        return None, None
    rows = [(int(match.group(1)), _cursor_label(match.group(2))) for match in ELEMENT_RE.finditer(text or "")]
    label = next((value for index, value in rows if index == element), None)
    if not label:
        return None, None
    normalized = re.sub(r"\W+", "", label).lower()
    occurrence = 0
    for index, value in rows:
        if value and re.sub(r"\W+", "", value).lower() == normalized:
            occurrence += 1
        if index == element:
            break
    return label, occurrence


def append_event(session: dict, action: str, detail: dict | None = None) -> None:
    BUS.mkdir(parents=True, exist_ok=True)
    event = {
        "ts": now_iso(),
        "session": session.get("id"),
        "app": session.get("app"),
        "action": action,
        "focused": session.get("focused"),
        "cursor": session.get("cursor"),
        "detail": detail or {},
    }
    existing: list[str] = []
    if EVENTS.exists() and EVENTS.stat().st_size > 512_000:
        existing = EVENTS.read_text().splitlines()[-400:]
    line = json.dumps(event)
    if existing:
        atomic_write_text(EVENTS, "\n".join(existing + [line]) + "\n")
    else:
        with EVENTS.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    write_summary()


def write_summary() -> None:
    registry = load_registry() if REGISTRY.exists() else {"sessions": []}
    active = [item for item in registry.get("sessions", []) if item.get("status") == "active"]
    events: list[dict] = []
    if EVENTS.exists():
        for line in EVENTS.read_text().splitlines()[-40:]:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    lines = [
        "# Computer Use summary",
        "",
        "Rolling compact log for Cursor. Prefer this plus HANDOFF.md over raw MCP screenshots.",
        "",
        f"Updated: {now_iso()}",
        "",
        "## Active cursors",
        "",
    ]
    if not active:
        lines.append("None.")
    for item in active:
        focused = item.get("focused") or {}
        cursor = item.get("cursor") or {}
        label = focused.get("label") or "none"
        lines.append(
            f"- `{item['id']}` `{item['app']}` color `{item.get('color')}` "
            f"focused `{focused.get('index')}` {label} "
            f"cursor `({cursor.get('x')}, {cursor.get('y')})` "
            f"last `{item.get('last_action') or 'none'}`"
        )
    lines.extend(["", "## Recent events", ""])
    if not events:
        lines.append("None.")
    for event in reversed(events[-16:]):
        focused = event.get("focused") or {}
        detail = event.get("detail") or {}
        extra = ""
        if "element_index" in detail:
            extra = f" element {detail['element_index']}"
        elif "x" in detail and "y" in detail:
            extra = f" @({detail['x']},{detail['y']})"
        lines.append(
            f"- {event.get('ts')} `{event.get('session')}` {event.get('action')}{extra}"
            f" → focused `{focused.get('index')}` {focused.get('label') or ''}".rstrip()
        )
    atomic_write_text(SUMMARY, "\n".join(lines) + "\n")


def list_windows() -> list[dict]:
    rows = _list_windows_pip()
    if not rows:
        rows = _list_windows_ax()
    return rows


def _list_windows_pip() -> list[dict]:
    binary = PIP_BIN
    if not binary.exists():
        build = ROOT / "scripts" / "build-computer-use-pip.sh"
        if build.exists():
            subprocess.run([str(build)], check=False, capture_output=True)
    if not binary.exists():
        return []
    try:
        proc = subprocess.run(
            [str(binary), "--list-windows"],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    raw = (proc.stdout or "").strip()
    if not raw:
        return []
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if isinstance(payload, dict):
        windows = payload.get("windows") or []
        height = payload.get("primary_height")
        if height:
            for window in windows:
                window.setdefault("primary_height", height)
        return windows
    return payload if isinstance(payload, list) else []


def _list_windows_ax() -> list[dict]:
    script = """
tell application "System Events"
    set output to ""
    repeat with p in application processes
        if background only of p is false then
            set pname to name of p as text
            try
                repeat with w in windows of p
                    set {x, y} to position of w
                    set {ww, hh} to size of w
                    set t to ""
                    try
                        set t to name of w as text
                    end try
                    set output to output & pname & tab & t & tab & x & tab & y & tab & ww & tab & hh & linefeed
                end repeat
            end try
        end if
    end repeat
    return output
end tell
"""
    try:
        proc = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    height = _desktop_height()
    rows = []
    for line in (proc.stdout or "").splitlines():
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        try:
            x, y, width, height_w = (float(parts[2]), float(parts[3]), float(parts[4]), float(parts[5]))
        except ValueError:
            continue
        appkit_y = height - y - height_w if height else 0
        rows.append(
            {
                "id": None,
                "app": parts[0],
                "bundle": "",
                "title": parts[1],
                "x": x,
                "y": y,
                "width": width,
                "height": height_w,
                "appkit_x": x,
                "appkit_y": appkit_y,
                "cursor_x": x + 28,
                "cursor_y": (height - y - 36) if height else None,
            }
        )
    return rows


def _desktop_height() -> float:
    try:
        out = subprocess.check_output(
            ["osascript", "-e", 'tell application "Finder" to get bounds of window of desktop'],
            text=True,
            timeout=4,
        )
        parts = [float(p.strip()) for p in out.split(",")]
        return parts[3] - parts[1]
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, ValueError, IndexError):
        return 0.0


def match_window(
    app: str,
    windows: list[dict] | None = None,
    window_id: int | None = None,
) -> dict | None:
    windows = windows if windows is not None else list_windows()
    if window_id is not None:
        exact = next((window for window in windows if int(window.get("id") or -1) == window_id), None)
        if exact:
            return exact
    target = app.lower().strip()
    hits = []
    for window in windows:
        owner = str(window.get("app") or "").lower()
        bundle = str(window.get("bundle") or "").lower()
        title = str(window.get("title") or "").lower()
        if (
            target == owner
            or target in owner
            or owner in target
            or target in bundle
            or target in title
            or ("simulator" in target and "simulator" in owner)
        ):
            hits.append(window)
    if not hits:
        return None
    return max(hits, key=lambda item: float(item.get("width") or 0) * float(item.get("height") or 0))


def cursor_point(window: dict, element: int | None = None, x: float | None = None, y: float | None = None) -> dict:
    origin_x = float(window.get("appkit_x", window.get("x") or 0) or 0)
    origin_y = window.get("appkit_y")
    width = float(window.get("width") or 0)
    height = float(window.get("height") or 0)
    rest_x = window.get("cursor_x")
    rest_y = window.get("cursor_y")
    if rest_x is None:
        rest_x = origin_x + 28
    if rest_y is None and origin_y is not None:
        rest_y = float(origin_y) + height - 36
    if x is not None and y is not None and origin_y is not None:
        cx = origin_x + float(x)
        cy = float(origin_y) + height - float(y)
    else:
        cx, cy = rest_x, rest_y
    if origin_y is not None and width and height and cx is not None and cy is not None:
        left, bottom = origin_x + 16, float(origin_y) + 16
        right, top = origin_x + width - 24, float(origin_y) + height - 24
        cx = min(max(float(cx), left), max(left, right))
        cy = min(max(float(cy), bottom), max(bottom, top))
    return {"x": None if cx is None else round(float(cx), 1), "y": None if cy is None else round(float(cy), 1)}


def bind_cursor(
    session: dict,
    element: int | None = None,
    x: float | None = None,
    y: float | None = None,
    windows: list[dict] | None = None,
    label: str | None = None,
    occurrence: int | None = None,
    window_id: int | None = None,
) -> dict:
    stored_id = ((session.get("window") or {}).get("id")) if isinstance(session.get("window"), dict) else None
    window = match_window(
        session.get("app") or "",
        windows,
        window_id=window_id if window_id is not None else stored_id,
    )
    if window:
        session["window"] = {
            "id": window.get("id"),
            "title": window.get("title"),
            "app": window.get("app"),
            "x": window.get("x"),
            "y": window.get("y"),
            "width": window.get("width"),
            "height": window.get("height"),
        }
        point = cursor_point(window, element=element, x=x, y=y)
        previous_label = (session.get("cursor") or {}).get("label")
        if label is not None:
            point["label"] = label
            point["occurrence"] = occurrence or 1
        elif x is not None and y is not None:
            point["label"] = None
            point["occurrence"] = None
        elif previous_label:
            point["label"] = previous_label
            point["occurrence"] = (session.get("cursor") or {}).get("occurrence", 1)
        session["cursor"] = point
    return session


def spawn(app: str, window_id: int | None = None) -> dict:
    registry = load_registry()
    expire_stale_sessions(registry)
    existing = next(
        (
            item for item in registry["sessions"]
            if item.get("app") == app
            and item.get("status") == "active"
            and (
                window_id is None
                or int(((item.get("window") or {}).get("id")) or -1) == window_id
            )
        ),
        None,
    )
    if existing:
        bind_cursor(existing, window_id=window_id)
        save_registry(registry)
        write_handoff(registry)
        write_pip_command(registry)
        write_summary()
        return existing
    used_colors = {item.get("color") for item in registry["sessions"] if item.get("status") == "active"}
    color = next((c for c in PALETTE if c not in used_colors), PALETTE[len(registry["sessions"]) % len(PALETTE)])
    window_suffix = f"-w{window_id}" if window_id is not None else ""
    session_id = f"{slug(app)}{window_suffix}-{int(time.time()) % 100000:05d}"
    session = {
        "id": session_id,
        "app": app,
        "color": color,
        "status": "active",
        "created_at": now_iso(),
        "updated_at": now_iso(),
        "last_action": None,
        "screenshot": None,
        "ax_chars": 0,
        "cursor": {"x": None, "y": None},
        "focused": {"index": None, "label": None},
        "window": None,
    }
    bind_cursor(session, window_id=window_id)
    registry["sessions"].append(session)
    save_registry(registry)
    meta = session_dir(session_id) / "meta.json"
    meta.write_text(json.dumps(session, indent=2) + "\n")
    write_handoff(registry)
    write_pip_command(registry)
    append_event(session, "spawn")
    return session


def stop(session_id: str | None = None) -> None:
    registry = load_registry()
    if session_id:
        for item in registry["sessions"]:
            if item["id"] == session_id:
                item["status"] = "stopped"
                item["updated_at"] = now_iso()
                item["cursor"] = {"x": None, "y": None}
                append_event(item, "stop")
    else:
        for item in registry["sessions"]:
            if item.get("status") == "active":
                item["status"] = "stopped"
                item["updated_at"] = now_iso()
                item["cursor"] = {"x": None, "y": None}
                append_event(item, "stop")
    save_registry(registry)
    write_handoff(registry)
    write_pip_command(
        registry,
        command="stop" if not any(s["status"] == "active" for s in registry["sessions"]) else "show",
    )
    write_summary()


def ax_diff(previous: str, current: str) -> str:
    if not previous.strip():
        return current
    prev_lines = previous.splitlines()
    cur_lines = current.splitlines()
    prev_set = set(prev_lines)
    cur_set = set(cur_lines)
    added = [line for line in cur_lines if line not in prev_set]
    removed = [line for line in prev_lines if line not in cur_set]
    if not added and not removed:
        return "(no AX diff — tree unchanged)"
    chunks = []
    if removed:
        chunks.append("removed:\n" + "\n".join(removed[:80]))
    if added:
        chunks.append("added:\n" + "\n".join(added[:80]))
    return "\n\n".join(chunks)


def extract_ocu_payload(raw: dict | list) -> tuple[str, bytes | None]:
    texts: list[str] = []
    image: bytes | None = None

    def walk(node):
        nonlocal image
        if isinstance(node, dict):
            if node.get("type") == "text" and node.get("text"):
                texts.append(node["text"])
            if node.get("type") == "image" and node.get("data") and image is None:
                import base64
                image = base64.b64decode(node["data"])
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(raw)
    return "\n".join(texts).strip(), image


def persist_session(session: dict) -> dict:
    registry = load_registry()
    for item in registry["sessions"]:
        if item["id"] == session["id"]:
            item.update(session)
            item["updated_at"] = now_iso()
            session = item
            break
    save_registry(registry)
    (session_dir(session["id"]) / "meta.json").write_text(json.dumps(session, indent=2) + "\n")
    write_handoff(registry)
    write_pip_command(registry)
    write_summary()
    return session


def ingest_snapshot(app: str, raw_json: str, action: str = "get_app_state", element: int | None = None, x: float | None = None, y: float | None = None) -> dict:
    session = spawn(app)
    payload = json.loads(raw_json)
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except json.JSONDecodeError:
            payload = {"content": [{"type": "text", "text": payload}]}
    text, image = extract_ocu_payload(payload)
    folder = session_dir(session["id"])
    prev_path = folder / "ax.prev.txt"
    ax_path = folder / "ax.txt"
    previous = ax_path.read_text() if ax_path.exists() else ""
    if ax_path.exists():
        prev_path.write_text(previous)
    ax_path.write_text(text + "\n")
    diff = ax_diff(previous, text)
    (folder / "ax.diff.txt").write_text(diff + "\n")
    screenshot_path = None
    if image:
        screenshot_path = folder / "latest.png"
        screenshot_path.write_bytes(image)
    focused = parse_focused(text)
    session["last_action"] = action
    session["updated_at"] = now_iso()
    session["ax_chars"] = len(text)
    session["focused"] = focused
    if screenshot_path:
        session["screenshot"] = str(screenshot_path)
    cursor_element = element
    cursor_label, cursor_occurrence = element_cursor_hint(text, cursor_element)
    bind_cursor(
        session,
        element=cursor_element,
        x=x,
        y=y,
        label=cursor_label,
        occurrence=cursor_occurrence,
    )
    persist_session(session)
    append_event(session, action, {"element_index": element, "x": x, "y": y} if element is not None or x is not None else {})
    return session


def snapshot_app(app: str) -> dict:
    proc = subprocess.run(
        ["open-computer-use", "call", "get_app_state", "--args", json.dumps({"app": app})],
        capture_output=True,
        text=True,
        env=ocu_env(),
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "get_app_state failed")
    return ingest_snapshot(app, proc.stdout, action="get_app_state")


def click_app(app: str, element: int | None = None, x: float | None = None, y: float | None = None) -> dict:
    if element is None and (x is None or y is None):
        raise SystemExit("click requires --element N or both --x and --y")
    args: dict = {"app": app}
    if element is not None:
        args["element_index"] = str(element)
    if x is not None and y is not None:
        args["x"] = x
        args["y"] = y
    if any(hint in app.lower() for hint in CHROMIUM_HINTS):
        args["click_method"] = "sky_click"
    calls = [
        {"tool": "click", "args": args},
        {"tool": "get_app_state", "args": {"app": app}},
    ]
    proc = subprocess.run(
        ["open-computer-use", "call", "--calls", json.dumps(calls), "--sleep", "0.8"],
        capture_output=True,
        text=True,
        env=ocu_env(),
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr or proc.stdout or "click failed")
    return ingest_snapshot(app, proc.stdout, action="click", element=element, x=x, y=y)


def compact_ax(text: str, limit: int = 1800) -> str:
    if len(text) <= limit:
        return text
    return text[:limit].rstrip() + "\n… [truncated for token efficiency; full tree in session ax.txt]"


SKIP_MENTION_APPS = {
    "computer use",
    "cursor",
    "open computer use",
    "window server",
    "dock",
    "control center",
    "notification centre",
    "notification center",
    "spotlight",
    "loginwindow",
    "system settings",
    "systemui server",
}


def refresh_mentions() -> dict:
    names: list[str] = []
    windows = _list_windows_ax()
    for window in windows:
        app = str(window.get("app") or "").strip()
        if not app or app.lower() in SKIP_MENTION_APPS:
            continue
        if app not in names:
            names.append(app)
    for extra in ("Simulator", "Google Chrome", "Safari", "Calendar", "Notes", "Finder", "Slack"):
        if extra not in names:
            names.append(extra)
    dirs = [
        BUS / "mentions",
        ROOT / ".cursor" / "computer-use" / "apps",
        Path.cwd() / ".cursor" / "computer-use" / "apps",
    ]
    unique_dirs: list[Path] = []
    for folder in dirs:
        resolved = folder.resolve()
        if resolved not in unique_dirs:
            unique_dirs.append(resolved)
            folder.mkdir(parents=True, exist_ok=True)
    written = []
    grouped_windows: dict[str, list[dict]] = {}
    for window in windows:
        app = str(window.get("app") or "").strip()
        if app in names and float(window.get("width") or 0) >= 160 and float(window.get("height") or 0) >= 160:
            grouped_windows.setdefault(app, []).append(window)
    window_specs: list[tuple[str, int, str, str]] = []
    for app, app_windows in grouped_windows.items():
        if len(app_windows) < 2:
            continue
        for number, window in enumerate(sorted(app_windows, key=lambda item: int(item.get("id") or 0)), 1):
            window_id = int(window.get("id") or 0)
            title = str(window.get("title") or f"Window {number}").strip()
            filename = f"{slug(app)}-window-{number}.md"
            window_specs.append((app, window_id, title, filename))
    expected_files = {f"{slug(app)}.md" for app in names} | {spec[3] for spec in window_specs}
    for folder in unique_dirs:
        for stale in folder.glob("*.md"):
            if stale.name != "README.md" and stale.name not in expected_files:
                stale.unlink(missing_ok=True)
    for app in names:
        filename = f"{slug(app)}.md"
        body = (
            f"---\ncomputer_use_app: {json.dumps(app)}\n---\n\n"
            f"# @{app}\n\n"
            f"The user @mentioned this file to aim **Open Computer Use** at **{app}**.\n\n"
            f"1. Run `scripts/cu-session.sh spawn {json.dumps(app)}`.\n"
            f"2. Show PiP for this app only (`scripts/computer-use-pip.sh show {json.dumps(app)}`).\n"
            f"3. Snapshot with `get_app_state` and `{{ \"app\": {json.dumps(app)} }}`.\n"
            "4. Click / type / set_value only on this app. Never `click_method: \"global\"`.\n"
            "5. Do not ask to re-grant Accessibility or Screen Recording unless "
            "`scripts/cu-permissions.sh status` reports missing.\n"
        )
        for folder in unique_dirs:
            path = folder / filename
            path.write_text(body)
            written.append(str(path))
    for app, window_id, title, filename in window_specs:
        body = (
            f"---\ncomputer_use_app: {json.dumps(app)}\n"
            f"computer_use_window_id: {window_id}\n---\n\n"
            f"# @{app} — {title}\n\n"
            f"Target only window `{window_id}` of **{app}**. Spawn with "
            f"`scripts/cu-session.sh spawn {json.dumps(app)} --window-id {window_id}`. "
            "Keep this cursor and all actions inside that exact window.\n"
        )
        for folder in unique_dirs:
            path = folder / filename
            path.write_text(body)
            written.append(str(path))
    index = unique_dirs[0] / "README.md" if unique_dirs else BUS / "mentions" / "README.md"
    index.write_text(
        "# Computer Use app mentions\n\n"
        "Attach one of these files (or a `rules/apps/*.mdc` rule) in chat with `@` "
        "to target Computer Use at that app.\n\n"
        + "\n".join(f"- `{name}`" for name in names)
        + ("\n\n## Exact windows\n\n" + "\n".join(
            f"- `{app}` — `{title}` (`{filename}`)"
            for app, _, title, filename in window_specs
        ) if window_specs else "")
        + "\n"
    )
    return {
        "apps": names,
        "windows": [
            {"app": app, "window_id": window_id, "title": title, "file": filename}
            for app, window_id, title, filename in window_specs
        ],
        "dir": str(unique_dirs[-1] if unique_dirs else BUS / "mentions"),
        "files": written[:60],
    }


def write_handoff(registry: dict) -> None:
    active = [item for item in registry.get("sessions", []) if item.get("status") == "active"]
    lines = [
        "# Computer Use handoff",
        "",
        "Compact shared context for Cursor / any agent. Prefer this file over raw MCP screenshot JSON.",
        "",
        f"Updated: {registry.get('updated_at', now_iso())}",
        "",
        "Also see `~/.cursor/computer-use/SUMMARY.md` for the rolling event log.",
        "",
    ]
    if not active:
        lines.append("No active Computer Use sessions.")
        atomic_write_text(HANDOFF, "\n".join(lines) + "\n")
        return
    for item in active:
        folder = session_dir(item["id"])
        ax = (folder / "ax.diff.txt").read_text() if (folder / "ax.diff.txt").exists() else ""
        if not ax.strip() or ax.startswith("(no AX"):
            ax = (folder / "ax.txt").read_text() if (folder / "ax.txt").exists() else "(no snapshot yet)"
        shot = item.get("screenshot") or str(folder / "latest.png")
        focused = item.get("focused") or {}
        cursor = item.get("cursor") or {}
        window = item.get("window") or {}
        lines.extend(
            [
                f"## {item['id']}",
                "",
                f"- app: `{item['app']}`",
                f"- cursor: `{item['color']}` at `({cursor.get('x')}, {cursor.get('y')})`",
                f"- window: `{window.get('title') or window.get('id') or item['app']}`",
                f"- focused: `{focused.get('index')}` {focused.get('label') or ''}".rstrip(),
                f"- last_action: `{item.get('last_action') or 'none'}`",
                f"- screenshot: `{shot}`",
                f"- ax_chars: {item.get('ax_chars', 0)}",
                "",
                "```text",
                compact_ax(ax),
                "```",
                "",
            ]
        )
    atomic_write_text(HANDOFF, "\n".join(lines) + "\n")


def write_pip_command(registry: dict, command: str = "show") -> None:
    active = [item for item in registry.get("sessions", []) if item.get("status") == "active"]
    payload = {
        "command": command if active else "stop",
        "visible": bool(active) and command != "stop",
        "app": active[0]["app"] if active else "Simulator",
        "sessions": [
            {
                "id": item["id"],
                "app": item["app"],
                "color": item["color"],
                "cursor": item.get("cursor") or {},
                "window": item.get("window"),
            }
            for item in active
        ],
    }
    atomic_write_text(PIP_COMMAND, json.dumps(payload) + "\n")


def print_session_context(session_id: str) -> None:
    registry = load_registry()
    item = next((s for s in registry["sessions"] if s["id"] == session_id), None)
    if not item:
        raise SystemExit(f"unknown session {session_id}")
    write_handoff(registry)
    folder = session_dir(session_id)
    ax_path = folder / "ax.diff.txt"
    if not ax_path.exists():
        ax_path = folder / "ax.txt"
    print(json.dumps({**item, "context_file": str(HANDOFF), "summary_file": str(SUMMARY), "ax_file": str(ax_path)}, indent=2))


def selftest() -> None:
    sample = (
        "0 standard window Calendar\n"
        "\t12 button Today\n"
        "The focused UI element is 12 button Today.\n"
    )
    focused = parse_focused(sample)
    assert focused == {"index": 12, "label": "button Today"}, focused
    window = {"appkit_x": 100, "appkit_y": 200, "width": 400, "height": 300, "cursor_x": 128, "cursor_y": 464}
    point = cursor_point(window, element=12)
    assert point["x"] is not None and point["y"] is not None
    click_pt = cursor_point(window, x=40, y=50)
    assert click_pt["x"] == 140.0
    windows = [
        {"id": 1, "app": "Browser", "width": 500, "height": 400},
        {"id": 2, "app": "Browser", "width": 500, "height": 400},
    ]
    assert match_window("Browser", windows, window_id=2)["id"] == 2
    print(json.dumps({"ok": True, "focused": focused, "element_cursor": point, "click_cursor": click_pt}))


def main() -> None:
    parser = argparse.ArgumentParser(description="Computer Use context bus")
    sub = parser.add_subparsers(dest="cmd", required=True)
    spawn_p = sub.add_parser("spawn")
    spawn_p.add_argument("app")
    spawn_p.add_argument("--window-id", type=int)
    sub.add_parser("list")
    sub.add_parser("windows")
    sub.add_parser("summary")
    sub.add_parser("selftest")
    sub.add_parser("mentions")
    stop_p = sub.add_parser("stop")
    stop_p.add_argument("session_id", nargs="?")
    snap_p = sub.add_parser("snapshot")
    snap_p.add_argument("app")
    ctx_p = sub.add_parser("context")
    ctx_p.add_argument("session_id", nargs="?")
    bind_p = sub.add_parser("bind")
    bind_p.add_argument("app")
    bind_p.add_argument("--window-id", type=int)
    click_p = sub.add_parser("click")
    click_p.add_argument("app")
    click_p.add_argument("--element", type=int)
    click_p.add_argument("--x", type=float)
    click_p.add_argument("--y", type=float)
    ingest_p = sub.add_parser("ingest")
    ingest_p.add_argument("app")
    ingest_p.add_argument("--action", default="computer_use")
    ingest_p.add_argument("--element", type=int)
    ingest_p.add_argument("--x", type=float)
    ingest_p.add_argument("--y", type=float)
    args = parser.parse_args()

    if args.cmd == "spawn":
        print(json.dumps(spawn(args.app, window_id=args.window_id), indent=2))
    elif args.cmd == "list":
        print(json.dumps(load_registry(), indent=2))
    elif args.cmd == "windows":
        print(json.dumps(list_windows(), indent=2))
    elif args.cmd == "summary":
        write_summary()
        sys.stdout.write(SUMMARY.read_text() if SUMMARY.exists() else "")
    elif args.cmd == "selftest":
        selftest()
    elif args.cmd == "mentions":
        print(json.dumps(refresh_mentions(), indent=2))
    elif args.cmd == "stop":
        stop(args.session_id)
        print(json.dumps(load_registry(), indent=2))
    elif args.cmd == "snapshot":
        print(json.dumps(snapshot_app(args.app), indent=2))
        print(HANDOFF.read_text(), file=sys.stderr)
    elif args.cmd == "bind":
        session = spawn(args.app, window_id=args.window_id)
        bind_cursor(session, window_id=args.window_id)
        persist_session(session)
        print(json.dumps(session, indent=2))
    elif args.cmd == "click":
        print(json.dumps(click_app(args.app, element=args.element, x=args.x, y=args.y), indent=2))
    elif args.cmd == "ingest":
        raw = sys.stdin.read()
        if not raw.strip():
            raise SystemExit("ingest requires Computer Use result JSON on stdin")
        print(json.dumps(
            ingest_snapshot(
                args.app,
                raw,
                action=args.action,
                element=args.element,
                x=args.x,
                y=args.y,
            ),
            indent=2,
        ))
    elif args.cmd == "context":
        registry = load_registry()
        if args.session_id:
            print_session_context(args.session_id)
        else:
            write_handoff(registry)
            write_summary()
            sys.stdout.write(HANDOFF.read_text())
            if SUMMARY.exists():
                sys.stdout.write("\n" + SUMMARY.read_text())


if __name__ == "__main__":
    main()

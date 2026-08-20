#!/usr/bin/env bash
# Persist Computer Use results into the compact shared context bus.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PATH="${root}/scripts/bin:${PATH:-/usr/bin:/bin}"
input="$(cat || true)"
printf '%s\n' '{}'

HOOK_INPUT="${input}" python3 - "${root}" <<'PY' >> /tmp/computer-use-sync.log 2>&1 &
import json
import os
import subprocess
import sys

root = sys.argv[1]
raw = os.environ.get("HOOK_INPUT", "")
try:
    event = json.loads(raw)
except Exception:
    raise SystemExit(0)

name = str(event.get("tool_name") or event.get("toolName") or "")
tool_input = event.get("tool_input") or event.get("toolInput") or {}
if isinstance(tool_input, str):
    try:
        tool_input = json.loads(tool_input)
    except Exception:
        tool_input = {}
app = tool_input.get("app") if isinstance(tool_input, dict) else None
result = event.get("result_json") or event.get("resultJson")
if not app or not result:
    raise SystemExit(0)

action = next(
    (candidate for candidate in (
        "get_app_state", "click", "type_text", "set_value", "press_key",
        "scroll", "drag", "perform_secondary_action",
    ) if candidate in name.lower()),
    "computer_use",
)
if not isinstance(result, str):
    result = json.dumps(result)
command = [
    sys.executable,
    os.path.join(root, "scripts/cu-state-lock.py"),
    "unless-stopped",
    "--",
    sys.executable,
    os.path.join(root, "scripts/lib/context_bus.py"),
    "ingest",
    str(app),
    "--action",
    action,
]
if isinstance(tool_input, dict):
    element = tool_input.get("element_index")
    if element is not None:
        command.extend(["--element", str(element)])
    if tool_input.get("x") is not None and tool_input.get("y") is not None:
        command.extend(["--x", str(tool_input["x"]), "--y", str(tool_input["y"])])
completed = subprocess.run(
    command,
    input=result,
    text=True,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    timeout=20,
    check=False,
    env=os.environ.copy(),
)
if completed.returncode:
    print(f"sync failed ({completed.returncode}): {completed.stderr}")
PY
exit 0

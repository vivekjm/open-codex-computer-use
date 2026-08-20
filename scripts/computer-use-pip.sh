#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
app="${root}/dist/Computer Use PiP.app"
binary="${app}/Contents/MacOS/ComputerUsePiP"
command_path="${OPEN_COMPUTER_USE_PIP_COMMAND:-/tmp/computer-use-pip.json}"
action="${1:-show}"
target="${2:-Simulator}"
process_pattern="Computer Use PiP.app/Contents/MacOS/ComputerUsePiP"

write_command() {
  PIP_COMMAND_PATH="${command_path}" python3 - "$1" "$2" <<'PY'
import json
import os
import sys
from pathlib import Path

action, app = sys.argv[1], sys.argv[2]
visible = action not in {"hide", "stop"}
sessions = []
registry = Path(os.environ.get("OPEN_COMPUTER_USE_BUS_DIR", str(Path.home() / ".cursor/computer-use"))) / "sessions.json"
try:
    data = json.loads(registry.read_text())
except (FileNotFoundError, json.JSONDecodeError, OSError):
    data = {"sessions": []}
for item in data.get("sessions", []):
    if item.get("status") != "active":
        continue
    sessions.append({
        "id": item.get("id"),
        "app": item.get("app"),
        "color": item.get("color"),
        "cursor": item.get("cursor") or {},
        "window": item.get("window"),
    })
payload = {"command": action, "app": app, "visible": visible, "sessions": sessions}
path = Path(os.environ["PIP_COMMAND_PATH"])
path.parent.mkdir(parents=True, exist_ok=True)
temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
temp.write_text(json.dumps(payload) + "\n")
temp.replace(path)
PY
}

case "${action}" in
  show)
    if [[ ! -x "${binary}" ]]; then
      if ! "${root}/scripts/build-computer-use-pip.sh" > /tmp/computer-use-build.log 2>&1; then
        echo "Computer Use PiP build failed; see /tmp/computer-use-build.log" >&2
        exit 1
      fi
    fi
    write_command show "${target}"
    if pgrep -f "${process_pattern}" >/dev/null 2>&1; then
      exit 0
    fi
    open -n "${app}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f "${process_pattern}" >/dev/null 2>&1 && break
      sleep 0.1
    done
    ;;
  hide)
    write_command hide "${target}"
    ;;
  stop)
    "${root}/scripts/cu-cleanup.sh"
    ;;
  status)
    if pgrep -f "${process_pattern}" >/dev/null 2>&1; then
      echo "sharing"
    elif [[ -x "${binary}" ]]; then
      echo "ready"
    else
      echo "not built"
    fi
    ;;
  *)
    echo "Usage: computer-use-pip.sh show [App] | hide | stop | status" >&2
    exit 2
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="${root}/dist/Computer Use PiP.app"
binary="${app}/Contents/MacOS/ComputerUsePiP"
command_path="/tmp/computer-use-pip.json"
action="${1:-show}"
target="${2:-Simulator}"

if [[ ! -x "${binary}" ]]; then
  if ! "${root}/scripts/build-computer-use-pip.sh" > /tmp/computer-use-build.log 2>&1; then
    echo "Computer Use PiP build failed; see /tmp/computer-use-build.log" >&2
    exit 1
  fi
fi

write_command() {
  python3 - "$1" "$2" <<'PY'
import json, sys
from pathlib import Path
action, app = sys.argv[1], sys.argv[2]
visible = action not in {"hide", "stop"}
sessions = []
registry = Path.home() / ".cursor" / "computer-use" / "sessions.json"
if registry.exists():
    data = json.loads(registry.read_text())
    sessions = [
        {
            "id": item["id"],
            "app": item["app"],
            "color": item.get("color"),
            "cursor": item.get("cursor") or {},
            "window": item.get("window"),
        }
        for item in data.get("sessions", [])
        if item.get("status") == "active"
    ]
payload = {"command": action, "app": app, "visible": visible, "sessions": sessions}
path = Path("/tmp/computer-use-pip.json")
temp = path.with_name(f".{path.name}.{__import__('os').getpid()}.tmp")
temp.write_text(json.dumps(payload) + "\n")
temp.replace(path)
PY
}

case "${action}" in
  show)
    write_command show "${target}"
    if pgrep -f "Computer Use PiP.app/Contents/MacOS/ComputerUsePiP" >/dev/null 2>&1; then
      exit 0
    fi
    open -n "${app}"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f "Computer Use PiP.app/Contents/MacOS/ComputerUsePiP" >/dev/null 2>&1 && break
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
    if pgrep -f "Computer Use PiP.app/Contents/MacOS/ComputerUsePiP" >/dev/null 2>&1; then
      echo "sharing"
    else
      echo "stopped"
    fi
    ;;
  *)
    echo "Usage: computer-use-pip.sh show [App] | hide | stop | status" >&2
    exit 1
    ;;
esac

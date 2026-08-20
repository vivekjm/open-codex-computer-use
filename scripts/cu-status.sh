#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bus="${OPEN_COMPUTER_USE_BUS_DIR:-${HOME}/.cursor/computer-use}"
runtime="${root}/scripts/ocu-runtime.sh"

echo "Open Computer Use plugin"
echo "plugin: $(python3 -c 'import json; print(json.load(open("'"${root}/.cursor-plugin/plugin.json"'"))["version"])')"
if OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" path >/dev/null 2>&1; then
  echo "runtime: $(OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" version 2>/dev/null || echo installed)"
  echo "runtime source: $(OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" source 2>/dev/null || echo unknown)"
  echo "runtime path: $(OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" path 2>/dev/null || echo unknown)"
else
  echo "runtime: missing (run ./scripts/ocu-runtime.sh install)"
fi

echo "pip: $("${root}/scripts/computer-use-pip.sh" status)"
pip_binary="${root}/dist/Computer Use PiP.app/Contents/MacOS/ComputerUsePiP"
if [[ -x "${pip_binary}" ]]; then
  capture="$("${pip_binary}" --capture-status 2>/dev/null || echo unknown)"
  if [[ "${capture}" == "granted" ]]; then
    echo "pip preview: live capture"
  elif [[ "${capture}" == "missing" ]]; then
    echo "pip preview: runtime snapshots (PiP has no separate grant)"
  else
    echo "pip preview: unknown"
  fi
else
  echo "pip preview: unavailable (PiP not built)"
fi

stopped_file="${OPEN_COMPUTER_USE_STOPPED_FILE:-/tmp/open-computer-use-stopped}"
echo "lifecycle: $([[ -e "${stopped_file}" ]] && echo stopped || echo active)"

python3 - "${bus}" <<'PY'
import json
import os
import sys
from pathlib import Path

bus = Path(sys.argv[1])
registry = bus / "sessions.json"
if registry.exists():
    try:
        sessions = json.loads(registry.read_text()).get("sessions", [])
    except Exception as error:
        print(f"sessions: invalid ({error})")
    else:
        active = [item for item in sessions if item.get("status") == "active"]
        print(f"sessions: {len(active)} active / {len(sessions)} retained")
        for item in active:
            print(f"  - {item.get('id')} → {item.get('app')} {item.get('cursor')}")
else:
    print("sessions: none")

for path, label in (
    (Path(os.environ.get("OPEN_COMPUTER_USE_PIP_COMMAND", "/tmp/computer-use-pip.json")), "command"),
    (Path("/tmp/computer-use-overlay-cursors.json"), "overlays"),
):
    try:
        value = json.loads(path.read_text())
        print(f"{label}: {json.dumps(value, separators=(',', ':'))}")
    except FileNotFoundError:
        print(f"{label}: none")
    except Exception as error:
        print(f"{label}: invalid ({error})")
PY

[[ -s /tmp/computer-use-build.log ]] && echo "last build log: /tmp/computer-use-build.log"
[[ -s /tmp/computer-use-sync.log ]] && echo "last sync log: /tmp/computer-use-sync.log"
echo "permissions: ./scripts/cu-permissions.sh status"
echo "full diagnostics: ./scripts/doctor.sh --live"

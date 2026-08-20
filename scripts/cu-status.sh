#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bus="${HOME}/.cursor/computer-use"

echo "Open Computer Use plugin"
echo "plugin: $(python3 -c 'import json; print(json.load(open("'"${root}/.cursor-plugin/plugin.json"'"))["version"])')"
if command -v open-computer-use >/dev/null 2>&1; then
  echo "runtime: $(open-computer-use version 2>/dev/null || echo installed)"
else
  echo "runtime: missing"
fi
echo "pip: $("${root}/scripts/computer-use-pip.sh" status)"
pip_binary="${root}/dist/Computer Use PiP.app/Contents/MacOS/ComputerUsePiP"
if [[ -x "${pip_binary}" ]]; then
  capture="$("${pip_binary}" --capture-status 2>/dev/null || echo unknown)"
  if [[ "${capture}" == "granted" ]]; then
    echo "pip preview: live capture"
  elif [[ "${capture}" == "missing" ]]; then
    echo "pip preview: runtime snapshots (no extra permission required)"
  else
    echo "pip preview: unknown"
  fi
else
  echo "pip preview: unavailable (PiP not built)"
fi
echo "lifecycle: $([[ -e /tmp/open-computer-use-stopped ]] && echo stopped || echo active)"

python3 - "${bus}" <<'PY'
import json
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
    (Path("/tmp/computer-use-pip.json"), "command"),
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

if [[ -s /tmp/computer-use-build.log ]]; then
  echo "last build log: /tmp/computer-use-build.log"
fi
if [[ -s /tmp/computer-use-sync.log ]]; then
  echo "last sync log: /tmp/computer-use-sync.log"
fi
echo "permissions: checked only after a real TCC failure (manual: ./scripts/cu-permissions.sh status)"

#!/usr/bin/env bash
# Tear down overlay cursors, session bus, OCU visual cursor, and PiP.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 "${root}/scripts/cu-state-lock.py" stop -- \
  python3 "${root}/scripts/lib/context_bus.py" stop >/dev/null 2>&1 || true
printf '%s\n' '{"command":"stop","visible":false,"sessions":[]}' > /tmp/computer-use-pip.json
printf '%s\n' '[]' > /tmp/computer-use-overlay-cursors.json

if command -v open-computer-use >/dev/null 2>&1; then
  open-computer-use turn-ended >/dev/null 2>&1 || true
fi

pkill -f "Computer Use PiP.app/Contents/MacOS/ComputerUsePiP" >/dev/null 2>&1 || true
exit 0

#!/usr/bin/env bash
# Tear down overlay cursors, session state, upstream turn state, and PiP.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
pip_command="${OPEN_COMPUTER_USE_PIP_COMMAND:-/tmp/computer-use-pip.json}"

python3 "${root}/scripts/cu-state-lock.py" stop -- \
  python3 "${root}/scripts/lib/context_bus.py" stop >/dev/null 2>&1 || true
mkdir -p "$(dirname "${pip_command}")"
printf '%s\n' '{"command":"stop","visible":false,"sessions":[]}' > "${pip_command}"
printf '%s\n' '[]' > /tmp/computer-use-overlay-cursors.json

OPEN_COMPUTER_USE_AUTO_INSTALL=0 \
  "${root}/scripts/ocu-runtime.sh" turn-ended >/dev/null 2>&1 || true

pkill -f "Computer Use PiP.app/Contents/MacOS/ComputerUsePiP" >/dev/null 2>&1 || true
exit 0

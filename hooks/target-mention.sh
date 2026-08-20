#!/usr/bin/env bash
# Resolve a Computer Use @mention before the first tool call.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="$(cat || true)"
printf '%s\n' '{"continue":true}'

parsed="$(HOOK_INPUT="${input}" python3 - <<'PY' || true
import json
import os
import re
from pathlib import Path

try:
    event = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    raise SystemExit(0)

for attachment in event.get("attachments") or []:
    path = Path(str(attachment.get("file_path") or ""))
    if not path.is_file():
        continue
    try:
        text = path.read_text(errors="ignore")[:4096]
    except OSError:
        continue
    match = re.search(r"(?m)^computer_use_app:\s*[\"']?([^\"'\n]+)", text)
    if not match:
        match = re.search(r"Aim Open Computer Use at [`*]+([^`*\n]+)", text, re.I)
    if match:
        window = re.search(r"(?m)^computer_use_window_id:\s*(\d+)", text)
        print(match.group(1).strip() + "\t" + (window.group(1) if window else ""))
        break
PY
)"

app="${parsed%%$'\t'*}"
window_id="${parsed#*$'\t'}"
if [[ "${window_id}" == "${parsed}" ]]; then
  window_id=""
fi
if [[ -z "${app}" ]]; then
  exit 0
fi

(
  python3 "${root}/scripts/cu-state-lock.py" active -- \
    /bin/bash -c '
      root="$1"
      app="$2"
      window_id="$3"
      "$root/scripts/computer-use-pip.sh" show "$app" >/dev/null 2>&1 || true
      args=(spawn "$app")
      [[ -n "$window_id" ]] && args+=(--window-id "$window_id")
      python3 "$root/scripts/lib/context_bus.py" "${args[@]}" >/dev/null 2>&1 || true
    ' _ "${root}" "${app}" "${window_id}"
) &
exit 0

#!/usr/bin/env bash
# Guard unsafe input and start the target PiP/session before an MCP action.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PATH="${root}/scripts/bin:${PATH:-/usr/bin:/bin}"
input="$(cat || true)"

parsed="$(HOOK_INPUT="${input}" python3 - <<'PY' || true
import json
import os
import re

raw = os.environ.get("HOOK_INPUT", "")
try:
    data = json.loads(raw)
except Exception:
    data = {}
name = str(data.get("tool_name") or data.get("toolName") or "")
command = str(data.get("command") or data.get("url") or "")
tool_input = data.get("tool_input") or data.get("toolInput") or data.get("arguments") or {}
if isinstance(tool_input, str):
    try:
        tool_input = json.loads(tool_input)
    except Exception:
        tool_input = {}
if not isinstance(tool_input, dict):
    tool_input = {}
app = str(tool_input.get("app") or "").strip()
if not app:
    match = re.search(r'"app"\s*:\s*"([^"]+)"', raw)
    app = match.group(1).strip() if match else ""
identity = (name + " " + command).lower()
is_cu = "computer-use" in identity or "open_computer_use" in identity
click_method = str(tool_input.get("click_method") or "").strip().lower()
forbidden = click_method == "global" or tool_input.get("allow_global_pointer_fallbacks") is True
print(("1" if is_cu else "0") + "\t" + app + "\t" + ("1" if forbidden else "0"))
PY
)"

is_cu="${parsed%%$'\t'*}"
rest="${parsed#*$'\t'}"
app="${rest%%$'\t'*}"
forbidden="${rest##*$'\t'}"

if [[ "${is_cu}" != "1" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

if [[ "${forbidden}" == "1" ]]; then
  cat <<'JSON'
{"permission":"deny","user_message":"Open Computer Use blocked a global-pointer action because it could move your real mouse or steal focus.","agent_message":"Use accessibility, app_post, or sky_click. Never use click_method=global or enable global pointer fallbacks."}
JSON
  exit 0
fi

# This allows the plugin's policy hook; Cursor may still show its normal MCP
# confirmation depending on the user's Run Mode and MCP settings.
printf '%s\n' '{"permission":"allow"}'
if [[ -z "${app}" || "${app}" == "Cursor" || "${app}" == "com.todesktop.230313mzl4w4u92" ]]; then
  exit 0
fi

(
  python3 "${root}/scripts/cu-state-lock.py" active -- \
    /bin/bash -c '
      root="$1"
      app="$2"
      "$root/scripts/computer-use-pip.sh" show "$app" >/dev/null 2>&1 || true
      python3 "$root/scripts/lib/context_bus.py" spawn "$app" >/dev/null 2>&1 || true
    ' _ "${root}" "${app}"
) >/dev/null 2>&1 &
exit 0

#!/usr/bin/env bash
# Start the target session/PiP before an MCP action without delaying Cursor.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
input="$(cat || true)"

parsed="$(HOOK_INPUT="${input}" python3 - <<'PY' || true
import json, os, re
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
app = tool_input.get("app", "") if isinstance(tool_input, dict) else ""
if not app:
    match = re.search(r'"app"\s*:\s*"([^"]+)"', raw)
    app = match.group(1) if match else ""
identity = (name + " " + command).lower()
is_cu = "computer-use" in identity or "open_computer_use" in identity
print(("1" if is_cu else "0") + "\t" + str(app).strip())
PY
)"

is_cu="${parsed%%$'\t'*}"
app="${parsed#*$'\t'}"
if [[ "${is_cu}" != "1" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

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
) &
exit 0

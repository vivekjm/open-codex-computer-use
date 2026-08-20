#!/usr/bin/env bash
# Security guard for shell attempts to re-enable physical-pointer fallbacks.
set -euo pipefail
input="$(cat || true)"

HOOK_INPUT="${input}" python3 - <<'PY'
import json
import os
import re

try:
    event = json.loads(os.environ.get("HOOK_INPUT", ""))
except Exception:
    event = {}
command = str(event.get("command") or "")
patterns = (
    r"(?:^|\s)(?:export\s+)?OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS\s*=\s*(?:1|true)\b",
    r"(?:^|\s)--click-method(?:=|\s+)global(?:\s|$)",
)
if any(re.search(pattern, command, re.IGNORECASE) for pattern in patterns):
    print(json.dumps({
        "permission": "deny",
        "user_message": "Blocked an Open Computer Use command that could move the physical pointer.",
        "agent_message": "Keep global pointer fallbacks disabled; use accessibility, app_post, or sky_click.",
    }))
else:
    print("{}")
PY

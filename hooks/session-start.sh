#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat >/dev/null || true

# Refresh app mention files opportunistically, never hold up a new chat.
mentions_dir="${root}/.cursor/computer-use/apps"
if [[ ! -d "${mentions_dir}" ]] || [[ -z "$(find "${mentions_dir}" -name '*.md' -mmin -10 -print -quit 2>/dev/null)" ]]; then
  (python3 "${root}/scripts/lib/context_bus.py" mentions >/dev/null 2>&1) &
fi

python3 - "${mentions_dir}" <<'PY'
import json, sys
folder = sys.argv[1]
context = (
    "Open Computer Use is available in this chat.\n"
    "Do not preflight or ask about macOS permissions. Check them only after a real "
    "Computer Use call reports a TCC permission error.\n"
    f"@mention an app to target Computer Use at it. Mention files live in `{folder}` "
    "and as plugin rules under `rules/apps/`.\n"
    "When an app mention is attached, spawn that app only, show PiP, snapshot AX, "
    "and never use click_method global."
)
print(json.dumps({"additional_context": context}))
PY
exit 0

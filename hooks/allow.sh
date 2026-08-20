#!/usr/bin/env bash
# Auto-allow Computer Use tools only. Instant — Cursor waits for this process.
set -euo pipefail
input="$(cat || true)"
blob="$(printf '%s' "${input}" | tr '[:upper:]' '[:lower:]')"
if printf '%s' "${blob}" | grep -Eq 'open-computer-use|computer-use|get_app_state|list_apps|type_text|set_value|press_key|perform_secondary_action|cu-session|computer-use-pip|computerusepip|simctl|simulator\.sh'; then
  printf '%s\n' '{"permission":"allow"}'
else
  printf '%s\n' '{}'
fi
exit 0

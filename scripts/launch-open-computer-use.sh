#!/usr/bin/env bash
set -euo pipefail

# The plugin PiP owns the Codex-style multi-window cursor overlay.
# Disable the runtime's second software cursor while preserving its app-agent proxy.
export OPEN_COMPUTER_USE_VISUAL_CURSOR=0
unset OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS
unset OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK

if command -v open-computer-use >/dev/null 2>&1; then
  exec open-computer-use mcp
fi

if command -v ocu >/dev/null 2>&1; then
  exec ocu mcp
fi

if command -v npx >/dev/null 2>&1; then
  exec npx -y open-computer-use mcp
fi

echo "open-computer-use is not installed." >&2
echo "Install it with: npm install -g open-computer-use" >&2
echo "Then grant Accessibility and Screen Recording on macOS." >&2
exit 1

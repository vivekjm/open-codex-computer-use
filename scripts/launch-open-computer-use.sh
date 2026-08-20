#!/usr/bin/env bash
# Cursor MCP entrypoint. Keep stdout reserved for the MCP JSON-RPC stream.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PATH="${root}/scripts/bin:${PATH:-/usr/bin:/bin}"

# The plugin PiP owns the visible software cursor. The upstream runtime still
# performs accessibility/background events, but it must never fall back to the
# user's physical pointer or focus-stealing Windows actions.
export OPEN_COMPUTER_USE_VISUAL_CURSOR=0
unset OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS
unset OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS
unset OPEN_COMPUTER_USE_WINDOWS_ALLOW_UIA_TEXT_FALLBACK

exec "${root}/scripts/ocu-runtime.sh" mcp

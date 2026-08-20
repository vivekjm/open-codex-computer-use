#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bus="${root}/scripts/lib/context_bus.py"
pip="${root}/scripts/computer-use-pip.sh"
cmd="${1:-help}"
shift || true

usage() {
  cat <<'EOF'
Usage: cu-session.sh <command>

Codex-style multi-window Computer Use:
  spawn <App> [--window-id N] Bind a colored overlay cursor to an exact app window
  snapshot <App>              Capture AX+screenshot into the shared bus (compact)
  click <App> --element N     Click without moving the real pointer, then snapshot
  click <App> --x N --y N     Window-relative coordinate click, then snapshot
  windows                     list_windows analogue (Sky Window2)
  mentions                    Write @mention files for running/common apps
  bind <App> [--window-id N]  Reposition a cursor on an exact app window
  list                        Show active cursors/sessions
  context [session-id]        Print HANDOFF.md + SUMMARY.md for Cursor
  summary                     Print the rolling compact event log
  stop [session-id]           Stop one cursor or all

Context is written to ~/.cursor/computer-use/HANDOFF.md so any Cursor
workspace can Read it. Screenshots stay on disk; only AX diffs go to the model.
EOF
}

case "${cmd}" in
  help|-h|--help) usage ;;
  spawn)
    [[ $# -ge 1 ]] || { echo "spawn requires an app name" >&2; exit 1; }
    python3 "${bus}" spawn "$@"
    "${pip}" show "$1" >/dev/null 2>&1 || true
    ;;
  snapshot)
    [[ $# -ge 1 ]] || { echo "snapshot requires an app name" >&2; exit 1; }
    python3 "${bus}" spawn "$1" >/dev/null
    python3 "${bus}" snapshot "$1"
    "${pip}" show "$1" >/dev/null 2>&1 || true
    ;;
  click)
    [[ $# -ge 1 ]] || { echo "click requires an app name" >&2; exit 1; }
    python3 "${bus}" click "$@"
    "${pip}" show "$1" >/dev/null 2>&1 || true
    ;;
  windows)
    python3 "${bus}" windows
    ;;
  mentions)
    python3 "${bus}" mentions
    ;;
  bind)
    [[ $# -ge 1 ]] || { echo "bind requires an app name" >&2; exit 1; }
    python3 "${bus}" bind "$@"
    "${pip}" show "$1" >/dev/null 2>&1 || true
    ;;
  list)
    python3 "${bus}" list
    ;;
  context)
    python3 "${bus}" context "${1:-}"
    ;;
  summary)
    python3 "${bus}" summary
    ;;
  stop)
    if [[ -z "${1:-}" ]]; then
      "${root}/scripts/cu-cleanup.sh"
    else
      python3 "${bus}" stop "${1:-}"
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

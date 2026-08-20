#!/usr/bin/env bash
# One-command local installation for the Cursor plugin and its pinned runtime.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
run_permissions=auto

usage() {
  cat <<'USAGE'
Usage: ./scripts/setup.sh [options]

Options:
  --no-permissions   Do not launch the upstream macOS permission doctor
  --permissions      Always launch the permission doctor after installation
  -h, --help         Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-permissions) run_permissions=no ;;
    --permissions) run_permissions=yes ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This Cursor wrapper currently requires macOS 14 or newer." >&2
  echo "The upstream runtime is cross-platform, but the PiP/overlay app in this repo is macOS-only." >&2
  exit 1
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "${major}" -lt 14 ]]; then
  echo "macOS 14 or newer is required (found $(sw_vers -productVersion))." >&2
  exit 1
fi

for command in python3 npm swiftc codesign rsync; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Missing required command: ${command}" >&2
    echo "Install Node.js and Xcode Command Line Tools, then run setup again." >&2
    exit 1
  fi
done

echo "[1/5] Installing the pinned Open Computer Use runtime"
"${root}/scripts/ocu-runtime.sh" install

echo "[2/5] Building the Computer Use PiP and overlay app"
"${root}/scripts/build-computer-use-pip.sh"

echo "[3/5] Running static and protocol verification"
python3 "${root}/scripts/verify-plugin.py"

echo "[4/5] Installing the local Cursor plugin"
"${root}/scripts/install-local-plugin.sh"

echo "[5/5] Checking the installation"
"${root}/scripts/doctor.sh"

if [[ "${run_permissions}" == yes ]] || { [[ "${run_permissions}" == auto ]] && [[ -t 0 && -t 1 ]]; }; then
  echo
  echo "Opening the upstream permission doctor. Grant Accessibility and Screen Recording if macOS asks."
  "${root}/scripts/ocu-runtime.sh" doctor || true
else
  echo
  echo "Permission onboarding was skipped. Run this once before the first GUI task:"
  echo "  ${root}/scripts/ocu-runtime.sh doctor"
fi

cat <<'DONE'

Installation complete.
1. In Cursor run “Developer: Reload Window”.
2. Open Customize → MCP and enable “open-computer-use” if it is off.
3. Run /computer-use-status, then try: “@Notes create a draft grocery list”.
DONE

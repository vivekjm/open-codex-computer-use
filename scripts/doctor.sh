#!/usr/bin/env bash
# Non-destructive diagnostics; --repair installs/builds missing local pieces.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
repair=0
permissions=0
live=0
failures=0
warnings=0
runtime_report="$(mktemp -t open-computer-use-runtime.XXXXXX)"
verify_report="$(mktemp -t open-computer-use-verify.XXXXXX)"
trap 'rm -f "${runtime_report}" "${verify_report}"' EXIT

usage() {
  cat <<'USAGE'
Usage: ./scripts/doctor.sh [--repair] [--permissions] [--live]

  --repair       Install the pinned runtime and build the PiP app when missing
  --permissions  Run the upstream Accessibility / Screen Recording doctor
  --live         Start the MCP server and verify initialize + tools/list
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repair) repair=1 ;;
    --permissions) permissions=1 ;;
    --live) live=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

ok() { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '  ✗ %s\n' "$1"; failures=$((failures + 1)); }

printf 'Open Computer Use doctor\n\n'

if [[ "$(uname -s)" == "Darwin" ]]; then
  product_version="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
  major="${product_version%%.*}"
  if [[ "${major}" =~ ^[0-9]+$ ]] && [[ "${major}" -ge 14 ]]; then
    ok "macOS ${product_version}"
  else
    fail "macOS 14+ required (found ${product_version})"
  fi
else
  fail "PiP/overlay wrapper requires macOS; found $(uname -s)"
fi

for command in bash python3; do
  if command -v "${command}" >/dev/null 2>&1; then
    ok "${command}: $(command -v "${command}")"
  else
    fail "missing ${command}"
  fi
done

for command in npm swiftc codesign rsync; do
  if command -v "${command}" >/dev/null 2>&1; then
    ok "${command}: $(command -v "${command}")"
  else
    warn "missing ${command} (needed for install/build)"
  fi
done

if ! OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${root}/scripts/ocu-runtime.sh" status >"${runtime_report}" 2>&1; then
  if [[ "${repair}" -eq 1 ]] && "${root}/scripts/ocu-runtime.sh" install; then
    ok "installed pinned runtime"
    OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${root}/scripts/ocu-runtime.sh" status >"${runtime_report}" 2>&1 || true
  else
    fail "runtime missing (run ./scripts/doctor.sh --repair)"
  fi
fi
if [[ -s "${runtime_report}" ]]; then
  while IFS= read -r line; do printf '    %s\n' "${line}"; done <"${runtime_report}"
fi
if OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${root}/scripts/ocu-runtime.sh" path >/dev/null 2>&1; then
  ok "runtime resolver"
fi

pip_binary="${root}/dist/Computer Use PiP.app/Contents/MacOS/ComputerUsePiP"
if [[ ! -x "${pip_binary}" && "${repair}" -eq 1 ]]; then
  if "${root}/scripts/build-computer-use-pip.sh"; then
    ok "built PiP app"
  else
    fail "PiP build failed (see /tmp/computer-use-build.log when launched from Cursor)"
  fi
fi
if [[ -x "${pip_binary}" ]]; then
  ok "PiP binary: ${pip_binary}"
else
  fail "PiP binary missing (run make build-pip or doctor --repair)"
fi

if python3 "${root}/scripts/verify-plugin.py" >"${verify_report}" 2>&1; then
  ok "plugin verification"
else
  fail "plugin verification failed"
  sed 's/^/    /' "${verify_report}" >&2
fi

plugin_dir="${OPEN_COMPUTER_USE_PLUGIN_DIR:-${HOME}/.cursor/plugins/local/open-computer-use}"
if [[ -e "${plugin_dir}/.cursor-plugin/plugin.json" ]]; then
  ok "Cursor plugin installed: ${plugin_dir}"
else
  warn "Cursor plugin is not installed at ${plugin_dir}"
fi

if [[ "${live}" -eq 1 ]]; then
  if OPEN_COMPUTER_USE_AUTO_INSTALL=0 python3 "${root}/scripts/mcp-smoke.py"; then
    ok "live MCP initialize + tools/list"
  else
    fail "live MCP smoke test"
  fi
fi

if [[ "${permissions}" -eq 1 ]]; then
  if "${root}/scripts/ocu-runtime.sh" doctor; then
    ok "upstream permission doctor"
  else
    fail "Accessibility or Screen Recording is not ready"
  fi
fi

printf '\nResult: %d failure(s), %d warning(s).\n' "${failures}" "${warnings}"
[[ "${failures}" -eq 0 ]]

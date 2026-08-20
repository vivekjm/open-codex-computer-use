#!/usr/bin/env bash
# Resolve and run the upstream Open Computer Use runtime from one stable entrypoint.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly DEFAULT_PACKAGE="open-computer-use@0.1.51"
package_spec="${OPEN_COMPUTER_USE_NPM_SPEC:-${DEFAULT_PACKAGE}}"
runtime_home="${OPEN_COMPUTER_USE_RUNTIME_HOME:-${HOME}/.cursor/open-computer-use/runtimes}"
runtime_id="$(printf '%s' "${package_spec}" | tr -c '[:alnum:].@_-' '_' | tr '@/' '__')"
managed_root="${runtime_home}/${runtime_id}"
managed_bin="${managed_root}/node_modules/.bin/open-computer-use"

RESOLVED_BIN=""
RESOLVED_SOURCE=""

canonical_path() {
  local value="$1"
  local dir base
  dir="$(dirname "${value}")"
  base="$(basename "${value}")"
  if [[ -d "${dir}" ]]; then
    printf '%s/%s\n' "$(cd "${dir}" && pwd -P)" "${base}"
  else
    printf '%s\n' "${value}"
  fi
}

is_own_shim() {
  local candidate shim_open shim_ocu
  candidate="$(canonical_path "$1")"
  shim_open="$(canonical_path "${root}/scripts/bin/open-computer-use")"
  shim_ocu="$(canonical_path "${root}/scripts/bin/ocu")"
  [[ "${candidate}" == "${shim_open}" || "${candidate}" == "${shim_ocu}" ]]
}

set_resolution() {
  RESOLVED_BIN="$1"
  RESOLVED_SOURCE="$2"
}

resolve_runtime() {
  local override candidate
  override="${OPEN_COMPUTER_USE_RUNTIME_BIN:-}"
  if [[ -n "${override}" ]]; then
    [[ "${override}" == "~/"* ]] && override="${HOME}/${override#~/}"
    if [[ -x "${override}" ]]; then
      set_resolution "$(canonical_path "${override}")" "override"
      return 0
    fi
    echo "OPEN_COMPUTER_USE_RUNTIME_BIN is not executable: ${override}" >&2
    return 1
  fi

  for candidate in \
    "${root}/Open Computer Use.app/Contents/MacOS/OpenComputerUse" \
    "${root}/Open Computer Use (Dev).app/Contents/MacOS/OpenComputerUse" \
    "${root}/OpenComputerUse.app/Contents/MacOS/OpenComputerUse" \
    "${root}/runtime/Open Computer Use.app/Contents/MacOS/OpenComputerUse" \
    "${root}/runtime/OpenComputerUse.app/Contents/MacOS/OpenComputerUse" \
    "${root}/runtime/open-computer-use" \
    "${root}/runtime/open-computer-use.exe" \
    "${root}/node_modules/.bin/open-computer-use" \
    "${managed_bin}"; do
    if [[ -x "${candidate}" ]]; then
      set_resolution "$(canonical_path "${candidate}")" \
        "$([[ "${candidate}" == "${managed_bin}" ]] && echo managed || echo bundled)"
      return 0
    fi
  done

  candidate="$(command -v open-computer-use 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]] && ! is_own_shim "${candidate}"; then
    set_resolution "$(canonical_path "${candidate}")" "path"
    return 0
  fi

  candidate="$(command -v ocu 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]] && ! is_own_shim "${candidate}"; then
    set_resolution "$(canonical_path "${candidate}")" "path-alias"
    return 0
  fi

  return 1
}

release_install_lock() {
  if [[ -n "${install_lock:-}" && -d "${install_lock}" ]]; then
    rm -rf "${install_lock}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${install_tmp:-}" && -d "${install_tmp}" ]]; then
    rm -rf "${install_tmp}" >/dev/null 2>&1 || true
  fi
}

install_runtime() {
  local attempt owner_pid
  if [[ -x "${managed_bin}" ]]; then
    printf 'Open Computer Use runtime is already installed at %s\n' "${managed_root}" >&2
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to install ${package_spec}. Install Node.js 20+ first." >&2
    return 1
  fi

  mkdir -p "${runtime_home}"
  install_lock="${managed_root}.install-lock"
  for ((attempt = 1; attempt <= 300; attempt++)); do
    if mkdir "${install_lock}" 2>/dev/null; then
      printf '%s\n' "$$" > "${install_lock}/pid"
      break
    fi
    owner_pid="$(cat "${install_lock}/pid" 2>/dev/null || true)"
    if [[ "${owner_pid}" =~ ^[0-9]+$ ]] && ! kill -0 "${owner_pid}" 2>/dev/null; then
      rm -rf "${install_lock}" >/dev/null 2>&1 || true
      continue
    fi
    if [[ -x "${managed_bin}" ]]; then
      printf 'Open Computer Use runtime became available at %s\n' "${managed_root}" >&2
      return 0
    fi
    if [[ "${attempt}" -eq 300 ]]; then
      echo "Timed out waiting for another runtime installation: ${install_lock}" >&2
      return 1
    fi
    sleep 0.2
  done

  trap release_install_lock EXIT INT TERM
  install_tmp="${managed_root}.tmp.$$"
  rm -rf "${install_tmp}"
  mkdir -p "${install_tmp}"

  echo "Installing pinned runtime ${package_spec} into ${managed_root} ..." >&2
  npm install \
    --prefix "${install_tmp}" \
    --no-audit \
    --no-fund \
    --omit=dev \
    --save-exact \
    "${package_spec}" >&2

  if [[ ! -x "${install_tmp}/node_modules/.bin/open-computer-use" ]]; then
    echo "npm completed, but the open-computer-use executable was not produced." >&2
    return 1
  fi

  rm -rf "${managed_root}"
  mv "${install_tmp}" "${managed_root}"
  install_tmp=""
  cat > "${managed_root}/open-computer-use-runtime.json" <<JSON
{
  "package": "${package_spec}",
  "installed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
JSON
  release_install_lock
  trap - EXIT INT TERM
  printf 'Installed %s at %s\n' "${package_spec}" "${managed_root}" >&2
}

print_status() {
  local json="${1:-}"
  local available=false path="" source="missing" version=""
  if resolve_runtime; then
    available=true
    path="${RESOLVED_BIN}"
    source="${RESOLVED_SOURCE}"
    version="$(OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${RESOLVED_BIN}" version 2>/dev/null | head -n 1 || true)"
  fi

  if [[ "${json}" == "--json" ]]; then
    STATUS_AVAILABLE="${available}" STATUS_PATH="${path}" STATUS_SOURCE="${source}" \
      STATUS_VERSION="${version}" STATUS_SPEC="${package_spec}" python3 - <<'PY'
import json
import os
print(json.dumps({
    "available": os.environ["STATUS_AVAILABLE"] == "true",
    "path": os.environ["STATUS_PATH"] or None,
    "source": os.environ["STATUS_SOURCE"],
    "version": os.environ["STATUS_VERSION"] or None,
    "package_spec": os.environ["STATUS_SPEC"],
}, indent=2))
PY
  else
    printf 'runtime: %s\n' "$([[ "${available}" == true ]] && echo available || echo missing)"
    printf 'source: %s\n' "${source}"
    printf 'path: %s\n' "${path:-none}"
    printf 'version: %s\n' "${version:-unknown}"
    printf 'managed package: %s\n' "${package_spec}"
  fi
  [[ "${available}" == true ]]
}

usage() {
  cat <<USAGE
Usage: ocu-runtime.sh <command> [args...]

Runtime management:
  install             Install ${package_spec} into the Cursor user cache
  path                Print the selected runtime executable
  source              Print how the runtime was resolved
  status [--json]     Report runtime availability without installing anything

Any other command is forwarded to the selected runtime, for example:
  ocu-runtime.sh mcp
  ocu-runtime.sh call list_apps
  ocu-runtime.sh doctor

Environment:
  OPEN_COMPUTER_USE_RUNTIME_BIN   Explicit executable override
  OPEN_COMPUTER_USE_RUNTIME_HOME  Managed runtime cache root
  OPEN_COMPUTER_USE_NPM_SPEC      npm package spec (default: ${DEFAULT_PACKAGE})
  OPEN_COMPUTER_USE_AUTO_INSTALL  Set to 0 to disable first-run installation
USAGE
}

command_name="${1:-}"
case "${command_name}" in
  -h|--help|help)
    usage
    exit 0
    ;;
  install)
    install_runtime
    exit $?
    ;;
  path)
    if resolve_runtime; then
      printf '%s\n' "${RESOLVED_BIN}"
      exit 0
    fi
    echo "Open Computer Use runtime is not installed." >&2
    exit 1
    ;;
  source)
    if resolve_runtime; then
      printf '%s\n' "${RESOLVED_SOURCE}"
      exit 0
    fi
    printf 'missing\n'
    exit 1
    ;;
  status)
    shift || true
    print_status "${1:-}"
    exit $?
    ;;
  "")
    usage >&2
    exit 2
    ;;
esac

if ! resolve_runtime; then
  if [[ "${OPEN_COMPUTER_USE_AUTO_INSTALL:-1}" == "1" ]]; then
    install_runtime
    resolve_runtime || true
  fi
fi

if [[ -z "${RESOLVED_BIN}" ]]; then
  cat >&2 <<ERROR
Open Computer Use runtime is unavailable.
Run: ${root}/scripts/ocu-runtime.sh install
Or set OPEN_COMPUTER_USE_RUNTIME_BIN to a native runtime executable.
ERROR
  exit 127
fi

exec "${RESOLVED_BIN}" "$@"

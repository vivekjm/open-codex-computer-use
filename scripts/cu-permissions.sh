#!/usr/bin/env bash
# Query or launch the upstream TCC doctor through the shared runtime resolver.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
runtime="${root}/scripts/ocu-runtime.sh"
cmd="${1:-status}"

case "${cmd}" in
  status)
    if ! OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" path >/dev/null 2>&1; then
      echo "missing: Open Computer Use runtime not installed"
      exit 1
    fi
    set +e
    out="$(OPEN_COMPUTER_USE_AUTO_INSTALL=0 "${runtime}" doctor 2>&1)"
    rc=$?
    set -e
    printf '%s\n' "${out}"
    if printf '%s' "${out}" | grep -qi 'accessibility=granted' \
      && printf '%s' "${out}" | grep -qi 'screenRecording=granted'; then
      echo "ok"
      exit 0
    fi
    if [[ "${rc}" -eq 0 ]] && ! printf '%s' "${out}" | grep -Eqi 'missing|denied|not granted'; then
      echo "ok"
      exit 0
    fi
    echo "missing"
    exit 1
    ;;
  doctor)
    exec "${runtime}" doctor
    ;;
  *)
    echo "Usage: cu-permissions.sh status | doctor" >&2
    exit 2
    ;;
esac

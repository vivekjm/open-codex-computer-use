#!/usr/bin/env bash
# Silent TCC status. Never launches onboarding unless the user asked (`doctor`).
set -euo pipefail

cmd="${1:-status}"

case "${cmd}" in
  status)
    if ! command -v open-computer-use >/dev/null 2>&1; then
      echo "missing: open-computer-use CLI not installed"
      exit 1
    fi
    out="$(open-computer-use doctor 2>&1 || true)"
    echo "${out}"
    if echo "${out}" | grep -qi "accessibility=granted" && echo "${out}" | grep -qi "screenRecording=granted"; then
      echo "ok"
      exit 0
    fi
    echo "missing"
    exit 1
    ;;
  doctor)
    exec open-computer-use doctor
    ;;
  *)
    echo "Usage: cu-permissions.sh status | doctor" >&2
    exit 1
    ;;
esac

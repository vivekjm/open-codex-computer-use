#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat >/dev/null || true
printf '%s\n' '{}'
("${root}/scripts/cu-cleanup.sh" >/dev/null 2>&1) &
exit 0

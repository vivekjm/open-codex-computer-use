#!/usr/bin/env bash
# Install a real local plugin copy. Cursor rejects symlinks escaping plugins/local.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
target="${OPEN_COMPUTER_USE_PLUGIN_DIR:-${HOME}/.cursor/plugins/local/open-computer-use}"
parent="$(dirname "${target}")"
mkdir -p "${parent}"

if [[ "$(cd "${parent}" && pwd -P)/$(basename "${target}")" == "${root}" ]]; then
  echo "Source and target are the same directory; nothing to copy."
else
  [[ -L "${target}" ]] && unlink "${target}"
  mkdir -p "${target}"
  rsync -a --delete \
    --exclude='.git' \
    --exclude='.github' \
    --exclude='.cursor' \
    --exclude='.DS_Store' \
    --exclude='.test-home' \
    --exclude='test-bus' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    "${root}/" "${target}/"
fi

version="$(python3 - "${target}/.cursor-plugin/plugin.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["version"])
PY
)"
echo "Installed Open Computer Use ${version} at ${target}"

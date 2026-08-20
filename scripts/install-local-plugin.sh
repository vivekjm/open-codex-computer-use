#!/usr/bin/env bash
# Install a real local plugin copy. Cursor rejects symlinks escaping plugins/local.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${OPEN_COMPUTER_USE_PLUGIN_DIR:-${HOME}/.cursor/plugins/local/open-computer-use}"
parent="$(dirname "${target}")"

mkdir -p "${parent}"
if [[ -L "${target}" ]]; then
  unlink "${target}"
fi
mkdir -p "${target}"

rsync -a --delete \
  --exclude='.cursor' \
  --exclude='.test-home' \
  --exclude='test-bus' \
  --exclude='__pycache__' \
  "${root}/" "${target}/"

version="$(python3 - "${target}/.cursor-plugin/plugin.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1]))["version"])
PY
)"
echo "Installed Open Computer Use ${version} at ${target}"

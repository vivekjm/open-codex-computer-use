#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
src="${root}/apps/ComputerUsePiP/main.swift"
plist="${root}/apps/ComputerUsePiP/Info.plist"
app="${root}/dist/Computer Use PiP.app"
macos="${app}/Contents/MacOS"
binary="${macos}/ComputerUsePiP"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Computer Use PiP can only be built on macOS." >&2
  exit 1
fi
for command in swiftc codesign; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "Missing ${command}. Install Xcode Command Line Tools." >&2
    exit 1
  }
done

mkdir -p "${macos}" "${app}/Contents/Resources"
cp "${plist}" "${app}/Contents/Info.plist"
/usr/bin/plutil -lint "${app}/Contents/Info.plist" >/dev/null

swiftc -swift-version 5 -O \
  -o "${binary}" \
  "${src}" \
  "${root}/apps/ComputerUsePiP/CursorOverlay.swift" \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ScreenCaptureKit \
  -framework Vision

chmod +x "${binary}"
codesign --remove-signature "${app}" >/dev/null 2>&1 || true
identity="${CU_CODESIGN_IDENTITY:-}"
if [[ -n "${identity}" ]]; then
  codesign --force --deep --sign "${identity}" --identifier com.vivek.open-computer-use.pip "${app}"
else
  codesign --force --deep --sign - --identifier com.vivek.open-computer-use.pip "${app}"
fi
codesign --verify --deep --strict "${app}"
echo "Built ${app}"

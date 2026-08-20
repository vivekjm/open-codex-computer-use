#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${root}/apps/ComputerUsePiP/main.swift"
plist="${root}/apps/ComputerUsePiP/Info.plist"
app="${root}/dist/Computer Use PiP.app"
macos="${app}/Contents/MacOS"
binary="${macos}/ComputerUsePiP"

mkdir -p "${macos}" "${app}/Contents/Resources"
cp "${plist}" "${app}/Contents/Info.plist"

swiftc -swift-version 5 -O \
  -o "${binary}" \
  "${src}" \
  "${root}/apps/ComputerUsePiP/CursorOverlay.swift" \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ScreenCaptureKit

chmod +x "${binary}"
codesign --remove-signature "${app}" >/dev/null 2>&1 || true
identity="${CU_CODESIGN_IDENTITY:-}"
if [[ -n "${identity}" ]]; then
  codesign --force --sign "${identity}" --identifier com.vivek.open-computer-use.pip "${app}"
else
  codesign --force --sign - --identifier com.vivek.open-computer-use.pip "${app}"
fi
echo "Built ${app}"

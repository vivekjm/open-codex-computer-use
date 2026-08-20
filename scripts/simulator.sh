#!/usr/bin/env bash
set -euo pipefail

# Codex-style iOS Simulator control: simctl first, GUI clicks only when needed.

usage() {
  cat <<'EOF'
Usage: simulator.sh <command> [args]

Commands:
  status                 Booted device name, UDID, runtime
  udid                   Print booted UDID
  apps                   Installed third-party apps on the booted device
  screenshot [path]      iOS framebuffer PNG (not the Simulator.app chrome)
  launch <bundle-id>     Launch an installed app
  terminate <bundle-id>  Terminate a running app
  openurl <url>          Open a URL / deep link on the device
  logs [predicate]       Stream os_log from the booted device (Ctrl-C to stop)
  appinfo <bundle-id>    Show installed app metadata

Device defaults to the currently booted simulator ("booted").
EOF
}

need_booted() {
  if ! xcrun simctl list devices booted | grep -q Booted; then
    echo "No booted iOS Simulator. Open Simulator first." >&2
    exit 1
  fi
}

udid() {
  xcrun simctl list devices booted | sed -n 's/.*(\([A-F0-9-]\{36\}\)).*(Booted).*/\1/p' | head -1
}

cmd="${1:-status}"
shift || true

case "${cmd}" in
  help|-h|--help)
    usage
    ;;
  udid)
    need_booted
    udid
    ;;
  status)
    need_booted
    xcrun simctl list devices booted | grep Booted
    echo "UDID=$(udid)"
    ;;
  apps)
    need_booted
    xcrun simctl listapps booted | plutil -convert json -o - - | python3 -c '
import json, sys
data = json.load(sys.stdin)
for bundle_id, info in sorted(data.items()):
    if bundle_id.startswith("com.apple"):
        continue
    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or ""
    print(f"{name}\t{bundle_id}")
'
    ;;
  screenshot)
    need_booted
    out="${1:-/tmp/simulator-framebuffer.png}"
    xcrun simctl io booted screenshot --type=png "${out}"
    echo "${out}"
    ;;
  launch)
    need_booted
    [[ $# -ge 1 ]] || { echo "launch requires a bundle id" >&2; exit 1; }
    xcrun simctl launch booted "$1"
    ;;
  terminate)
    need_booted
    [[ $# -ge 1 ]] || { echo "terminate requires a bundle id" >&2; exit 1; }
    xcrun simctl terminate booted "$1"
    ;;
  openurl)
    need_booted
    [[ $# -ge 1 ]] || { echo "openurl requires a url" >&2; exit 1; }
    xcrun simctl openurl booted "$1"
    ;;
  appinfo)
    need_booted
    [[ $# -ge 1 ]] || { echo "appinfo requires a bundle id" >&2; exit 1; }
    xcrun simctl appinfo booted "$1"
    ;;
  logs)
    need_booted
    extra=()
    if [[ $# -ge 1 ]]; then
      extra=(--predicate "$1")
    fi
    xcrun simctl spawn booted log stream --style compact --level debug "${extra[@]}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

---
name: ios-simulator
description: Drive the iOS Simulator the way Codex does — simctl for launch/terminate/screenshots/logs, Computer Use only for on-screen taps. Use when the task involves Simulator, iPhone emulator, simctl, or auditing a booted iOS app.
---

# iOS Simulator (Codex hybrid)

Codex does **not** click through Simulator chrome for app lifecycle. It uses the `com.apple.iphonesimulator` integration: `xcrun simctl` first, then Computer Use only for guest UI.

Keep Cursor in front. Show the Currently Sharing PiP. Do not raise the Simulator window.

## Prefer simctl

Use `scripts/simulator.sh` or raw `xcrun simctl` with the special device `booted`.

| Goal | Do this | Do not do this |
| --- | --- | --- |
| See the phone screen | `simulator.sh screenshot` | Screenshot the whole Mac / Simulator chrome |
| Switch apps | `simctl terminate` / `simctl launch` | Click Simulator Home, then hunt for an icon |
| Kill the app | `xcrun simctl terminate booted <bundle-id>` | Force-quit from the GUI |
| Deep link | `simctl openurl booted <url>` | Type the URL into Safari by hand |
| API / runtime audit | `simctl spawn booted log stream` | Infer network calls only from pixels |
| Tap a button | Open Computer Use `get_app_state` + `click` on app `Simulator` | Move the real mouse |

Current device identity:

```sh
./scripts/simulator.sh status
./scripts/simulator.sh apps
```

Tangibly on this machine: `com.tangiblereserve.tangibly`.

## Loop (inspect → act → verify)

1. `simulator.sh status` and reuse the booted UDID for the rest of the session.
2. `scripts/computer-use-pip.sh show Simulator` so the user watches the framebuffer PiP.
3. For each screen you need to audit:
   - `simulator.sh screenshot /tmp/sim.png` (iOS framebuffer, fast)
   - `open-computer-use call get_app_state --args '{"app":"Simulator"}'` for the AX tree
   - Click / type with `element_index`. Never `click_method: "global"`.
4. To leave an app and open another: `terminate` then `launch`, not Home + icon.
5. For API audits, start `log stream` in parallel, exercise the UI, then quote the relevant log lines.

Group work as named steps the way Codex does: “Inspect signed-in simulator”, “Audit Profile screen”, “Dismiss sheet”.

## Computer Use is for the guest UI only

The macOS app name is `Simulator` / `com.apple.iphonesimulator`. Snapshot that app, then tap iOS controls. Do not click Simulator toolbar Home / Rotate / close unless the user asked to operate the *host* window.

## Safety

Do not `erase`, `delete`, or `uninstall` unless the user explicitly asked. Ask before `terminate` if the user is actively using that app. Stay out of password managers and unrelated accounts.

---
name: open-computer-use
description: Inspect and operate real macOS apps in the background through the Open Computer Use MCP server, with app-scoped virtual cursors and a Picture-in-Picture preview. Use only when a structured API or file operation cannot complete the requested desktop task.
---

# Open Computer Use

Use the `open-computer-use` MCP tools to operate a real macOS app without moving the user’s physical pointer. The tinted pointer belongs to the agent; the user keeps their mouse, keyboard focus, and frontmost app.

Prefer a structured connector, CLI, API, or direct file edit when one can complete the task. Computer Use is the fallback for UI-only work.

## Readiness

- The plugin wrapper requires macOS 14 or newer.
- The supported runtime entrypoint is `scripts/ocu-runtime.sh`; do not assume a global npm binary exists.
- If tools are unavailable, run `scripts/doctor.sh` and read [references/installation.md](references/installation.md).
- Do not preflight macOS permissions before every task. Run `scripts/cu-permissions.sh status` only after a real TCC/permission failure, or when the user asks for diagnostics.

## Start a task

1. Resolve the exact app with `list_apps`.
2. Spawn its visual session with `scripts/cu-session.sh spawn <App>`.
3. Show the PiP for that app. Never raise the app merely so the user can see it.
4. Call `get_app_state` before the first action in each turn.
5. Prefer a fresh `element_index`; do not reuse indexes after navigation, dialogs, or failed actions.
6. Use the action result as the next state, or snapshot again when the UI changed substantially.

If the user attached an app-mention file, target only the app/window named in its front matter. Refresh mention files with `scripts/cu-session.sh mentions`.

For parallel app windows, use `scripts/cu-session.sh windows`, spawn one session per target, and read `~/.cursor/computer-use/HANDOFF.md` plus `SUMMARY.md` instead of dumping raw Accessibility trees into the conversation.

## Action preference

1. `set_value` for an exposed editable control.
2. Accessibility action using `element_index`.
3. `app_post` for blank-area/window-relative interaction.
4. `sky_click` for a covered Chromium/Electron window on macOS.
5. Coordinate input only when the current screenshot/tree makes the target unambiguous.

Never use `click_method: "global"`. Never set `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`. If background delivery fails, stop and report the limitation rather than moving the real pointer or stealing focus.

## iOS Simulator

Use `scripts/simulator.sh` / `xcrun simctl` for device status, app launch/terminate, screenshots, logs, and installed-app lookup. Use Computer Use only for taps, gestures, and text inside the guest UI. Do not click Simulator Home to switch apps when `simctl launch` can do it deterministically.

## Safety

This is the user’s live session.

- Do not open password managers, unrelated private windows, or sensitive apps unless required by the user’s request.
- Confirm immediately before deletion, sending/publishing, purchases, financial actions, creating credentials, changing access, or submitting a high-impact form.
- Hand CAPTCHA/security barriers and final password-change submission to the user.
- Ordinary reading, navigation, reversible local edits, and typing an unsent draft do not need repeated confirmation.
- Stop immediately when the user cancels, presses Escape in the PiP, or clicks Stop Sharing.

## Manual fallback

When Cursor’s MCP connection is unavailable but the runtime is healthy, use the local shims so all calls still share the pinned resolver and safety environment:

```bash
scripts/bin/open-computer-use call list_apps
scripts/bin/ocu call get_app_state --args '{"app":"Notes"}'
```

See [references/usage.md](references/usage.md) and [references/troubleshooting.md](references/troubleshooting.md).

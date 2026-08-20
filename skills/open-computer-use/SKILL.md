---
name: open-computer-use
description: Operate real desktop apps in the background through the Open Computer Use MCP server. Use when the user wants computer use, GUI automation, clicking, typing, scrolling, or inspecting macOS, Linux, or Windows apps that are not available as structured APIs.
---

# Open Computer Use

Drive the user's desktop **in the background**, the way Codex Computer Use does. Prefer the `open-computer-use` MCP tools over the CLI.

The user keeps their real mouse, keyboard, and frontmost window. You act under the hood with accessibility / posted events. The tinted overlay pointer is **your** cursor, not theirs.

Watch the target in the floating **Currently Sharing** Picture-in-Picture card (Codex-style), not by stealing the full Simulator/desktop. At the start of a GUI task, run `scripts/cu-session.sh spawn <App>` (or `scripts/computer-use-pip.sh show <App>`). Never raise the real app just so the user can see it.

For parallel windows, spawn one cursor per app (`scripts/cu-session.sh spawn`) and Read `~/.cursor/computer-use/HANDOFF.md` plus `SUMMARY.md` instead of dumping MCP screenshots into chat. `cu-session.sh windows` is the Window2 `list_windows` analogue. See [../cu-sessions/SKILL.md](../cu-sessions/SKILL.md).

If the user **@mentions** an app (a `rules/apps/*.mdc` rule or `.cursor/computer-use/apps/*.md` file), target **only that app**. Refresh mention files with `scripts/cu-session.sh mentions`.

## iOS Simulator

If the target is the iOS Simulator, also read [../ios-simulator/SKILL.md](../ios-simulator/SKILL.md). Codex uses `xcrun simctl` for launch, terminate, framebuffer screenshots, and logs. Computer Use is only for taps and typing inside the guest app. Do not click Simulator Home to switch apps.

macOS requires 14.0 or later. Windows and Linux need a logged-in graphical session.

Exposed tools: `list_apps`, `get_app_state`, `click`, `perform_secondary_action`, `scroll`, `drag`, `type_text`, `press_key`, `set_value`.

## Background contract (non-negotiable)

- Do **not** move the system pointer.
- Do **not** steal keyboard focus, raise windows, switch Spaces, or activate the target app just to operate it.
- Do **not** set `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1` or use `click_method: "global"`.
- Keep the plugin-owned `MultiCursorOverlay` enabled. The runtime cursor is intentionally off so only one software cursor is rendered.
- Leave the user in whatever app they were using. Target other apps even if they are behind Cursor.
- The overlay cursor is a visual cue that you are acting. The real OS cursor stays where the user left it.

If a click cannot be delivered without grabbing the real pointer, stop and say so. Do not escalate to global pointer input.

## Core workflow

1. If MCP tools are missing, read [references/installation.md](references/installation.md) and ask the user to enable the plugin / MCP server, then reload Cursor.
2. On macOS, run `scripts/cu-permissions.sh status` (or `open-computer-use doctor`) **only if a tool call fails with a TCC error**. If status is `ok` / `granted`, do **not** ask the user to grant Accessibility or Screen Recording again, and do not launch onboarding.
3. Call `list_apps` before acting. Use the returned app name or bundle id.
4. Call `get_app_state` for that app. The default snapshot is enough for most UI work. Prefer apps that already have a visible window. Do not ask the user to click the target app into the foreground.
5. Prefer `element_index` from the latest `get_app_state` result. Never reuse indexes across sessions or after navigation, modals, or failed actions.
6. For chat history, email bodies, or other long text, call `get_app_state` with `text_limit: 1000` or `text_limit: "max"`.
7. If a visible long page or list looks incomplete after scrolling, raise `max_tree_nodes` or `max_tree_depth`.
8. Prefer `set_value` for editable controls. Use coordinate `click`, `scroll`, and `drag` only when the tree has no safer target.
9. After each action, use the refreshed state the tool returns. Re-snapshot if the UI changed a lot.

## Operating rules

- This is the user's real session. Do not open password managers, unrelated private windows, or sensitive apps unless the user asked for that task.
- **Hand control to the user** for CAPTCHA/security-barrier bypasses and the final submission of a password change.
- **Always confirm immediately before** deleting data, sending or publishing as the user, creating credentials, changing access permissions, accepting a purchase/financial transaction, or submitting medical/legal/high-impact forms.
- Explicit approval in the user's request is enough for ordinary login, file upload/move/rename, and accepting a routine site warning; otherwise confirm at action time.
- Do not interrupt for reading, navigation, scrolling, opening apps, reversible local edits, or typing non-sensitive draft text before submission.
- If MCP is down, fall back to `open-computer-use call ...` / `ocu call ...`. See [references/usage.md](references/usage.md). Keep those CLI calls on the same overlay / no-global-pointer path.

## Click methods

Omit `click_method` unless needed (`auto` is semantic-first and already avoids the real pointer):

- `accessibility`: element accessibility action; requires `element_index`; safest background path
- `app_post`: post a mouse event to the app without moving the real pointer (macOS, Windows). Use for blank-area or overlay hits
- `sky_click`: macOS-only covered Chromium / background-window clicks; does not move the pointer, deactivate the front app, or raise the target. Use when Chrome/Electron is behind another window
- `global`: **forbidden** unless the user explicitly asked. Moves the real pointer and can steal focus

Covered window: try `sky_click` (Chromium) or `app_post` / `accessibility`. Never bring the window forward as a workaround.

## References

- [references/installation.md](references/installation.md)
- [references/usage.md](references/usage.md)
- [references/troubleshooting.md](references/troubleshooting.md)

---
name: computer-use
description: Operate a desktop app with Open Computer Use MCP tools.
---

# Computer use

Use the `open-computer-use` skill and MCP tools to complete the user's GUI task **in the background**.

Keep the user's real pointer, keyboard, and frontmost window alone. The overlay cursor is the agent cursor. Show the Codex-style **Currently Sharing** PiP (close / minimize in the title bar) instead of covering Cursor with the real Simulator window.

If the user @mentioned an app rule or `.cursor/computer-use/apps/*.md` file, target **only that app**.

1. Show the PiP (`scripts/computer-use-pip.sh show Simulator` or the named app) if it is not already up.
2. Call `list_apps` and pick the requested app (or the @mentioned app).
3. Call `get_app_state` before every targeted action, even if the app is not frontmost.
4. Prefer `element_index` plus `click`, `set_value`, `type_text`, or `press_key`. Use `sky_click` only for covered Chromium windows. Never `click_method: "global"`.
5. Do not ask to re-grant macOS permissions when `scripts/cu-permissions.sh status` is ok.
6. Ask before sending, deleting, purchasing, or any other externally visible change.
7. Report what changed in the UI when finished.

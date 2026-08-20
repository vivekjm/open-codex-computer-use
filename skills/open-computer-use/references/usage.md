# Usage

Prefer Cursor MCP tools. Use the CLI only when MCP is unavailable.

This plugin is locked to Codex-style **background** computer use: a virtual overlay cursor, posted/accessibility events, and no real-pointer movement.

## MCP tools

```text
list_apps
get_app_state
click
perform_secondary_action
scroll
drag
type_text
press_key
set_value
```

Typical loop:

1. `list_apps`
2. `get_app_state` with `{ "app": "Notes" }`
3. `click` / `set_value` / `type_text` / `press_key` using `element_index` from that snapshot
4. Read the returned state; snapshot again after large UI changes

Keep the user in their current app. Snapshot and act on other windows even when they are behind Cursor.

At the start of a GUI task, show the Codex-style PiP and bind a session cursor:

```sh
./scripts/cu-session.sh spawn Simulator
./scripts/cu-session.sh snapshot Simulator
```

Read `~/.cursor/computer-use/HANDOFF.md` and `SUMMARY.md` for compact AX context. Spawn additional apps to get extra cursors. `scripts/cu-session.sh windows` lists window bounds (Window2-style). The user watches **Currently Sharing**. Do not raise the real Simulator over Cursor. `Stop Sharing` dismisses the card.

## Overlay cursor vs real pointer

The tinted software cursor is the **agent** cursor. The user's hardware pointer must stay put.

Runtime env (already set by the launcher):

- `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` — runtime overlay off; PiP owns the single multi-window cursor
- `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` — **unset**
- App-agent proxy remains enabled for background event delivery

Never pass `click_method: "global"`. Prefer omitted/`auto`, then `accessibility`, `app_post`, or macOS `sky_click` for covered Chromium windows.

## Text and tree budgets

Snapshot text truncates at 500 characters by default (`...` means truncated, not missing).

- Longer content: `text_limit: 1000` or `text_limit: "max"`
- Incomplete long pages: `max_tree_nodes: 3000`, `max_tree_depth: 96`

Action tools refresh state with the default budgets. Request a larger snapshot again if you still need full text or a deeper tree.

## CLI fallback

Do not prefix CLI calls with the global-pointer env. Overlay stays on by default.

```sh
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
open-computer-use call click --args '{"app":"TextEdit","element_index":"0"}'
open-computer-use call set_value --args '{"app":"TextEdit","element_index":"1","value":"Draft"}'
```

Covered Chrome window, no raise:

```sh
open-computer-use call click --args '{"app":"Google Chrome","x":875,"y":375,"click_method":"sky_click"}'
```

Reuse element indexes in one process:

```sh
open-computer-use call --calls '[
  {"tool":"get_app_state","args":{"app":"TextEdit"}},
  {"tool":"click","args":{"app":"TextEdit","element_index":"1"}},
  {"tool":"type_text","args":{"app":"TextEdit","text":"Hello"}}
]'
```

## Platform notes

- **macOS**: Accessibility + ScreenCaptureKit + overlay cursor. Default paths (`auto`, `app_post`, `sky_click`) do not move the real pointer or steal key focus.
- **Windows**: UI Automation. Must run in the logged-in desktop session. Do not enable `OPEN_COMPUTER_USE_WINDOWS_ALLOW_FOCUS_ACTIONS` or `OPEN_COMPUTER_USE_WINDOWS_ALLOW_APP_LAUNCH`.
- **Linux**: AT-SPI2. Wayland screenshots and coordinate input are best-effort. No overlay cursor on Linux.

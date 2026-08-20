# Open Computer Use for Cursor

Cursor plugin wrapper around [iFurySt/open-codex-computer-use](https://github.com/iFurySt/open-codex-computer-use). It packages the open-source Computer Use MCP server with a Cursor skill, commands, and a local plugin manifest.

Official Codex Computer Use is not open source. This plugin uses the community MCP runtime, configured the same way Codex uses it:

- A floating **Currently Sharing** Picture-in-Picture card with **close / minimize** window controls
- **@mention** targeting so a chat can aim Computer Use at one app
- A **virtual overlay cursor**
- Background accessibility / posted events
- **No theft of the user's real pointer or frontmost window**

## What you get

| Piece | Role |
| --- | --- |
| MCP server | `list_apps`, `get_app_state`, `click`, `type_text`, `press_key`, `set_value`, and related tools |
| Overlay cursor | Agent-only software pointer. Your hardware mouse stays put |
| Picture in Picture | Codex-style **Currently Sharing** live preview with close, minimize, and **Stop Sharing** |
| @mentions | Type `@` and pick an app rule (`rules/apps/`) or `.cursor/computer-use/apps/*.md` |
| Skill | `/open-computer-use` — background GUI operation, no focus stealing |
| Commands | `/computer-use`, `/mention-apps`, `/show-computer-use-pip`, `/inspect-simulator`, `/list-desktop-apps`, `/inspect-app` |
| Rule | Agent-decides guidance for GUI tasks |

## Behavior

The MCP launcher always:

- Uses the PiP app's multi-window Codex-style cursor as the sole overlay renderer
- Sets `OPEN_COMPUTER_USE_VISUAL_CURSOR=0` for the runtime to prevent a duplicate cursor
- Leaves the macOS `Open Computer Use.app` agent enabled so that overlay can draw
- Unsets `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS` so clicks cannot fall back to moving the real pointer

You can keep typing in Cursor while the agent clicks another app behind it. Watch the target in the PiP card instead of switching to the real Simulator window. Covered Chromium windows should use `click_method: "sky_click"` instead of being brought forward.

Use **Stop Sharing**, the close button, or **Esc** while the PiP is active to
cancel. The plugin also stops and clears all cursors when the macOS session
locks or switches users.

```sh
./scripts/computer-use-pip.sh show Simulator
./scripts/computer-use-pip.sh stop
```

The PiP app does not nag for a second Screen Recording grant. When PiP capture is
not authorized it shows the latest screenshot captured by the already-authorized
Computer Use runtime. Simulator uses the guest framebuffer through
`xcrun simctl io booted screenshot`.

Codex-style Simulator and multi-window control:

```sh
./scripts/cu-session.sh spawn Simulator
./scripts/cu-session.sh spawn "Google Chrome"
./scripts/cu-session.sh windows
./scripts/cu-session.sh snapshot Simulator
./scripts/cu-session.sh click Simulator --element 13
./scripts/cu-session.sh stop
./scripts/simulator.sh status
```

Shared context for any Cursor chat: `~/.cursor/computer-use/HANDOFF.md` and `SUMMARY.md`. Each spawned app gets its own overlay cursor on that window.

Refresh chat @mention files:

```sh
./scripts/cu-session.sh mentions
```

## Install

```sh
npm install -g open-computer-use
```

On macOS 14+, check TCC once. Do not re-run onboarding if status is already granted:

```sh
./scripts/cu-permissions.sh status
```

Load this folder as a local Cursor plugin:

```sh
./scripts/install-local-plugin.sh
```

Reload the window (**Developer: Reload Window**). Enable `open-computer-use` under **Customize → MCP** if it is off.

This project also ships `.cursor/mcp.json`, so the server starts for this workspace even before the local plugin is picked up.

## Use

Ask the agent to operate a real app, @mention the app, or run a command:

- `@Simulator tap Collections`
- `@Notes write a grocery list` (mention the **Computer Use target — Notes** rule, or `.cursor/computer-use/apps/notes.md`)
- `/mention-apps`
- `/list-desktop-apps`
- `/inspect-app`
- `/inspect-simulator`
- `/computer-use`
- `/show-computer-use-pip`

The agent should snapshot UI state, then act with `element_index` targets, without moving your mouse. It should ask before sending, deleting, or other externally visible changes.

## Layout

```text
.
├── .cursor-plugin/plugin.json
├── mcp.json
├── skills/open-computer-use/
├── apps/ComputerUsePiP/
├── commands/
├── rules/
├── agents/
└── assets/logo.svg
```

## License

MIT. Runtime and skill guidance come from [open-computer-use](https://github.com/iFurySt/open-codex-computer-use), also MIT.

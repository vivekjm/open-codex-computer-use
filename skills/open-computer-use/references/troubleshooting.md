# Troubleshooting

## MCP server not listed in Cursor

1. Confirm `.cursor-plugin/plugin.json` and `mcp.json` exist in the plugin root.
2. Confirm a real local copy exists at `~/.cursor/plugins/local/open-computer-use`; Cursor rejects symlinks that escape that directory.
3. Reload the window.
4. Run `npx -y open-computer-use -h` to confirm the package launches.

## Unsupported macOS

Requires 14.0+. On older versions the binary fails with a `dyld` / minimum-version error. `doctor` and TCC changes cannot fix that.

## Permissions

```sh
./scripts/cu-permissions.sh status
```

If both Accessibility and Screen Recording are `granted`, the agent must not ask again. `open-computer-use doctor` only launches onboarding when something is actually missing.

The PiP preview app is separate from `Open Computer Use.app`. If PiP itself is
not authorized for live capture, it automatically uses the runtime's latest
snapshot instead. Do not ask for another grant. Simulator previews use `simctl`.

## App not found

1. `list_apps`
2. Use an exact name or bundle id from that list
3. Confirm the app is running with a visible, non-minimized window

Do not silently switch to a different app.

## Empty snapshot

Common causes: no visible window, minimized/hidden window, missing Screen Recording, or a command running outside the logged-in desktop session.

## Truncated text or incomplete trees

`...` at 500 characters is truncation. Request `text_limit: 1000` or `"max"`. If the screenshot shows more widgets than the tree, raise `max_tree_nodes` / `max_tree_depth`.

## Element action fails

Re-run `get_app_state`. Confirm `element_index` still points at the intended control. Prefer `set_value` for editable fields. Use coordinates only after the semantic path fails.

## Overlay cursor missing / real mouse moved

The PiP app draws the only software cursor; the runtime cursor stays off to prevent duplicates. The launcher unsets global pointer fallbacks. If the real pointer moved, the process was started without that launcher, or `click_method: "global"` was used.

Reload Cursor after changing `mcp.json`. Confirm MCP env does **not** include `OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS`. Overlay drawing needs the `Open Computer Use.app` agent (do not set `OPEN_COMPUTER_USE_DISABLE_APP_AGENT_PROXY`).

If a background click fails, retry with `app_post` or macOS `sky_click`. Do not raise the target window or enable global pointer fallbacks.

## Safety

Do not bypass TCC, enable global pointer fallbacks, disable the overlay cursor, or touch password managers / sensitive apps unless the user explicitly requested it. Pause before submit, send, delete, purchase, or approve.

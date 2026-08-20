# Installation

Read this when Open Computer Use is missing, broken, or not connected in Cursor.

## Runtime

Install the CLI once:

```sh
npm install -g open-computer-use
open-computer-use -h
```

macOS 14.0+ is required. Check with `sw_vers -productVersion`. Older macOS cannot run the binary; permissions will not fix that.

## Cursor plugin

This repo is a Cursor plugin. Load it locally:

```sh
./scripts/install-local-plugin.sh
```

Cursor rejects local-plugin symlinks that resolve outside `~/.cursor/plugins/local`,
so the installer creates a synchronized real copy. Run it again after updating
the source. Cursor normally reloads the plugin automatically; otherwise run
**Developer: Reload Window**. Confirm `open-computer-use` appears under
Customize → Plugins / MCP.

This workspace also has `.cursor/mcp.json`, which starts the same stdio server for this project.

The PiP app owns the Codex-style multi-window overlay. The launcher sets the runtime cursor off (`OPEN_COMPUTER_USE_VISUAL_CURSOR=0`) to avoid drawing two cursors, and keeps global pointer fallbacks off.

## macOS permissions

```sh
./scripts/cu-permissions.sh status
```

That prints the current TCC state and does **not** nag if Accessibility and Screen Recording are already granted. Only run `open-computer-use doctor` (or `./scripts/cu-permissions.sh doctor`) when status reports missing.

The Picture-in-Picture app (`com.vivek.open-computer-use.pip`) is separate from
`Open Computer Use.app`, but it does not request another grant. Without its own
Screen Recording authorization it displays the latest screenshot from the
already-authorized Computer Use runtime. Simulator PiP uses `simctl`.

Release builds should use a stable signing identity so macOS keeps the grant across
rebuilds:

```sh
CU_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-computer-use-pip.sh
```

Local ad-hoc builds remain prompt-free to compile. A stable identity is only
needed when distributing a build that should retain optional live PiP capture.

Windows and Linux skip this step but still need a logged-in desktop session.

## Verify

```sh
open-computer-use call list_apps
open-computer-use call get_app_state --args '{"app":"TextEdit"}'
```

If this fails, read [troubleshooting.md](troubleshooting.md).

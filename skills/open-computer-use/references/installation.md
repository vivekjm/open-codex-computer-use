# Installation

## Recommended

From the repository root on macOS 14+:

```bash
./scripts/setup.sh
```

This installs the pinned upstream runtime in the user cache, builds/signs the PiP app, verifies the plugin, and installs it under `~/.cursor/plugins/local/open-computer-use`.

Reload Cursor with **Developer: Reload Window**, then enable `open-computer-use` in **Customize → MCP**.

## Repair

```bash
./scripts/doctor.sh --repair --live
```

The doctor reports missing tools, runtime resolution, PiP build state, plugin installation, static verification, and an optional real MCP handshake.

## Runtime only

```bash
./scripts/ocu-runtime.sh install
./scripts/ocu-runtime.sh status
```

A global `npm install -g` is not required. The plugin pins `open-computer-use@0.1.51` in a versioned cache under `~/.cursor/open-computer-use/runtimes/`.

## Permissions

macOS privacy grants cannot be silently automated. Run:

```bash
./scripts/ocu-runtime.sh doctor
```

Grant Accessibility and Screen Recording to the host/helper shown by macOS, then restart Cursor. Do not repeatedly reset TCC or request grants when `scripts/cu-permissions.sh status` already reports `ok`.

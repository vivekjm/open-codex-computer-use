# Open Computer Use for Cursor

A macOS Cursor plugin that gives an agent a **background desktop-control lane**: app-scoped Accessibility actions, one virtual cursor per target window, a live “Currently Sharing” Picture-in-Picture card, compact cross-turn state, and hard guards against moving the user’s physical pointer.

This repository is a Cursor integration and observability layer around the open-source [`open-computer-use`](https://github.com/iFurySt/open-codex-computer-use) runtime. It is not the proprietary OpenAI Computer Use implementation and is not affiliated with OpenAI, Cursor, or Apple.

## What is functional in v0.8.0

| Capability | Status |
|---|---|
| Cursor MCP tools (`list_apps`, `get_app_state`, click, type, scroll, drag, keys, values) | Working through a pinned managed runtime |
| First-run runtime installation | Automatic or explicit; no global npm install required |
| Background app interaction | Semantic Accessibility / app-posted events; global-pointer fallback blocked |
| Multiple app/window sessions | Independent session registry and colored software cursors |
| Picture in Picture | Native Swift app using ScreenCaptureKit, with Simulator framebuffer fallback and Stop Sharing |
| App targeting | Cursor `@mention` files plus per-window bindings |
| Context continuity | Compact `HANDOFF.md`, `SUMMARY.md`, AX diffs, and local screenshots |
| Safety and cancellation | Fail-closed hooks for global-pointer attempts, Escape/Stop cleanup, session-end teardown |
| Reliability checks | Runtime resolver tests, JSON/shell/Python validation, MCP protocol smoke test, macOS CI build |

The goal is **Codex-style behavior**, not a claim of byte-for-byte parity. OpenAI’s private sandboxing, agent orchestration, and internal desktop runtime are outside this repository. See [Architecture](docs/ARCHITECTURE.md) for the exact boundary.

## Requirements

- macOS 14 or newer
- Cursor with local plugin and stdio MCP support
- Node.js/npm, used once to install the pinned upstream runtime
- Python 3
- Xcode Command Line Tools (`swiftc`, `codesign`)
- Accessibility and Screen Recording permission when macOS requests them

## Install

Clone the repository, then run:

```bash
./scripts/setup.sh
```

Setup performs five concrete steps:

1. Installs the pinned `open-computer-use@0.1.51` runtime into `~/.cursor/open-computer-use/runtimes/`.
2. Builds and ad-hoc signs `dist/Computer Use PiP.app`.
3. Runs static checks and a fake-runtime MCP handshake.
4. Copies the plugin to `~/.cursor/plugins/local/open-computer-use`.
5. Runs installation diagnostics and, in an interactive terminal, opens the permission doctor.

Then run **Developer: Reload Window** in Cursor. Open **Customize → MCP** and make sure `open-computer-use` is enabled.

Useful setup and repair commands:

```bash
./scripts/setup.sh --no-permissions
./scripts/doctor.sh --repair
./scripts/doctor.sh --live
```

## Use it

In Cursor, ask for a desktop task normally or target an app explicitly:

```text
@Notes create a draft grocery list, but do not share or send it.
@Calendar inspect tomorrow’s schedule.
@Simulator open the installed app and verify the login screen.
```

The intended execution loop is:

1. Spawn or bind a session cursor for the app.
2. Call `list_apps`, then `get_app_state`.
3. Prefer the latest semantic `element_index` over coordinates.
4. Act with `accessibility`, `app_post`, or `sky_click` as appropriate.
5. Verify the returned state and update the compact handoff.
6. Stop on user cancellation, Escape, session end, or **Stop Sharing**.

Manual tools are available for debugging:

```bash
./scripts/cu-session.sh windows
./scripts/cu-session.sh spawn Notes
./scripts/cu-session.sh snapshot Notes
./scripts/cu-session.sh list
./scripts/cu-status.sh
./scripts/computer-use-pip.sh show Notes
./scripts/computer-use-pip.sh stop
```

All CLI calls resolve through `scripts/ocu-runtime.sh`. The same command works whether the runtime is bundled, installed in the managed cache, available globally as `open-computer-use`, or exposed as `ocu`.

## Runtime resolution

Resolution order is deterministic:

1. `OPEN_COMPUTER_USE_RUNTIME_BIN` override
2. A native/bundled runtime inside the plugin
3. The managed pinned runtime cache
4. `open-computer-use` or `ocu` already on `PATH`
5. First-run installation of `OPEN_COMPUTER_USE_NPM_SPEC`, enabled by default

Inspect or control it with:

```bash
./scripts/ocu-runtime.sh status
./scripts/ocu-runtime.sh status --json
./scripts/ocu-runtime.sh path
./scripts/ocu-runtime.sh install
OPEN_COMPUTER_USE_AUTO_INSTALL=0 ./scripts/ocu-runtime.sh status
```

The default package is pinned rather than using `latest`, so a Cursor restart cannot silently pull a different desktop runtime. Set `OPEN_COMPUTER_USE_NPM_SPEC` deliberately when testing an upstream release.

## Safety model

This plugin operates the user’s real logged-in desktop session. The following rules are enforced in both agent instructions and hooks:

- Never enable global pointer fallbacks or use `click_method: "global"`.
- Never move the physical pointer merely because semantic/background delivery failed.
- Do not activate or raise a target window solely to automate it.
- Ask immediately before destructive, financial, permission-changing, credential-creating, sending, publishing, or other externally visible actions.
- Hand CAPTCHAs, security barriers, and final password-change submission back to the user.
- Keep screenshots, AX trees, and session data local under `~/.cursor/computer-use/`.

The MCP and shell safety hooks fail closed for global-pointer violations. Cursor still controls its normal MCP approval UI according to the user’s Run Mode and settings. See [SECURITY.md](SECURITY.md).

## Verify and develop

```bash
make verify       # network-free static checks + fake-runtime MCP protocol test
make build-pip    # compile and sign the native PiP app on macOS
make smoke        # live initialize + tools/list against the installed runtime
make live-smoke   # MCP smoke plus list_apps
make doctor       # installation report
```

GitHub Actions runs the network-free verification on Linux and compiles/codesigns the PiP app on macOS. `make verify` checks manifests, MCP configs, hooks, plist consistency, executable bits, shell/Python syntax, runtime resolution, an MCP JSON-RPC handshake, context-bus parsing, lifecycle locking, and safety-hook behavior.

## State and logs

| Path | Purpose |
|---|---|
| `~/.cursor/computer-use/sessions.json` | Active and retained app/window sessions |
| `~/.cursor/computer-use/HANDOFF.md` | Compact state for the current agent turn |
| `~/.cursor/computer-use/SUMMARY.md` | Rolling event summary |
| `~/.cursor/computer-use/sessions/<id>/` | AX snapshots, diffs, screenshot, metadata |
| `/tmp/computer-use-pip.json` | PiP/overlay command channel |
| `/tmp/computer-use-sync.log` | Asynchronous hook ingestion diagnostics |
| `/tmp/computer-use-build.log` | On-demand PiP build output |

## Troubleshooting

**MCP is disconnected**

```bash
./scripts/doctor.sh --repair --live
```

Reload Cursor after a successful repair and check Customize → MCP if the server is disabled.

**The runtime is missing after restart**

```bash
./scripts/ocu-runtime.sh install
./scripts/ocu-runtime.sh status
```

The managed install is independent of shell profile configuration, so Cursor does not depend on a global npm bin path.

**The PiP is blank**

Run `./scripts/ocu-runtime.sh doctor`, grant Screen Recording to the relevant host/helper, then restart Cursor. Simulator preview can still use `xcrun simctl io booted screenshot` when ScreenCaptureKit preview is unavailable.

**An app action cannot be delivered in the background**

Fetch a fresh state, use an Accessibility element, or use `app_post` / `sky_click` for supported windows. The plugin intentionally stops rather than falling back to the real mouse.

## License

MIT. The separately installed upstream runtime is governed by its own repository and package license.

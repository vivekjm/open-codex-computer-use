# Architecture

## Scope

This project is the Cursor-facing orchestration, visibility, and safety layer. The separately installed `open-computer-use` package supplies the platform automation MCP server. On macOS, this repository adds a native PiP/overlay process and a compact local context bus.

```text
Cursor Agent
  │
  ├─ MCP stdio ──> scripts/launch-open-computer-use.sh
  │                  └─ scripts/ocu-runtime.sh
  │                       └─ pinned/native upstream runtime
  │                            ├─ Accessibility tree
  │                            ├─ semantic/background actions
  │                            └─ post-action screenshots
  │
  ├─ before/after MCP hooks
  │      ├─ block global-pointer input
  │      ├─ spawn app/window session
  │      └─ ingest result into compact state
  │
  └─ local state ──> scripts/lib/context_bus.py
                         ├─ sessions.json
                         ├─ HANDOFF.md / SUMMARY.md
                         ├─ AX snapshots and diffs
                         └─ PiP command JSON

Computer Use PiP.app
  ├─ ScreenCaptureKit app-window preview
  ├─ simctl framebuffer preview for Simulator
  ├─ one non-interactive overlay cursor per session/window
  └─ Stop/Escape/session-inactive cleanup
```

## Runtime lifecycle

`scripts/ocu-runtime.sh` is the supported runtime entrypoint. It resolves an explicit override, bundled native binaries, the versioned managed npm cache, or an existing PATH installation. When none exists and auto-install is enabled, it atomically installs the pinned package into the user cache under an installation lock.

Two shims, `scripts/bin/open-computer-use` and `scripts/bin/ocu`, keep older helpers compatible without requiring a global npm binary. The MCP launcher and manual session CLI prepend this directory to `PATH`.

The package default is `open-computer-use@0.1.51`. Updating it is an explicit source change and must pass `make verify`, `make smoke`, and a real macOS app test.

## MCP transport

The upstream server uses newline-delimited JSON-RPC over stdio. `scripts/mcp-smoke.py` verifies:

1. `initialize` using protocol `2025-03-26`
2. server identity `open-computer-use`
3. `notifications/initialized`
4. `tools/list`
5. the minimum expected desktop action surface

No MCP server diagnostic may write ordinary logs to stdout; stdout is reserved for JSON-RPC.

## Session model

A session binds an app name and, when available, a concrete ScreenCaptureKit window ID to a stable session ID, color, virtual cursor position, last action, focused Accessibility element, and latest screenshot/tree.

Multiple active sessions are rendered simultaneously. The PiP can cycle through them while each overlay remains constrained to its window frame. The context bus gives Cursor compact Markdown and AX diffs instead of repeatedly injecting full screenshots and trees. Raw data stays on disk for recovery and debugging.

## Safety boundary

The background contract is stricter than ordinary GUI automation:

- physical pointer fallback is disabled in the launcher
- a fail-closed MCP hook rejects `click_method=global`
- a fail-closed shell hook rejects attempts to set the global-pointer fallback environment variable
- Cursor itself is not selected as an automation target
- lifecycle cleanup writes a stopped marker before asynchronous result ingestion can resurrect a session

This is not an OS sandbox. The runtime acts inside the user’s real session with the permissions granted to its host/helper, so agent-level confirmation rules remain mandatory.

## Known boundaries

- The custom PiP and overlay are macOS-only even though the upstream runtime supports other desktop platforms.
- Background delivery varies by application and UI framework; some apps expose incomplete Accessibility trees.
- The plugin cannot duplicate OpenAI’s private agent scheduler, sandbox implementation, or internal Computer Use runtime.
- Cursor decides its own MCP confirmation UI; a hook `allow` result does not guarantee zero-click execution in every Run Mode.
- Screen Recording and Accessibility grants cannot be silently automated by this repository.

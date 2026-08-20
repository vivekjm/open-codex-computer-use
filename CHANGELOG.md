# Changelog

## 0.8.0 — 2026-08-20

- Added a single runtime resolver with an atomic, pinned managed install of `open-computer-use@0.1.51`.
- Removed the hidden dependency on a globally installed command by providing local `open-computer-use` and `ocu` shims.
- Added one-command setup, repairable diagnostics, and a real MCP initialize/tools-list smoke test.
- Added fail-closed hook guards for global-pointer actions while preserving Cursor’s normal confirmation behavior.
- Hardened cleanup, status, permission, session, plugin-install, and PiP build scripts around the shared runtime path.
- Added Linux static CI and a macOS native PiP compile/codesign job.
- Documented the architecture, safety boundary, runtime lifecycle, feature scope, and known non-parity areas.

## 0.7.1 — 2026-08-20

- Initial Cursor plugin scaffold with PiP, overlay cursors, app mentions, Simulator helpers, and compact session state.

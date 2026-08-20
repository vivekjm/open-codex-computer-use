---
name: spawn-cursors
description: Spawn one or more Computer Use overlay cursors and print the shared HANDOFF context.
---

# Spawn cursors

Use the `cu-sessions` skill.

1. For each named app (default Simulator), run `scripts/cu-session.sh spawn <App>`.
2. `scripts/cu-session.sh windows` to see Window2-style targets, then `snapshot <App>` to fill compact AX context.
3. Read `~/.cursor/computer-use/HANDOFF.md` and `SUMMARY.md` and summarize active cursors (id, app, color, overlay x/y, focused element).
4. Keep Cursor frontmost. Cycle PiP with the on-card arrows if several sessions are live. Each window keeps its own overlay cursor.
5. Clicks: `scripts/cu-session.sh click <App> --element N`. Do not use `click_method: "global"`.

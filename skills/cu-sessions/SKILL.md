---
name: cu-sessions
description: Spawn multiple Computer Use cursors across apps/windows and share compact AX context with Cursor. Use when the user wants parallel computer use, extra cursors, context handoff, or Codex-style window targeting.
---

# Multi-window Computer Use sessions

Codex Computer Use (Sky Window / Window2) binds **one software cursor per window**, then shares compact accessibility text — not raw screenshot JSON — with the model. This plugin mirrors that.

## Spawn cursors

```sh
./scripts/cu-session.sh spawn Simulator
./scripts/cu-session.sh spawn "Google Chrome"
./scripts/cu-session.sh list
```

Each spawn gets its own color (`#606acc` first, matching Codex accent) and stays bound to that app. PiP arrows cycle sessions. The PiP window has close and minimize controls. Do not raise those apps over Cursor.

## @mention an app

In Cursor chat, type `@` and pick:

- a rule such as **Computer Use target — Simulator** (`rules/apps/`)
- or a generated file in `.cursor/computer-use/apps/` (`./scripts/cu-session.sh mentions`)

That mention is the Window2 target for the turn.

## Share context efficiently

After UI work, ingest a snapshot into the bus:

```sh
./scripts/cu-session.sh snapshot Simulator
./scripts/cu-session.sh context
```

Read `~/.cursor/computer-use/HANDOFF.md` (and `SUMMARY.md`) in Cursor instead of pasting MCP image payloads. Those files contain:

- session id, app, overlay color, overlay cursor coordinates
- focused element index + label
- screenshot **path** (file on disk)
- AX **diff** when possible, otherwise a truncated tree
- a rolling event log (`SUMMARY.md` / `events.jsonl`)

Full trees live in `~/.cursor/computer-use/sessions/<id>/ax.txt`. Screenshots stay in `latest.png`.

## Target like Window2

`scripts/cu-session.sh windows` lists on-screen windows (app, title, bounds) the way Sky `list_windows` does. Bind one cursor per window with `spawn` / `bind`. Clicks go through `scripts/cu-session.sh click <App> --element N` so the overlay moves on that window only — never `click_method: "global"`.

Every action must name the app/window for that cursor. Never reuse `element_index` across sessions or after navigation.

- Simulator lifecycle: `scripts/simulator.sh` (`simctl`)
- Simulator/guest taps: Computer Use on `Simulator`
- Other Mac apps: Computer Use on that app’s session

Prefer accessibility text over screenshots. Fetch a screenshot only when the tree is incomplete.

## Stop

When the task is done, overlay cursors must disappear:

```sh
./scripts/cu-session.sh stop
```

That marks sessions stopped, calls `open-computer-use turn-ended`, and quits PiP. Close on the PiP window does the same. Agent `stop` / session-end hooks also run this cleanup so cursors are not left on other displays.

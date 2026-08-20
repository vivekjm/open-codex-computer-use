---
name: mention-apps
description: Refresh @mention files for desktop apps so chat can target Computer Use at a specific app.
---

# Mention apps

1. Run `scripts/cu-session.sh mentions`.
2. Tell the user they can type `@` and pick:
   - a rule under `rules/apps/` (Simulator, Chrome, Safari, Calendar, Notes, Slack, Finder)
   - or a generated file in `.cursor/computer-use/apps/`
3. Do not ask them to re-grant macOS permissions if `scripts/cu-permissions.sh status` prints `ok`.

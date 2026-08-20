---
name: inspect-app
description: Snapshot the current UI state of a desktop app.
---

# Inspect app

1. If the user named an app, use that name or bundle id. Otherwise call `list_apps` and ask which one to inspect.
2. Call `get_app_state` for that app. Do not bring it to the front.
3. Summarize windows, focused control, and the most useful `element_index` targets.
4. If text is truncated or the tree looks incomplete, retry with a larger `text_limit` or tree budget.

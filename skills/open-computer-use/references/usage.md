# Usage

## MCP workflow

```text
list_apps
get_app_state {"app":"Notes"}
click {"app":"Notes","element_index":12}
type_text {"app":"Notes","text":"Draft text"}
```

Use the latest state returned by every action. Semantic element targeting is safer than coordinates.

## Session/PiP helpers

```bash
./scripts/cu-session.sh windows
./scripts/cu-session.sh spawn Notes
./scripts/cu-session.sh snapshot Notes
./scripts/cu-session.sh context
./scripts/cu-session.sh stop
```

## Runtime CLI fallback

```bash
./scripts/ocu-runtime.sh call list_apps
./scripts/ocu-runtime.sh call get_app_state --args '{"app":"Notes"}'
./scripts/ocu-runtime.sh call --calls '[
  {"tool":"get_app_state","args":{"app":"Notes"}},
  {"tool":"press_key","args":{"app":"Notes","key":"Return"}}
]'
```

The `scripts/bin/open-computer-use` and `scripts/bin/ocu` shims are equivalent and route through the same resolver.

## Click methods

- `accessibility`: semantic element action; preferred.
- `app_post`: background mouse event posted to a target app/window.
- `sky_click`: covered Chromium/Electron background click on macOS.
- `global`: forbidden because it moves the user’s real pointer.

# Troubleshooting

## MCP tools are missing or disconnected

```bash
./scripts/doctor.sh --repair --live
```

Then reload Cursor and verify the server is enabled in Customize → MCP.

## Runtime not found

```bash
./scripts/ocu-runtime.sh status --json
./scripts/ocu-runtime.sh install
```

Use `OPEN_COMPUTER_USE_RUNTIME_BIN=/absolute/path/to/OpenComputerUse` only for deliberate native-runtime testing.

## Permission failure

```bash
./scripts/cu-permissions.sh status
./scripts/cu-permissions.sh doctor
```

Restart Cursor after changing macOS privacy grants. Do not reset all TCC state as a first response.

## PiP not built or blank

```bash
make build-pip
./scripts/computer-use-pip.sh show Notes
```

Check `/tmp/computer-use-build.log` and `/tmp/computer-use-pip.log`. Simulator preview can use `simctl` without a separate ScreenCaptureKit preview grant.

## Click did nothing

1. Fetch a fresh app state.
2. Prefer a semantic element.
3. For a covered Chromium window, try `sky_click`.
4. For a blank area, try `app_post` with verified window-relative coordinates.
5. Never enable global-pointer fallback. Report that the app cannot be controlled safely in the background.

## Session state looks stale

```bash
./scripts/cu-session.sh stop
./scripts/cu-session.sh spawn <App>
./scripts/cu-session.sh snapshot <App>
```

Inspect `~/.cursor/computer-use/HANDOFF.md`, `SUMMARY.md`, and `/tmp/computer-use-sync.log`.

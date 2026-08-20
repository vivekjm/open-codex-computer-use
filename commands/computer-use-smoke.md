---
name: computer-use-smoke
description: Verify that Open Computer Use starts as a stdio MCP server and exposes the required desktop tools.
---

# Computer Use smoke test

Run `make smoke`. This must complete `initialize` and `tools/list` and confirm the required tool names without taking any desktop action. For a real app-discovery check, run `make live-smoke` only when local permissions are ready.

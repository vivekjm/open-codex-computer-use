#!/usr/bin/env python3
"""Start the stdio MCP server and verify initialize plus tools/list."""
from __future__ import annotations

import argparse
import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_TOOLS = {
    "list_apps",
    "get_app_state",
    "click",
    "type_text",
    "press_key",
    "set_value",
}


def send(process: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_response(
    process: subprocess.Popen[str],
    selector: selectors.BaseSelector,
    response_id: int,
    deadline: float,
    diagnostics: list[str],
) -> dict[str, Any]:
    while time.monotonic() < deadline:
        remaining = max(0.05, deadline - time.monotonic())
        for key, _ in selector.select(timeout=remaining):
            line = key.fileobj.readline()
            if not line:
                continue
            if key.data == "stderr":
                diagnostics.append(line.rstrip())
                continue
            stripped = line.strip()
            if not stripped:
                continue
            try:
                payload = json.loads(stripped)
            except json.JSONDecodeError:
                diagnostics.append(f"non-JSON stdout: {stripped}")
                continue
            if payload.get("id") == response_id:
                return payload
    detail = "\n".join(diagnostics[-20:])
    raise TimeoutError(f"timed out waiting for JSON-RPC id {response_id}\n{detail}")


def run(command: str, timeout: float) -> None:
    env = os.environ.copy()
    env.setdefault("OPEN_COMPUTER_USE_AUTO_INSTALL", "0")
    process = subprocess.Popen(
        [command],
        cwd=ROOT,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None and process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    diagnostics: list[str] = []
    deadline = time.monotonic() + timeout

    try:
        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-03-26",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "open-computer-use-smoke",
                        "version": "0.8.0",
                    },
                },
            },
        )
        initialized = read_response(process, selector, 1, deadline, diagnostics)
        if "error" in initialized:
            raise RuntimeError(f"initialize failed: {initialized['error']}")
        result = initialized.get("result") or {}
        if (result.get("serverInfo") or {}).get("name") != "open-computer-use":
            raise RuntimeError(f"unexpected serverInfo: {result.get('serverInfo')}")

        send(process, {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
        send(process, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        tools_response = read_response(process, selector, 2, deadline, diagnostics)
        if "error" in tools_response:
            raise RuntimeError(f"tools/list failed: {tools_response['error']}")
        tools = {
            item.get("name")
            for item in ((tools_response.get("result") or {}).get("tools") or [])
            if isinstance(item, dict)
        }
        missing = sorted(EXPECTED_TOOLS - tools)
        if missing:
            raise RuntimeError(f"missing expected tools: {', '.join(missing)}; got {sorted(tools)}")
        print(f"mcp_smoke_ok server=open-computer-use tools={len(tools)}")
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--command",
        default=str(ROOT / "scripts" / "launch-open-computer-use.sh"),
        help="MCP launcher executable",
    )
    parser.add_argument("--timeout", type=float, default=12.0)
    args = parser.parse_args()
    command = str(Path(args.command).expanduser().resolve())
    if not os.access(command, os.X_OK):
        parser.error(f"launcher is not executable: {command}")
    try:
        run(command, args.timeout)
    except Exception as error:  # noqa: BLE001 - CLI should print actionable diagnostics.
        print(f"mcp_smoke_failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fast, network-free verification for the Cursor Computer Use plugin."""
from __future__ import annotations

import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON = sys.executable


def run(
    args: list[str],
    *,
    env: dict[str, str] | None = None,
    stdin: str | None = None,
    timeout: float = 30,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        env=env or os.environ.copy(),
        input=stdin,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except Exception as error:  # noqa: BLE001
        raise AssertionError(f"invalid JSON in {path.relative_to(ROOT)}: {error}") from error
    require(isinstance(value, dict), f"expected object in {path.relative_to(ROOT)}")
    return value


def verify_metadata() -> None:
    manifest = load_json(ROOT / ".cursor-plugin/plugin.json")
    hooks = load_json(ROOT / "hooks/hooks.json")
    workspace_mcp = load_json(ROOT / ".cursor/mcp.json")
    plugin_mcp = load_json(ROOT / "mcp.json")

    require(manifest["hooks"] == "./hooks/hooks.json", "manifest hook path mismatch")
    require(not (ROOT / "plugin.json").exists(), "dual plugin manifests cause ambiguous loading")
    require(workspace_mcp == plugin_mcp, "workspace and plugin MCP configs have drifted")
    server = plugin_mcp["mcpServers"]["open-computer-use"]
    require(server["command"] == "./scripts/launch-open-computer-use.sh", "MCP launcher mismatch")
    require(
        server["env"]["OPEN_COMPUTER_USE_NPM_SPEC"] == "open-computer-use@0.1.51",
        "MCP runtime must be pinned",
    )

    with (ROOT / "apps/ComputerUsePiP/Info.plist").open("rb") as handle:
        plist = plistlib.load(handle)
    require(
        plist["CFBundleShortVersionString"] == manifest["version"],
        "PiP and plugin versions differ",
    )
    require(plist["LSMinimumSystemVersion"] == "14.0", "unexpected minimum macOS version")

    hook_map = hooks["hooks"]
    before_mcp = hook_map["beforeMCPExecution"][0]
    before_shell = hook_map["beforeShellExecution"][0]
    require(before_mcp.get("failClosed") is True, "MCP safety hook must fail closed")
    require(before_shell.get("failClosed") is True, "shell safety hook must fail closed")
    require("sync-context.sh" in hook_map["afterMCPExecution"][0]["command"], "context sync hook missing")
    require("target-mention.sh" in hook_map["beforeSubmitPrompt"][0]["command"], "mention hook missing")


def verify_scripts() -> None:
    shell_files = sorted(ROOT.rglob("*.sh"))
    require(shell_files, "no shell scripts found")
    unsafe_assignment = re.compile(
        r"^(?:export\s+)?OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS\s*=\s*(?:1|true)\b",
        re.IGNORECASE,
    )
    for path in shell_files:
        require(os.access(path, os.X_OK), f"script is not executable: {path.relative_to(ROOT)}")
        result = run(["bash", "-n", str(path)])
        require(result.returncode == 0, f"bash -n failed for {path}: {result.stderr}")
        for line in path.read_text(errors="ignore").splitlines():
            require(
                not unsafe_assignment.match(line.strip()),
                f"unsafe pointer fallback enabled in {path.relative_to(ROOT)}",
            )

    require(
        "scripts/ocu-runtime.sh" in (ROOT / "scripts/launch-open-computer-use.sh").read_text(),
        "launcher bypasses runtime resolver",
    )
    require(
        "scripts/bin" in (ROOT / "scripts/cu-session.sh").read_text(),
        "CLI sessions do not expose the runtime shim",
    )
    require(
        "-framework Vision" in (ROOT / "scripts/build-computer-use-pip.sh").read_text(),
        "PiP build does not link Vision",
    )
    require(
        "--exclude='.git'" in (ROOT / "scripts/install-local-plugin.sh").read_text(),
        "plugin copy includes .git",
    )

    pycache = tempfile.mkdtemp(prefix="cu-pycache-")
    env = os.environ.copy()
    env["PYTHONPYCACHEPREFIX"] = pycache
    python_files = sorted((ROOT / "scripts").rglob("*.py"))
    result = run([PYTHON, "-m", "py_compile", *map(str, python_files)], env=env)
    require(result.returncode == 0, result.stderr)


def write_fake_runtime(path: Path) -> None:
    path.write_text(
        """#!/usr/bin/env python3
import json
import sys

TOOLS = [
    'list_apps', 'get_app_state', 'click', 'perform_secondary_action',
    'scroll', 'drag', 'type_text', 'press_key', 'set_value'
]
command = sys.argv[1] if len(sys.argv) > 1 else ''
if command == 'version':
    print('open-computer-use 0.1.51-test')
elif command == 'doctor':
    print('accessibility=granted screenRecording=granted')
elif command == 'mcp':
    for line in sys.stdin:
        if not line.strip():
            continue
        request = json.loads(line)
        request_id = request.get('id')
        method = request.get('method')
        if method == 'initialize':
            result = {
                'protocolVersion': '2025-03-26',
                'serverInfo': {'name': 'open-computer-use', 'version': '0.1.51-test'},
                'capabilities': {'tools': {'listChanged': False}},
            }
        elif method == 'tools/list':
            result = {'tools': [
                {'name': name, 'description': name, 'inputSchema': {'type': 'object'}}
                for name in TOOLS
            ]}
        elif method == 'notifications/initialized':
            continue
        else:
            result = {}
        print(json.dumps({'jsonrpc': '2.0', 'id': request_id, 'result': result}), flush=True)
else:
    print(json.dumps({'argv': sys.argv[1:]}))
"""
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def verify_runtime_and_protocol() -> None:
    with tempfile.TemporaryDirectory(prefix="cu-verify-") as temp:
        temp_path = Path(temp)
        fake = temp_path / "fake-open-computer-use"
        write_fake_runtime(fake)
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(temp_path / "home"),
                "OPEN_COMPUTER_USE_RUNTIME_BIN": str(fake),
                "OPEN_COMPUTER_USE_AUTO_INSTALL": "0",
                "OPEN_COMPUTER_USE_BUS_DIR": str(temp_path / "bus"),
                "OPEN_COMPUTER_USE_STATE_LOCK": str(temp_path / "state.lock"),
                "OPEN_COMPUTER_USE_STOPPED_FILE": str(temp_path / "stopped"),
                "OPEN_COMPUTER_USE_PIP_COMMAND": str(temp_path / "pip.json"),
            }
        )

        result = run(["scripts/ocu-runtime.sh", "path"], env=env)
        require(result.returncode == 0, result.stderr)
        require(Path(result.stdout.strip()) == fake, "runtime override was not selected")

        result = run(["scripts/bin/open-computer-use", "version"], env=env)
        require(result.returncode == 0 and "0.1.51-test" in result.stdout, result.stderr)

        result = run(
            [PYTHON, "scripts/mcp-smoke.py", "--command", "scripts/launch-open-computer-use.sh", "--timeout", "5"],
            env=env,
            timeout=10,
        )
        require(result.returncode == 0, result.stderr or result.stdout)
        require("mcp_smoke_ok" in result.stdout, result.stdout)

        context_bus = ROOT / "scripts/lib/context_bus.py"
        result = run([PYTHON, str(context_bus), "selftest"], env=env)
        require(result.returncode == 0, result.stderr)

        result = run(
            [PYTHON, "scripts/cu-state-lock.py", "stop", "--", "/usr/bin/true"],
            env=env,
        )
        require(result.returncode == 0, result.stderr)
        blocked = temp_path / "should-not-exist"
        result = run(
            [
                PYTHON,
                "scripts/cu-state-lock.py",
                "unless-stopped",
                "--",
                "/usr/bin/touch",
                str(blocked),
            ],
            env=env,
        )
        require(result.returncode == 0 and not blocked.exists(), "stop lock was bypassed")


def verify_hooks() -> None:
    normal = json.dumps(
        {
            "tool_name": "user-open-computer-use-list_apps",
            "command": str(ROOT / "scripts/launch-open-computer-use.sh"),
            "tool_input": {},
        }
    )
    result = run(["bash", "hooks/prepare-computer-use.sh"], stdin=normal)
    require(result.returncode == 0, result.stderr)
    require(json.loads(result.stdout)["permission"] == "allow", result.stdout)

    unsafe = json.dumps(
        {
            "tool_name": "user-open-computer-use-click",
            "command": str(ROOT / "scripts/launch-open-computer-use.sh"),
            "tool_input": {"app": "Notes", "click_method": "global"},
        }
    )
    result = run(["bash", "hooks/prepare-computer-use.sh"], stdin=unsafe)
    require(result.returncode == 0, result.stderr)
    require(json.loads(result.stdout)["permission"] == "deny", result.stdout)

    shell_unsafe = json.dumps(
        {"command": "export OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1; open-computer-use mcp"}
    )
    result = run(["bash", "hooks/allow.sh"], stdin=shell_unsafe)
    require(result.returncode == 0, result.stderr)
    require(json.loads(result.stdout)["permission"] == "deny", result.stdout)

    shell_safe = json.dumps({"command": "./scripts/ocu-runtime.sh status"})
    result = run(["bash", "hooks/allow.sh"], stdin=shell_safe)
    require(result.returncode == 0 and json.loads(result.stdout) == {}, result.stdout)


def main() -> None:
    verify_metadata()
    verify_scripts()
    verify_runtime_and_protocol()
    verify_hooks()
    print("plugin_verify_ok")


if __name__ == "__main__":
    main()

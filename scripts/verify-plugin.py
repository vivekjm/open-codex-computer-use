#!/usr/bin/env python3
"""Fast, isolated invariants for the Cursor Computer Use plugin."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PYTHON = sys.executable


def run(args: list[str], *, env: dict[str, str], stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        env=env,
        input=stdin,
        text=True,
        capture_output=True,
        timeout=30,
        check=False,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="cu-verify-") as temp:
        temp_path = Path(temp)
        env = os.environ.copy()
        env["OPEN_COMPUTER_USE_BUS_DIR"] = str(temp_path / "bus")
        env["OPEN_COMPUTER_USE_STATE_LOCK"] = str(temp_path / "state.lock")
        env["OPEN_COMPUTER_USE_STOPPED_FILE"] = str(temp_path / "stopped")
        env["OPEN_COMPUTER_USE_PIP_COMMAND"] = str(temp_path / "pip.json")

        result = run([PYTHON, "scripts/lib/context_bus.py", "selftest"], env=env)
        assert result.returncode == 0, result.stderr

        sample = {
            "content": [{
                "type": "text",
                "text": (
                    "App=com.apple.iCal\n"
                    "0 standard window Calendar\n"
                    "12 button Today\n"
                    "The focused UI element is 12 button Today."
                ),
            }]
        }
        result = run(
            [PYTHON, "scripts/lib/context_bus.py", "ingest", "Calendar", "--action", "get_app_state"],
            env=env,
            stdin=json.dumps(sample),
        )
        assert result.returncode == 0, result.stderr
        registry = json.loads((temp_path / "bus/sessions.json").read_text())
        session = registry["sessions"][0]
        assert session["focused"]["index"] == 12
        assert session["last_action"] == "get_app_state"

        result = run(
            [PYTHON, "scripts/cu-state-lock.py", "stop", "--", "/usr/bin/true"],
            env=env,
        )
        assert result.returncode == 0
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
        assert result.returncode == 0 and not blocked.exists()

        hook_input = json.dumps({
            "tool_name": "user-open-computer-use-list_apps",
            "command": str(ROOT / "scripts/launch-open-computer-use.sh"),
            "tool_input": {},
        })
        result = run(["bash", "hooks/prepare-computer-use.sh"], env=env, stdin=hook_input)
        assert json.loads(result.stdout)["permission"] == "allow"

        hooks = json.loads((ROOT / "hooks/hooks.json").read_text())["hooks"]
        assert "prepare-computer-use.sh" in hooks["beforeMCPExecution"][0]["command"]
        assert "sync-context.sh" in hooks["afterMCPExecution"][0]["command"]
        assert "perform_secondary_action" in hooks["afterMCPExecution"][0]["matcher"]
        assert "target-mention.sh" in hooks["beforeSubmitPrompt"][0]["command"]
        assert "stop" in hooks and "sessionEnd" in hooks
        assert all(
            "CURSOR_PLUGIN_ROOT" in definition["command"]
            for definitions in hooks.values()
            for definition in definitions
        )
        for definitions in hooks.values():
            for definition in definitions:
                command_path = definition["command"].strip('"').replace("${CURSOR_PLUGIN_ROOT}", str(ROOT))
                assert Path(command_path).is_file() and os.access(command_path, os.X_OK)
        assert not (ROOT / ".cursor/hooks.json").exists(), "workspace hooks duplicate plugin hooks"

        assert not (ROOT / "plugin.json").exists(), "dual plugin manifests cause ambiguous loading"
        manifest = json.loads((ROOT / ".cursor-plugin/plugin.json").read_text())
        assert manifest["hooks"] == "./hooks/hooks.json"
        assert (ROOT / "scripts/install-local-plugin.sh").is_file()
        assert "ln -sfn" not in (ROOT / "README.md").read_text()
        plist_text = (ROOT / "apps/ComputerUsePiP/Info.plist").read_text()
        version_match = re.search(
            r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>",
            plist_text,
        )
        assert version_match and version_match.group(1) == manifest["version"]
        assert "OPEN_COMPUTER_USE_VISUAL_CURSOR=0" in (ROOT / "scripts/launch-open-computer-use.sh").read_text()

        forbidden = "OPEN_COMPUTER_USE_ALLOW_GLOBAL_POINTER_FALLBACKS=1"
        for path in ROOT.rglob("*"):
            if path.resolve() == Path(__file__).resolve():
                continue
            if path.is_file() and path.suffix in {".py", ".sh", ".json", ".swift"}:
                assert forbidden not in path.read_text(errors="ignore"), path

    print("plugin_verify_ok")


if __name__ == "__main__":
    main()

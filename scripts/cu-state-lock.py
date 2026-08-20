#!/usr/bin/env python3
"""Serialize Computer Use lifecycle writes and prevent post-cleanup resurrection."""
from __future__ import annotations

import argparse
import fcntl
import os
import subprocess
import sys
from pathlib import Path

LOCK = Path(os.environ.get("OPEN_COMPUTER_USE_STATE_LOCK", "/tmp/open-computer-use-state.lock"))
STOPPED = Path(os.environ.get("OPEN_COMPUTER_USE_STOPPED_FILE", "/tmp/open-computer-use-stopped"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("active", "unless-stopped", "stop"))
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")

    LOCK.touch(exist_ok=True)
    with LOCK.open("r+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        if args.mode == "active":
            STOPPED.unlink(missing_ok=True)
        elif args.mode == "stop":
            STOPPED.write_text(str(os.getpid()))
        elif STOPPED.exists():
            return 0
        return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())

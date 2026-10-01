#!/usr/bin/env python3
"""Tell the user when a newer agent-gov exists. Python standard library only.

  check_update.py [--force]

Run at the start of every agent session. Compares .agents/init-version with VERSION on
the agent-gov repo and prints a notice with the new changelog entries when the repo is
newer. Silent when up to date or offline (--force prints the reason instead). Changes
nothing. Opt out: set AGENT_GOV_NO_UPDATE_CHECK=1.
"""
import os
import re
import sys
import urllib.request
from pathlib import Path

LOCAL = Path(__file__).resolve().parents[2] / ".agents" / "init-version"
REMOTE = os.environ.get("AGENT_GOV_REMOTE",
                        "https://raw.githubusercontent.com/Duc42195/agent-gov/main")


def ver(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text or "")
    return tuple(map(int, m.groups())) if m else None


def fetch(name):
    with urllib.request.urlopen(f"{REMOTE}/{name}", timeout=3) as r:
        return r.read().decode("utf-8", errors="replace")


def newer_sections(changelog, current):
    parts = re.split(r"(?m)^(?=## \d+\.\d+\.\d+)", changelog)
    return [p.strip() for p in parts if p.startswith("## ") and (v := ver(p[:20])) and v > current]


def main():
    force = "--force" in sys.argv[1:]
    if os.environ.get("AGENT_GOV_NO_UPDATE_CHECK"):
        return
    current = ver(LOCAL.read_text() if LOCAL.is_file() else "")
    if current is None:
        if force:
            print("no .agents/init-version: this project was not scaffolded by agent-gov >= 0.2.0")
        return
    try:
        latest_text = fetch("VERSION")
        latest = ver(latest_text)
        changelog = fetch("CHANGELOG.md") if latest and latest > current else ""
    except Exception:
        if force:
            print("could not reach the agent-gov repo (offline?)")
        return
    if latest and latest > current:
        print(f"agent-gov {latest_text.strip()} is available (this project: {'.'.join(map(str, current))}). "
              "Tell the user in one line; do not upgrade without asking. "
              "To upgrade, run /project-init (it detects the old version).\n")
        print("\n\n".join(newer_sections(changelog, current)))
    elif force:
        print("agent-gov is up to date")


if __name__ == "__main__":
    main()

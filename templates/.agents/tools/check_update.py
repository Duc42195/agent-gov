#!/usr/bin/env python3
"""Tell the user when a newer agent-init exists. Python standard library only.

  check_update.py [--force]

Compares .agents/init-version with VERSION on the agent-init repo. Silent when up to
date, offline, or checked within the last 7 days (--force ignores the throttle and
always answers). Never changes anything. Opt out: set AGENT_INIT_NO_UPDATE_CHECK=1.
"""
import datetime
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / ".agents" / "init-version"
STAMP = ROOT / ".agents" / "state" / "update-check"
REMOTE = os.environ.get("AGENT_INIT_REMOTE",
                        "https://raw.githubusercontent.com/Duc42195/agent-init/main")
EVERY_DAYS = 7


def ver(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text or "")
    return tuple(map(int, m.groups())) if m else None


def fetch(name):
    with urllib.request.urlopen(f"{REMOTE}/{name}", timeout=3) as r:
        return r.read().decode("utf-8", errors="replace")


def newer_sections(changelog, current):
    parts = re.split(r"(?m)^(?=## \d+\.\d+\.\d+)", changelog)
    return [p.strip() for p in parts if (v := ver(p[:20])) and p.startswith("## ") and v > current]


def main():
    force = "--force" in sys.argv[1:]
    if os.environ.get("AGENT_INIT_NO_UPDATE_CHECK"):
        return
    current = ver(LOCAL.read_text() if LOCAL.is_file() else "")
    if current is None:
        if force:
            print("no .agents/init-version: this project was not scaffolded by agent-init >= 0.2.0")
        return
    if not force and STAMP.is_file():
        try:
            last = datetime.date.fromisoformat(STAMP.read_text().strip())
            if (datetime.date.today() - last).days < EVERY_DAYS:
                return
        except ValueError:
            pass
    try:
        latest_text = fetch("VERSION")
        latest = ver(latest_text)
        changelog = fetch("CHANGELOG.md") if latest and latest > current else ""
    except Exception:
        if force:
            print("could not reach the agent-init repo (offline?)")
        return
    try:
        STAMP.parent.mkdir(parents=True, exist_ok=True)
        STAMP.write_text(datetime.date.today().isoformat())
    except OSError:
        pass
    if latest and latest > current:
        cur = ".".join(map(str, current))
        print(f"agent-init {latest_text.strip()} is available (this project: {cur}). "
              f"Tell the user in one line; do not upgrade without asking. "
              f"To upgrade, run /project-init (it detects the old version).\n")
        print("\n\n".join(newer_sections(changelog, current)))
    elif force:
        print("agent-init is up to date")


if __name__ == "__main__":
    main()

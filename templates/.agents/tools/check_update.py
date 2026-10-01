"""Tell the user when a newer agent-gov exists. Python standard library only.

  check_update.py [--force]

Compares .agents/init-version with VERSION on the agent-gov repo. Silent when up to
date or offline. Asks the network at most once an hour (a failed try also waits an
hour), and repeats the same notice at most once a day, so a release is seen within
an hour of being published without nagging. --force ignores both limits and always
answers. Never changes anything but its own state file. Opt out: set
AGENT_GOV_NO_UPDATE_CHECK=1.
"""
import datetime
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL = ROOT / ".agents" / "init-version"
STATE = ROOT / ".agents" / "state" / "update-check.json"
REMOTE = os.environ.get("AGENT_GOV_REMOTE",
                        "https://raw.githubusercontent.com/Duc42195/agent-gov/main")
RECHECK = datetime.timedelta(hours=1)
REPEAT = datetime.timedelta(hours=24)


def ver(text):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", text or "")
    return tuple(map(int, m.groups())) if m else None


def fetch(name):
    with urllib.request.urlopen(f"{REMOTE}/{name}", timeout=3) as r:
        return r.read().decode("utf-8", errors="replace")


def newer_sections(changelog, current):
    parts = re.split(r"(?m)^(?=## \d+\.\d+\.\d+)", changelog)
    return [p.strip() for p in parts if p.startswith("## ") and (v := ver(p[:20])) and v > current]


def load():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save(state):
    try:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(state))
    except OSError:
        pass


def ago(state, key, now):
    try:
        return now - datetime.datetime.fromisoformat(state[key])
    except (KeyError, ValueError, TypeError):
        return None


def main():
    force = "--force" in sys.argv[1:]
    if os.environ.get("AGENT_GOV_NO_UPDATE_CHECK"):
        return
    current = ver(LOCAL.read_text() if LOCAL.is_file() else "")
    if current is None:
        if force:
            print("no .agents/init-version: this project was not scaffolded by agent-gov >= 0.2.0")
        return
    now = datetime.datetime.now()
    state = load()
    since = ago(state, "tried", now)
    if not force and since is not None and since < RECHECK:
        return
    state["tried"] = now.isoformat(timespec="seconds")
    try:
        latest_text = fetch("VERSION")
        latest = ver(latest_text)
        changelog = fetch("CHANGELOG.md") if latest and latest > current else ""
    except Exception:
        save(state)
        if force:
            print("could not reach the agent-gov repo (offline?)")
        return
    if latest and latest > current:
        shown = ago(state, "announced_at", now)
        repeat = state.get("announced") == latest_text.strip() and shown is not None and shown < REPEAT
        if force or not repeat:
            state["announced"], state["announced_at"] = latest_text.strip(), now.isoformat(timespec="seconds")
            cur = ".".join(map(str, current))
            print(f"agent-gov {latest_text.strip()} is available (this project: {cur}). "
                  f"Tell the user in one line; do not upgrade without asking. "
                  f"To upgrade, run /project-init (it detects the old version).\n")
            print("\n\n".join(newer_sections(changelog, current)))
    elif force:
        print("agent-gov is up to date")
    save(state)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Sync .agents/plan.csv with an external tracker.

plan.csv is the source of truth. `push` sends it out; `pull` brings external
changes in. On conflict, plan.csv wins. Keep credentials in environment
variables or .agents/state/ (git-ignored), never in this file.

  sync_plan.py push
  sync_plan.py pull
"""
import sys

import plan  # same folder

BACKEND = "{{EXTERNAL_TRACKER}}"  # none | jira | gsheet | excel

# plan.csv status -> the tracker's status name. Edit to match its workflow.
STATUS_MAP = {"todo": "To Do", "in-progress": "In Progress", "done": "Done"}


def not_ready(name):
    sys.exit(f"{name} adapter is not implemented yet: fill in the TODO in sync_plan.py")


def push_none(rows):
    print("no external tracker configured; plan.csv is the only record")


def pull_none():
    print("no external tracker configured; nothing to pull")


def push_jira(rows):
    # TODO env JIRA_URL, JIRA_TOKEN. For each row whose id is a Jira issue key:
    #   GET  {JIRA_URL}/rest/api/2/issue/{key}/transitions   -> find id of STATUS_MAP[row["status"]]
    #   POST the same URL with {"transition": {"id": "<id>"}}
    not_ready("jira")


def pull_jira():
    # TODO read issue status back, map with the reverse of STATUS_MAP, update rows, plan.save(rows)
    not_ready("jira")


def push_gsheet(rows):
    # TODO credentials file path in env GOOGLE_APPLICATION_CREDENTIALS; sheet id in .agents/state/sync.json
    #   write the plan.csv columns to the sheet (e.g. with gspread or the Sheets API)
    not_ready("gsheet")


def pull_gsheet():
    not_ready("gsheet")


def push_excel(rows):
    # TODO workbook path in .agents/state/sync.json; write plan.csv columns with openpyxl
    not_ready("excel")


def pull_excel():
    not_ready("excel")


PUSH = {"none": push_none, "jira": push_jira, "gsheet": push_gsheet, "excel": push_excel}
PULL = {"none": pull_none, "jira": pull_jira, "gsheet": pull_gsheet, "excel": pull_excel}


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("push", "pull"):
        sys.exit(__doc__)
    if BACKEND not in PUSH:
        sys.exit(f"unknown BACKEND {BACKEND!r}")
    if sys.argv[1] == "push":
        PUSH[BACKEND](plan.load())
    else:
        PULL[BACKEND]()


if __name__ == "__main__":
    main()

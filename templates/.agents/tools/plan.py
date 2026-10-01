#!/usr/bin/env python3
"""Read and update plan.csv. Python standard library only.

  plan.py list [--owner NAME] [--status STATUS]
  plan.py add ID "Title" [--owner NAME]
  plan.py set-status ID todo|in-progress|done [--mr URL]
  plan.py set-review ID pending|approved|changes [--reviewer NAME]
  plan.py set-deps ID [--depends "ID;ID"] [--adr "NNNN;NNNN"]
"""
import argparse
import csv
import datetime
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # <root>/.agents/tools/plan.py
PLAN = ROOT / "plan.csv"
BACKUP = ROOT / ".agents" / "plan.csv.bak"
COLS = ["id", "title", "owner", "status", "estimate", "start", "end",
        "dod", "mr", "reviewer", "review", "updated", "depends", "adr", "notes"]
STATUS = ("todo", "in-progress", "done")
REVIEW = ("pending", "approved", "changes")


def today():
    return datetime.date.today().isoformat()


def load():
    if not PLAN.exists():
        sys.exit(f"{PLAN} not found")
    with PLAN.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, restval=""))


def save(rows):
    shutil.copy2(PLAN, BACKUP)
    with PLAN.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLS, extrasaction="ignore", restval="")
        writer.writeheader()
        writer.writerows(rows)


def find(rows, task_id):
    for row in rows:
        if row["id"] == task_id:
            return row
    sys.exit(f"unknown task id: {task_id}")


def cmd_list(args):
    rows = load()
    now = today()
    for r in rows:
        if args.owner and r["owner"] != args.owner:
            continue
        if args.status and r["status"] != args.status:
            continue
        late = " LATE" if r["end"] and r["end"] < now and r["status"] != "done" else ""
        print(f'{r["id"]:<10} {r["status"]:<12} {r["owner"]:<12} '
              f'{r["review"]:<9} {r["end"]:<10} {r["title"]}{late}')
    done = sum(1 for r in rows if r["status"] == "done")
    pct = f" ({100 * done // len(rows)}%)" if rows else ""
    print(f"\n{done}/{len(rows)} done{pct}")


def cmd_add(args):
    rows = load()
    if any(r["id"] == args.id for r in rows):
        sys.exit(f"task id already exists: {args.id}")
    row = {c: "" for c in COLS}
    row.update(id=args.id, title=args.title, owner=args.owner, status="todo", updated=today())
    rows.append(row)
    save(rows)


def cmd_set_status(args):
    rows = load()
    row = find(rows, args.id)
    row["status"] = args.status
    if args.mr:
        row["mr"] = args.mr
    if args.status == "done" and not row["review"]:
        row["review"] = "pending"
    row["updated"] = today()
    save(rows)


def cmd_set_review(args):
    rows = load()
    row = find(rows, args.id)
    row["review"] = args.review
    if args.reviewer:
        row["reviewer"] = args.reviewer
    row["updated"] = today()
    save(rows)


def cmd_set_deps(args):
    rows = load()
    row = find(rows, args.id)
    if args.depends is not None:
        known = {r["id"] for r in rows}
        unknown = [d.strip() for d in args.depends.replace(",", ";").split(";")
                   if d.strip() and d.strip() not in known]
        if unknown:
            sys.exit(f"unknown task id in --depends: {', '.join(unknown)}")
        row["depends"] = args.depends
    if args.adr is not None:
        row["adr"] = args.adr
    row["updated"] = today()
    save(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list")
    p.add_argument("--owner")
    p.add_argument("--status", choices=STATUS)
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("add")
    p.add_argument("id")
    p.add_argument("title")
    p.add_argument("--owner", default="")
    p.set_defaults(fn=cmd_add)

    p = sub.add_parser("set-status")
    p.add_argument("id")
    p.add_argument("status", choices=STATUS)
    p.add_argument("--mr", default="")
    p.set_defaults(fn=cmd_set_status)

    p = sub.add_parser("set-review")
    p.add_argument("id")
    p.add_argument("review", choices=REVIEW)
    p.add_argument("--reviewer", default="")
    p.set_defaults(fn=cmd_set_review)

    p = sub.add_parser("set-deps")
    p.add_argument("id")
    p.add_argument("--depends")
    p.add_argument("--adr")
    p.set_defaults(fn=cmd_set_deps)

    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

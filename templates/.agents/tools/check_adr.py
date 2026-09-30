#!/usr/bin/env python3
"""Check ADR integrity. Python standard library only.

  check_adr.py [--reports PATH ...]

Checks: unique numbers, every ADR has a status, superseded-by points at a real
ADR, one accepted ADR per topic, index in adr/README.md matches the files, and
(with --reports) every run-id cited in reports equals an accepted result ADR.
Exit code 1 if anything is wrong.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ADR_DIR = Path(__file__).resolve().parent.parent / "adr"
NAME = re.compile(r"^(\d{4})-.+\.md$")
INDEX_ROW = re.compile(r"^\|\s*(\d{4})\s*\|(.+)\|(.+)\|\s*$", re.M)
CITED_RUN = re.compile(r"(?<![\w-])run[-_]?id:\s*`?([\w.\-]+)", re.I)
REPORT_SUFFIX = {".md", ".tex", ".txt", ".rst"}


def field(name):
    return re.compile(rf"^-[ \t]*{name}:[ \t]*(.+?)[ \t]*$", re.I | re.M)


STATUS, TOPIC, RUN_ID = field("Status"), field("Topic"), field("Run-id")


def first(pattern, text):
    m = pattern.search(text)
    return m.group(1) if m else None


def load_adrs():
    adrs = []
    for path in sorted(ADR_DIR.glob("*.md")):
        m = NAME.match(path.name)
        if not m or m.group(1) == "0000":
            continue
        text = path.read_text(encoding="utf-8")
        status = first(STATUS, text)
        adrs.append({
            "number": m.group(1),
            "file": path.name,
            "status": status.lower() if status else None,
            "topic": first(TOPIC, text),
            "run_id": first(RUN_ID, text),
        })
    return adrs


def check_structure(adrs):
    problems = []
    by_number = defaultdict(list)
    for a in adrs:
        by_number[a["number"]].append(a["file"])
    for number, files in by_number.items():
        if len(files) > 1:
            problems.append(f"duplicate ADR number {number}: {', '.join(files)}")

    by_topic = defaultdict(list)
    for a in adrs:
        status = a["status"]
        if status is None:
            problems.append(f'{a["file"]}: missing "- Status:" line')
            continue
        if status.startswith("superseded"):
            ref = re.search(r"superseded-by\s+(\d{4})", status)
            if not ref:
                problems.append(f'{a["file"]}: status must read "superseded-by NNNN"')
            elif ref.group(1) not in by_number:
                problems.append(f'{a["file"]}: superseded-by {ref.group(1)} does not exist')
        elif status.startswith("accepted"):
            if not a["topic"]:
                problems.append(f'{a["file"]}: accepted ADR needs a "- Topic:" line')
            else:
                by_topic[a["topic"].lower()].append(a["file"])
    for topic, files in by_topic.items():
        if len(files) > 1:
            problems.append(f'topic "{topic}" has {len(files)} accepted ADRs: {", ".join(files)}')
    return problems


def check_index(adrs):
    readme = ADR_DIR / "README.md"
    if not readme.exists():
        return ["adr/README.md is missing"]
    indexed = {m.group(1): m.group(3).strip().lower()
               for m in INDEX_ROW.finditer(readme.read_text(encoding="utf-8"))}
    problems = []
    for a in adrs:
        if a["number"] not in indexed:
            problems.append(f'{a["file"]}: not listed in the adr/README.md index')
        elif a["status"] and indexed[a["number"]] != a["status"]:
            problems.append(f'{a["file"]}: index says "{indexed[a["number"]]}", file says "{a["status"]}"')
    known = {a["number"] for a in adrs}
    for number in indexed:
        if number not in known:
            problems.append(f"index lists {number} but no such ADR file exists")
    return problems


def check_reports(adrs, paths):
    accepted = {a["run_id"] for a in adrs
                if a["run_id"] and a["status"] and a["status"].startswith("accepted")}
    files = []
    for p in map(Path, paths):
        if not p.exists():
            return [f"report path not found: {p}"]
        files += [p] if p.is_file() else [f for f in sorted(p.rglob("*"))
                                           if f.is_file() and f.suffix in REPORT_SUFFIX]
    problems = []
    for f in files:
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            for run in CITED_RUN.findall(line):
                if run not in accepted:
                    problems.append(
                        f"{f}:{n}: run-id {run} is not an accepted result ADR "
                        f"(accepted: {', '.join(sorted(accepted)) or 'none'}). "
                        f"Regenerate from the accepted run, or cite it as superseded-run-id.")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--reports", nargs="*", default=[],
                        help="files or folders with tables/numbers/figures to check")
    args = parser.parse_args()

    adrs = load_adrs()
    problems = check_structure(adrs) + check_index(adrs)
    if args.reports:
        problems += check_reports(adrs, args.reports)
    for p in problems:
        print("FAIL", p)
    if problems:
        sys.exit(1)
    print(f"OK ({len(adrs)} ADRs)")


if __name__ == "__main__":
    main()

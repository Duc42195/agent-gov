#!/usr/bin/env python3
"""Score how well /project-init scaffolded a project. Python standard library only.

  score_init.py [PROJECT_DIR] [--agent NAME] [--model NAME] [--write]

Checks the result objectively (files, placeholders, tools run, profile filled).
--write saves a paste-ready report to PROJECT_DIR/.agents/state/init-report.md with an
empty self-report section for the agent to fill. Exit code 1 if any check fails.
"""
import argparse
import csv
import re
import subprocess
import sys
from pathlib import Path

REQUIRED = [
    "AGENTS.md", "CLAUDE.md", ".agents/roles.md", "plan.csv",
    ".agents/adr/README.md", ".agents/adr/0000-template.md",
    ".agents/wiki/decisions-log.md", ".agents/wiki/learnings.md",
    ".agents/wiki/open-questions.md", ".agents/wiki/working-process.md",
    ".agents/tools/plan.py", ".agents/tools/check_adr.py", ".agents/tools/sync_plan.py",
]
DONE_CMDS = [".claude/commands/done.md", ".cursor/commands/done.md",
             ".github/prompts/done.prompt.md"]
HEADER = "id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,notes"
GITIGNORE = [".agents/state/", ".agents/*.bak", "__pycache__/"]


def read(root, rel):
    p = root / rel
    return p.read_text(encoding="utf-8", errors="replace") if p.is_file() else ""


def run(root, *cmd):
    r = subprocess.run([sys.executable, *cmd], cwd=root, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


def checks(root):
    out = []

    def add(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    missing = [f for f in REQUIRED if not (root / f).is_file()]
    add("required files exist", not missing, "missing: " + ", ".join(missing))

    left = []
    for d in ("AGENTS.md", ".agents", ".claude", ".cursor", ".github"):
        p = root / d
        for f in ([p] if p.is_file() else sorted(p.rglob("*")) if p.exists() else []):
            if f.is_file() and f.suffix in {".md", ".py", ".csv", ".toml"} and "{{" in read(root, f.relative_to(root)):
                left.append(str(f.relative_to(root)))
    add("no {{placeholder}} left", not left, ", ".join(left))

    add("CLAUDE.md is one line '@AGENTS.md'", read(root, "CLAUDE.md").strip() == "@AGENTS.md")

    agents = read(root, "AGENTS.md")
    add("AGENTS.md profile filled", agents and "<one line>" not in agents and "<stack" not in agents,
        "'<one line>' or '<stack' still present")
    add("AGENTS.md short (<= 80 lines)", 0 < len(agents.splitlines()) <= 80,
        f"{len(agents.splitlines())} lines")
    research = re.search(r"Research project:\s*(\w+)", agents)
    if research and research.group(1).lower() == "no":
        add("non-research: Results rule removed", "Run of record" not in agents)

    plan = read(root, "plan.csv")
    rows = list(csv.DictReader(plan.splitlines())) if plan else []
    add("plan.csv header exact", plan.splitlines()[:1] == [HEADER])
    add("plan.csv has >= 1 task", len(rows) >= 1)

    add("roles.md filled", "<name>" not in read(root, ".agents/roles.md") and (root / ".agents/roles.md").is_file())

    gi = read(root, ".gitignore").splitlines()
    add(".gitignore has agent lines", all(l in gi for l in GITIGNORE),
        "missing: " + ", ".join(l for l in GITIGNORE if l not in gi))

    if (root / ".agents/tools/check_adr.py").is_file():
        code, msg = run(root, ".agents/tools/check_adr.py")
        add("check_adr.py prints OK", code == 0 and msg.startswith("OK"), msg)
    if (root / ".agents/tools/plan.py").is_file():
        code, msg = run(root, ".agents/tools/plan.py", "list")
        add("plan.py list works", code == 0, msg)

    tracker = re.search(r"External tracker:\s*(\w+)", agents)
    backend = re.search(r'BACKEND = "(\w+)"', read(root, ".agents/tools/sync_plan.py"))
    add("sync_plan BACKEND matches AGENTS.md tracker",
        bool(tracker and backend and tracker.group(1).lower() == backend.group(1).lower()),
        f"AGENTS.md={tracker and tracker.group(1)} sync_plan={backend and backend.group(1)}")

    add("a /done command exists", any((root / c).is_file() for c in DONE_CMDS))
    return out


REPORT = """# init report

- agent: {agent}
- model: {model}
- project type: {ptype}
- score: {passed}/{total}

## Objective checks
{table}

## Self-report (the agent fills this in; keep it short, no project secrets or private content)
- Steps of init.md I could not follow as written, and why:
- Places where init.md was ambiguous or contradicted itself:
- Files I had to change beyond the templates (list) and why:
- Questions I asked the user (count) and any I could have answered from the repo:
- Errors hit and how they were fixed:
- Existing files I merged into instead of creating (list):
- One change to init.md or templates that would have saved the most effort:
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("project", nargs="?", default=".")
    ap.add_argument("--agent", default="unknown")
    ap.add_argument("--model", default="unknown")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    root = Path(args.project).resolve()
    res = checks(root)
    passed = sum(1 for _, ok, _ in res if ok)
    table = "\n".join(f"- [{'x' if ok else ' '}] {n}" + (f" — {d}" if d and not ok else "")
                      for n, ok, d in res)
    print(table)
    print(f"\nscore {passed}/{len(res)}")
    if args.write:
        agents = read(root, "AGENTS.md")
        r = re.search(r"Research project:\s*(\w+)", agents)
        dest = root / ".agents/state/init-report.md"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(REPORT.format(
            agent=args.agent, model=args.model, ptype="research" if r and r.group(1).lower() == "yes" else "other",
            passed=passed, total=len(res), table=table), encoding="utf-8")
        print(f"report written: {dest}")
    sys.exit(0 if passed == len(res) else 1)


if __name__ == "__main__":
    main()

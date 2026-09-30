#!/usr/bin/env python3
"""Smoke test: scaffold templates into an empty dir the way init.md says, then run the checks.

  python tests/smoke_test.py
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "templates"
VALUES = {
    "PROJECT_NAME": "demo", "IS_RESEARCH": "yes", "TASK_KEY": "DEMO",
    "GIT_HOST": "GitHub", "DEFAULT_BRANCH": "main",
    "EXTERNAL_TRACKER": "none", "GATE_CMD": "python -m pytest",
}


def run(cwd, *cmd):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def scaffold(dest):
    for src in TEMPLATES.rglob("*"):
        if src.is_dir() or src.name in ("pointer.md", "gitignore.append"):
            continue
        out = dest / src.relative_to(TEMPLATES)
        out.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text(encoding="utf-8")
        for k, v in VALUES.items():
            text = text.replace("{{%s}}" % k, v)
        out.write_text(text, encoding="utf-8")


def main():
    failures = []
    tmp = Path(tempfile.mkdtemp())
    try:
        scaffold(tmp)

        left = [str(p.relative_to(tmp)) for p in tmp.rglob("*")
                if p.is_file() and "{{" in p.read_text(encoding="utf-8")]
        if left:
            failures.append(f"placeholders left in: {left}")

        code, out = run(tmp, sys.executable, ".agents/tools/check_adr.py")
        if code or "OK" not in out:
            failures.append(f"check_adr on empty ADR set: {out}")

        code, out = run(tmp, sys.executable, ".agents/tools/plan.py", "list")
        if code or "DEMO-1" not in out:
            failures.append(f"plan list: {out}")

        for args, expect in [
            (("set-status", "DEMO-1", "in-progress"), "in-progress"),
            (("set-status", "DEMO-1", "done", "--mr", "http://x/1"), "pending"),
            (("set-review", "DEMO-1", "approved", "--reviewer", "bob"), "approved"),
        ]:
            code, out = run(tmp, sys.executable, ".agents/tools/plan.py", *args)
            _, lst = run(tmp, sys.executable, ".agents/tools/plan.py", "list")
            if code or expect not in lst:
                failures.append(f"plan {args}: {out}{lst}")

        code, out = run(tmp, sys.executable, ".agents/tools/sync_plan.py", "push")
        if code:
            failures.append(f"sync_plan push (none): {out}")

        # ADR rules: two accepted ADRs on one topic must fail; a run-id check must catch stale numbers.
        adr = tmp / ".agents/adr"
        tpl = (adr / "0000-template.md").read_text()
        for n, topic in (("0001", "t"), ("0002", "t")):
            (adr / f"{n}-x.md").write_text(
                tpl.replace("NNNN", n).replace("proposed", "accepted").replace("topic-slug", topic))
        code, out = run(tmp, sys.executable, ".agents/tools/check_adr.py")
        if code == 0 or "topic" not in out:
            failures.append(f"duplicate topic not detected: {out}")
        (adr / "0002-x.md").write_text(
            (adr / "0002-x.md").read_text().replace("accepted", "superseded-by 0001", 1))
        idx = adr / "README.md"
        idx.write_text(idx.read_text().rstrip("\n") +
                       "\n| 0001 | x | accepted |\n| 0002 | x | superseded-by 0001 |\n")
        code, out = run(tmp, sys.executable, ".agents/tools/check_adr.py")
        if code:
            failures.append(f"valid supersede flagged: {out}")

        (tmp / "rep.md").write_text("Table (run-id: r9)\n")
        code, out = run(tmp, sys.executable, ".agents/tools/check_adr.py", "--reports", "rep.md")
        if code == 0:
            failures.append("stale run-id in report not detected")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # init.md must reference only templates that exist.
    init = (ROOT / "init.md").read_text()
    for path in re.findall(r"\| `((?:\.|[A-Za-z])[^`|]*)` \| ", init):
        p = path.rstrip("/*")
        if p.startswith("templates"):
            continue
        if not any(TEMPLATES.glob(p + "*")) and not (TEMPLATES / p).exists():
            failures.append(f"init.md references missing template: {path}")

    for f in failures:
        print("FAIL", f)
    if failures:
        sys.exit(1)
    print("OK smoke test")


if __name__ == "__main__":
    main()

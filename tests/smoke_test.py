#!/usr/bin/env python3
"""Smoke test: scaffold templates into an empty dir the way init.md says, then run the checks.

  python tests/smoke_test.py
"""
import os
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
    (dest / ".agents/init-version").write_text((ROOT / "VERSION").read_text())


def main():
    failures = []
    tmp = Path(tempfile.mkdtemp())
    try:
        scaffold(tmp)

        left = [str(p.relative_to(tmp)) for p in tmp.rglob("*")
                if p.is_file() and "{{" in p.read_text(encoding="utf-8")]
        if left:
            failures.append(f"placeholders left in: {left}")

        # what the agent fills in by hand
        for c in (".claude/commands/plan-check.md", ".cursor/commands/plan-check.md", ".github/prompts/plan-check.prompt.md"):
            f = tmp / c
            f.write_text(f.read_text().replace("<!-- PROJECT-CHECKS -->", "- gate passes"))
        a = tmp / "AGENTS.md"
        a.write_text(a.read_text().replace("<one line>", "x").replace('<stack, or "docs only">', "x"))
        r = tmp / ".agents/roles.md"
        r.write_text(r.read_text().replace("<name>", "me").replace("<role>", "maintainer"))
        (tmp / ".gitignore").write_text((TEMPLATES / "gitignore.append").read_text())
        scorer = str(ROOT / "tools" / "score_init.py")
        code, out = run(tmp, sys.executable, scorer, ".", "--agent", "t", "--write")
        if code or not (tmp / ".agents/state/init-report.md").is_file():
            failures.append(f"score_init on a good scaffold: {out}")
        empty = Path(tempfile.mkdtemp())
        code, out = run(empty, sys.executable, scorer, ".")
        shutil.rmtree(empty, ignore_errors=True)
        if code == 0:
            failures.append("score_init passed on an empty dir")

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

        # plan.csv deps, plan-check on a real git repo
        code, out = run(tmp, sys.executable, ".agents/tools/plan.py", "set-deps", "DEMO-1", "--depends", "NOPE-9")
        if code == 0:
            failures.append("set-deps accepted an unknown id")
        code, out = run(tmp, sys.executable, ".agents/tools/plan.py", "set-deps", "DEMO-1", "--depends", "DEMO-1", "--adr", "0003")
        if code or "0003" not in (tmp / "plan.csv").read_text():
            failures.append(f"set-deps: {out}")
        pc = tmp / "plan.csv"
        pc.write_text("id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,depends,adr,notes\n"
                      "DEMO-1,t,me,in-progress,1d,2020-01-01,2020-01-02,d,,,,,,,\n")
        for g in (("init", "-q", "-b", "main"), ("add", "-A"), ("commit", "-qm", "init")):
            subprocess.run(["git", *g], cwd=tmp, capture_output=True,
                           env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                                    GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
        code, out = run(tmp, sys.executable, ".agents/plan-check/plan_check.py", "--no-fetch", "--date", "2026-01-01")
        if code or "| ID |" not in out or "BEHIND" not in out:
            failures.append(f"plan_check late task: {out}")
        code, out = run(tmp, sys.executable, ".agents/plan-check/plan_check.py", "--no-fetch", "--lang", "vi")
        if code or "| ID |" not in out:
            failures.append(f"plan_check vi: {out}")
        # an unfilled marker must be noticed by the scorer
        f = tmp / ".claude/commands/plan-check.md"
        good = f.read_text()
        f.write_text(good + "\n<!-- PROJECT-CHECKS -->\n")
        code, out = run(tmp, sys.executable, scorer, ".")
        if code == 0 or "Project checks filled" not in out or "[ ] plan-check Project checks" not in out:
            failures.append(f"scorer missed the unfilled PROJECT-CHECKS marker: {out}")
        f.write_text(good)
        code, out = run(tmp, sys.executable, scorer, ".")
        if code:
            failures.append(f"scorer on a filled plan-check: {out}")

        # update check runs every session: no throttle, no state file; silent when current or offline
        remote = Path(tempfile.mkdtemp())
        (remote / "VERSION").write_text("9.9.9\n")
        (remote / "CHANGELOG.md").write_text("# c\n\n## 9.9.9 — 2030-01-01\n- Upgrade: do x\n\n## 0.0.1 — old\n- y\n")
        env = dict(os.environ, AGENT_GOV_REMOTE=remote.as_uri())
        chk = [sys.executable, ".agents/tools/check_update.py"]

        def check(*extra):
            return subprocess.run(chk + list(extra), cwd=tmp, capture_output=True, text=True, env=env)

        for n in (1, 2, 3):  # every call prints while a newer version exists
            r = check()
            if "9.9.9" not in r.stdout or "do x" not in r.stdout or "0.0.1" in r.stdout:
                failures.append(f"check_update call {n} with a newer remote: {r.stdout}{r.stderr}")
        (remote / "VERSION").write_text((ROOT / "VERSION").read_text())
        if check().stdout:
            failures.append("check_update spoke while up to date")
        if "up to date" not in check("--force").stdout:
            failures.append("check_update --force did not say up to date")
        env["AGENT_GOV_REMOTE"] = "file:///nonexistent"
        r = check()
        if r.returncode or r.stdout:
            failures.append("check_update offline not silent")
        if "offline" not in check("--force").stdout:
            failures.append("check_update --force did not explain being offline")
        env["AGENT_GOV_NO_UPDATE_CHECK"] = "1"
        env["AGENT_GOV_REMOTE"] = remote.as_uri()
        (remote / "VERSION").write_text("9.9.9\n")
        if check("--force").stdout:
            failures.append("AGENT_GOV_NO_UPDATE_CHECK not honoured")
        if list((tmp / ".agents/state").glob("update-check*")):
            failures.append("check_update left a state file")
        shutil.rmtree(remote, ignore_errors=True)

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

    # release hygiene: VERSION equals the newest CHANGELOG heading
    top = re.search(r"(?m)^## (\d+\.\d+\.\d+)", (ROOT / "CHANGELOG.md").read_text())
    if not top or top.group(1) != (ROOT / "VERSION").read_text().strip():
        failures.append("VERSION does not match the top CHANGELOG entry")

    # install.sh --update against a throwaway clone
    base = Path(tempfile.mkdtemp())
    def git(*a, cwd):
        return subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True,
                              env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
                                       GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
    up = base / "up"; shutil.copytree(ROOT, up, ignore=shutil.ignore_patterns(".git", "__pycache__"))
    git("init", "-q", "-b", "main", cwd=up); git("add", "-A", cwd=up); git("commit", "-qm", "v", cwd=up)
    clone = base / "clone"; git("clone", "-q", str(up), str(clone), cwd=base)
    r = subprocess.run(["bash", str(clone / "install.sh"), "--update"], capture_output=True, text=True)
    if "up to date" not in r.stdout:
        failures.append(f"install --update when current: {r.stdout}{r.stderr}")
    (up / "VERSION").write_text("9.0.0\n")
    (up / "CHANGELOG.md").write_text("# c\n\n## 9.0.0 — d\n- new thing\n" + (up / "CHANGELOG.md").read_text().split("\n", 1)[1])
    git("commit", "-qam", "next", cwd=up)
    r = subprocess.run(["bash", str(clone / "install.sh"), "--update"], capture_output=True, text=True)
    if "9.0.0" not in r.stdout or "new thing" not in r.stdout:
        failures.append(f"install --update when behind: {r.stdout}{r.stderr}")
    shutil.rmtree(base, ignore_errors=True)

    # delete-session: compiles; installed by a user-wide claude install only; keeps settings; idempotent
    src = ROOT / "tools/claude-delete-session"
    compile(src.read_text(encoding="utf-8"), str(src), "exec")
    import json

    def install(home, *args, cwd=None):
        return subprocess.run(["bash", str(ROOT / "install.sh"), *args], capture_output=True, text=True,
                              cwd=cwd, env=dict(os.environ, HOME=str(home)))

    home = Path(tempfile.mkdtemp())
    (home / ".claude").mkdir()
    (home / ".claude/settings.json").write_text('{"model": "x", "permissions": {"allow": ["Bash(ls)"]}}')
    for _ in range(2):
        r = install(home, "--agent", "claude")
    cfg = json.loads((home / ".claude/settings.json").read_text())
    rule = "Bash(~/.local/bin/claude-delete-session)"
    if r.returncode or not (home / ".local/bin/claude-delete-session").is_file():
        failures.append(f"install --agent claude did not install delete-session: {r.stdout}{r.stderr}")
    if cfg.get("model") != "x" or cfg["permissions"]["allow"] != ["Bash(ls)", rule]:
        failures.append(f"settings.json not preserved or rule duplicated: {cfg}")
    for args, why in ((("--agent", "cursor"), "cursor"), (("--agent", "claude", "--project"), "claude --project")):
        other = Path(tempfile.mkdtemp())
        r = install(other, *args, cwd=other)
        if r.returncode or (other / ".local").exists():
            failures.append(f"install {why} must not install delete-session: {r.stdout}{r.stderr}")
        shutil.rmtree(other, ignore_errors=True)
    r = install(home, "--with", "delete-session")
    if r.returncode != 2:
        failures.append("the removed --with option was accepted")
    shutil.rmtree(home, ignore_errors=True)

    # no leftovers of the old name outside the changelog
    for f in list(ROOT.rglob("*")):
        if f.is_file() and ".git" not in f.parts and "__pycache__" not in f.parts and f.name not in ("CHANGELOG.md", "smoke_test.py"):
            try:
                txt = f.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            if re.search(r"agent-init|AGENT_INIT", txt):
                failures.append(f"old name agent-init left in {f.relative_to(ROOT)}")

    # init.md must reference only templates that exist.
    init = (ROOT / "init.md").read_text()
    for path in re.findall(r"(?m)^\| `((?:\.|[A-Za-z])[^`|]*)` \| ", init):
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

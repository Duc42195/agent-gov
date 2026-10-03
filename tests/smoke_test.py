#!/usr/bin/env python3
"""Smoke test for agent-gov: installer, gov.sh (scaffold + upgrade), plan.sh, score.sh, plan_check.py,
claude-delete-session and the Windows scripts (statically; for real if pwsh exists).

  python3 tests/smoke_test.py

Everything runs on a throwaway COPY of the repo and a fake HOME, so your own ~/.agent-gov/.env and
~/.claude are never touched. Python here is only the test runner; the tools under test are bash.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAILURES = []
TMP = Path(tempfile.mkdtemp(prefix="agent-gov-test-"))
GIT_ENV = dict(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def fail(msg):
    FAILURES.append(msg)


def run(cmd, cwd=None, env=None, check_rc=None):
    e = dict(os.environ, **(env or {}))
    r = subprocess.run(cmd, cwd=cwd, env=e, capture_output=True, text=True)
    if check_rc is not None and r.returncode != check_rc:
        fail(f"{' '.join(map(str, cmd))[:90]}: exit {r.returncode}, wanted {check_rc}: {(r.stdout + r.stderr)[-300:]}")
    return r


def sh(script, *args, cwd=None, env=None, rc=None):
    return run(["bash", str(script), *map(str, args)], cwd=cwd, env=env, check_rc=rc)


def mkdir(name):
    d = TMP / f"{name}-{len(list(TMP.iterdir()))}"
    d.mkdir(parents=True)
    return d


def repo_copy():
    """A working copy of this repo (with .git, so release tags are there) that tests may modify."""
    dst = mkdir("repo") / "agent-gov"
    shutil.copytree(ROOT, dst, ignore=shutil.ignore_patterns("__pycache__", ".env"))
    return dst


def tree(path):
    out = []
    for p in sorted(Path(path).rglob("*")):
        if p.is_file():
            out.append((str(p.relative_to(path)), p.stat().st_size, p.read_bytes()))
    return out


def has(text, *needles):
    return all(n in text for n in needles)


# --------------------------------------------------------------------------- installer
def test_installer():
    gov = repo_copy()
    inst = gov / "install.sh"
    home = mkdir("home")
    (home / ".claude").mkdir()
    settings = home / ".claude/settings.json"
    settings.write_text('{"model": "x", "permissions": {"allow": ["Bash(ls)"]}}')
    proj = mkdir("proj")
    jq = shutil.which("jq")

    # user-wide: writes under HOME only, never in the project
    before = tree(proj)
    for _ in range(2):  # twice: idempotent
        r = sh(inst, "--agent", "claude,cursor,gemini,opencode,codex,copilot", cwd=proj, env={"HOME": home}, rc=0)
    expect = {
        ".claude/commands/project-init.md": "claude", ".cursor/commands/project-init.md": "cursor",
        ".gemini/commands/project-init.toml": "gemini", ".config/opencode/commands/project-init.md": "opencode",
        ".codex/prompts/project-init.md": "codex",
    }
    for rel, name in expect.items():
        f = home / rel
        if not f.is_file() or "agent-governance scaffold" not in f.read_text():
            fail(f"user-wide install: {name} command missing at ~/{rel}")
    if tree(proj) != before:
        fail("a user-wide install changed the project folder")
    if "no user-wide commands" not in r.stdout:
        fail("copilot user-wide must explain it is project only")
    claude_cmd = (home / ".claude/commands/project-init.md").read_text()
    if not has(claude_cmd, "init.md", "do not change anything outside it") or "git fetch" in claude_cmd:
        fail("the generated command must point at init.md, stay inside the project and not check for updates")
    if "agent: agent" in (home / ".config/opencode/commands/project-init.md").read_text():
        fail("only Copilot prompt files use the agent: field")
    if not (home / ".local/bin/claude-delete-session").is_file():
        fail("user-wide claude must install claude-delete-session")
    cfg = json.loads(settings.read_text())
    rule = "Bash(~/.local/bin/claude-delete-session)"
    if jq:
        if cfg.get("model") != "x" or cfg["permissions"]["allow"] != ["Bash(ls)", rule]:
            fail(f"settings.json not preserved or rule duplicated: {cfg}")
    elif cfg["permissions"]["allow"] != ["Bash(ls)"] or "jq not found" not in r.stdout:
        fail("without jq the installer must leave settings.json alone and print the rule")
    envf = (gov / ".env").read_text()
    if not has(envf, "AGENT_GOV_OS=", "AGENT_GOV_SHELL=", "AGENT_GOV_PY=", "AGENT_GOV_INSTALLER=install.sh"):
        fail(f".env incomplete: {envf}")

    # a copy from 0.7.0 in the wrong folder is removed, but only by a user-wide install
    wrong = home / ".opencode/commands/project-init.md"
    wrong.parent.mkdir(parents=True)
    wrong.write_text(claude_cmd)
    sh(inst, "--agent", "cursor", cwd=proj, env={"HOME": home}, rc=0)
    if wrong.exists():
        fail("the misplaced 0.7.0 file was not removed by a user-wide install")

    # project install: writes only under the project, touches nothing in HOME
    home2 = mkdir("home")
    (home2 / ".claude").mkdir()
    (home2 / ".claude/commands").mkdir()
    (home2 / ".claude/commands/foreign.md").write_text("mine")
    snap = tree(home2)
    proj2 = mkdir("proj")
    r = sh(inst, "--agent", "claude,cursor,copilot,gemini,opencode,codex", "--project", cwd=proj2, env={"HOME": home2}, rc=0)
    if tree(home2) != snap:
        fail("a --project install changed the home folder")
    for rel in (".claude/commands/project-init.md", ".cursor/commands/project-init.md", ".github/prompts/project-init.prompt.md",
                ".gemini/commands/project-init.toml", ".opencode/commands/project-init.md"):
        if not (proj2 / rel).is_file():
            fail(f"--project install missing {rel}")
    if "agent: agent" not in (proj2 / ".github/prompts/project-init.prompt.md").read_text():
        fail("Copilot prompt file needs the agent: field")
    if "codex" not in r.stdout or (proj2 / ".codex").exists():
        fail("codex has no project scope: it must say so and write nothing")
    sh(inst, "--agent", "claude", "--project", cwd=gov, env={"HOME": home2}, rc=2)  # inside the agent-gov folder

    # both scopes: warn, never delete across scopes; --uninstall removes only ours, in the scope asked
    r = sh(inst, "--agent", "claude", cwd=proj2, env={"HOME": home2}, rc=0)
    if "WARNING" not in r.stdout or "twice" not in r.stdout:
        fail("installing user-wide next to a project copy must warn about the duplicate")
    if not (proj2 / ".claude/commands/project-init.md").is_file():
        fail("the user-wide install deleted the project copy")
    sh(inst, "--agent", "claude", "--uninstall", cwd=proj2, env={"HOME": home2}, rc=0)
    if (home2 / ".claude/commands/project-init.md").exists() or not (home2 / ".claude/commands/foreign.md").exists():
        fail("--uninstall must remove only our file in that scope")
    if not (proj2 / ".claude/commands/project-init.md").is_file():
        fail("--uninstall (user-wide) removed the project copy")
    sh(inst, "--agent", "claude", "--uninstall", "--project", cwd=proj2, env={"HOME": home2}, rc=0)
    if (proj2 / ".claude/commands/project-init.md").exists():
        fail("--uninstall --project did not remove the project copy")

    # removed options and bad input
    for bad in (["--update"], ["--with", "x"], ["--agent", "nope"]):
        sh(inst, *bad, cwd=proj2, env={"HOME": home2}, rc=2)

    # Python detection recorded in .env
    for cands, want in (("python3", "AGENT_GOV_PY=python3"), ("nope1 nope2", "AGENT_GOV_PY=none")):
        h = mkdir("home")
        sh(inst, "--agent", "cursor", cwd=proj2, env={"HOME": h, "AGENT_GOV_PY_CANDIDATES": cands}, rc=0)
        if want not in (gov / ".env").read_text():
            fail(f"python detection with {cands!r}: wanted {want} in .env")


# --------------------------------------------------------------------------- gov.sh
VARS = "PROJECT_NAME=demo\nWHAT=A demo project\nGOAL=Ship it\nSTACK=python\nTASK_KEY=DEMO\nGATE_CMD=pytest\nIS_RESEARCH=no\n"


def make_vars(path, extra=""):
    path.write_text(VARS + extra)
    return path


def test_detect_and_scaffold():
    gov = ROOT
    p = mkdir("proj")
    run(["git", "init", "-q", "-b", "main"], cwd=p)
    run(["git", "remote", "add", "origin", "https://github.com/acme/demo.git"], cwd=p)
    (p / "package.json").write_text('{"scripts": {"test": "jest"}}')
    (p / ".claude").mkdir()
    (p / "record.md").write_text("legacy")
    d = sh(gov / "scripts/gov.sh", "detect", p, rc=0).stdout
    if not has(d, "manifest=no", "git=yes", "git_host=GitHub", "default_branch=main", "agent_dirs=claude",
               "gate_guess=npm test", "legacy=record.md", "agents_md=no"):
        fail(f"detect output wrong:\n{d}")

    # scaffold: selection by agents / plan-check, pointers, .gitignore, manifest, no placeholder left
    p = mkdir("proj")
    (p / "AGENTS.md").write_text("MY OWN RULES\n")
    v = make_vars(p / "vars.env", "AGENTS=claude,opencode,copilot,gemini\nPLAN_CHECK=yes\n")
    r = sh(gov / "scripts/gov.sh", "scaffold", p, "--vars", v, rc=0).stdout
    if (p / "AGENTS.md").read_text() != "MY OWN RULES\n" or "EXISTS\tAGENTS.md" not in r:
        fail("scaffold must keep an existing AGENTS.md untouched and say EXISTS")
    must = [".agents/roles.md", ".agents/wiki/decisions-log.md", ".agents/tools/plan.sh", ".agents/tools/plan.ps1",
            ".agents/tools/plan.cmd", "plan.csv", "CLAUDE.md", ".claude/commands/done.md", ".claude/commands/plan-check.md",
            ".opencode/commands/done.md", ".github/prompts/done.prompt.md", ".github/copilot-instructions.md", "GEMINI.md",
            ".agents/plan-check/plan_check.py", ".agents/init-manifest"]
    for rel in must:
        if not (p / rel).is_file():
            fail(f"scaffold did not create {rel}")
    for rel in (".cursor", ".agents/adr", ".agents/tools/check_adr.py", ".agents/tools/sync_plan.py", ".agents/tools/plan.py"):
        if (p / rel).exists():
            fail(f"scaffold must not create {rel}")
    left = [str(f.relative_to(p)) for f in p.rglob("*") if f.is_file() and ".git" not in f.parts
            and re.search(r"\{\{[A-Z_]+\}\}", f.read_text(errors="ignore")) and f.name != "AGENTS.md"]
    if left:
        fail(f"placeholders left after scaffold: {left}")
    man = (p / ".agents/init-manifest").read_text()
    if not has(man, "version " + (ROOT / "VERSION").read_text().strip(), "var PROJECT_NAME=demo", "file\t"):
        fail("manifest incomplete")
    gi = (p / ".gitignore").read_text()
    if not has(gi, ".agents/state/", ".agents/*.bak"):
        fail(".gitignore lines missing")
    sh(gov / "scripts/gov.sh", "scaffold", p, "--vars", v, rc=2)  # a second scaffold must refuse

    # not selected -> not created (claude only, no plan-check)
    p2 = mkdir("proj")
    sh(gov / "scripts/gov.sh", "scaffold", p2, "--vars", make_vars(p2 / "vars.env"), rc=0)
    for rel in (".agents/plan-check", ".claude/commands/plan-check.md", ".opencode", ".github", "GEMINI.md"):
        if (p2 / rel).exists():
            fail(f"{rel} must not be created for claude without plan-check")
    # CRLF files compare equal (Windows checkouts)
    f = p2 / ".agents/wiki/learnings.md"
    f.write_bytes(f.read_bytes().replace(b"\n", b"\r\n"))
    out = sh(gov / "scripts/gov.sh", "upgrade", p2, rc=0).stdout
    if "learnings.md" in out:
        fail(f"a CRLF copy must count as unmodified: {out}")


def test_upgrade():
    # a working copy of the repo plays "the new release"; the project was scaffolded from the current one
    gov = repo_copy()
    g = gov / "scripts/gov.sh"
    p = mkdir("proj")
    sh(g, "scaffold", p, "--vars", make_vars(p / "vars.env", "PLAN_CHECK=no\n"), rc=0)
    (p / "record.md").write_text("legacy notes")
    (p / "AGENTS.md").write_text((p / "AGENTS.md").read_text() + "- my own rule\n")
    (p / ".agents/wiki/working-process.md").write_text("my process\n")
    # release N+1
    t = gov / "templates"
    (t / ".agents/wiki/learnings.md").write_text((t / ".agents/wiki/learnings.md").read_text() + "- new in template\n")
    (t / "AGENTS.md").write_text((t / "AGENTS.md").read_text() + "- new rule in template\n")
    (t / ".agents/wiki/open-questions.md").unlink()
    (t / ".agents/wiki/working-process.md").unlink()
    (t / ".agents/wiki/extra.md").write_text("# new\n")
    plan = sh(g, "upgrade", p, rc=0).stdout
    for line in ("ADD\t.agents/wiki/extra.md", "UPDATE\t.agents/wiki/learnings.md", "CONFLICT\tAGENTS.md",
                 "REMOVE\t.agents/wiki/open-questions.md", "ORPHAN\t.agents/wiki/working-process.md"):
        if line not in plan:
            fail(f"upgrade plan lacks {line!r}:\n{plan}")
    if "dry run" not in plan or (p / ".agents/wiki/extra.md").exists() or (p / ".agents/wiki/open-questions.md").exists() is False:
        fail("the default upgrade must be a dry run that changes nothing")
    sh(g, "upgrade", p, "--apply", rc=0)
    if not (p / ".agents/wiki/extra.md").is_file() or (p / ".agents/wiki/open-questions.md").exists():
        fail("--apply must add the new file and remove the untouched dropped one")
    if "new in template" not in (p / ".agents/wiki/learnings.md").read_text():
        fail("an untouched file must be updated")
    if "my own rule" not in (p / "AGENTS.md").read_text() or "new rule in template" in (p / "AGENTS.md").read_text():
        fail("a modified AGENTS.md must be left exactly as the user has it")
    if "new rule in template" not in (p / "AGENTS.md.agent-gov-new").read_text():
        fail("the new AGENTS.md must be written to AGENTS.md.agent-gov-new")
    if (p / ".agents/wiki/working-process.md").read_text() != "my process\n" or (p / "record.md").read_text() != "legacy notes":
        fail("a modified orphan and files agent-gov does not own must be kept")
    again = sh(g, "upgrade", p, rc=0).stdout
    if "CONFLICT\tAGENTS.md" not in again or "UPDATE" in again or "ADD" in again:
        fail(f"a second upgrade must only repeat the open conflict:\n{again}")
    sh(g, "record", p, "AGENTS.md", rc=0)
    done = sh(g, "upgrade", p, rc=0).stdout
    if "CONFLICT" in done or (p / "AGENTS.md.agent-gov-new").exists():
        fail(f"record must close the conflict and remove the .new file:\n{done}")
    sh(g, "record", p, "record.md", rc=2)

    # a project with no manifest (older agent-gov): limited mode, uses the released tags
    tags = run(["git", "-C", str(ROOT), "tag", "-l", "v0.8.1"]).stdout.strip()
    if not tags:
        print("note: tag v0.8.1 not found (shallow clone?): skipped the limited-mode upgrade test")
        return
    gov2 = repo_copy()
    old = mkdir("old")
    for rel in (".agents/tools/check_adr.py", ".agents/tools/plan.py", ".agents/tools/sync_plan.py",
                ".agents/adr/README.md", ".agents/adr/0000-template.md"):
        (old / rel).parent.mkdir(parents=True, exist_ok=True)
        (old / rel).write_bytes(run(["git", "-C", str(gov2), "show", f"v0.8.1:templates/{rel}"]).stdout.encode())
    (old / ".agents/tools/sync_plan.py").write_text((old / ".agents/tools/sync_plan.py").read_text() + "# touched\n")
    (old / ".agents/adr/0001-mine.md").write_text("# my adr\n")
    (old / "AGENTS.md").write_text("custom\n")
    (old / "record.md").write_text("legacy")
    out = sh(gov2 / "scripts/gov.sh", "upgrade", old, rc=0).stdout
    for line in ("WARNING: no manifest", "REMOVE\t.agents/tools/check_adr.py", "REMOVE\t.agents/tools/plan.py",
                 "REMOVE\t.agents/adr/README.md", "ORPHAN\t.agents/tools/sync_plan.py", "UNKNOWN\tAGENTS.md",
                 "ADD\t.agents/tools/plan.sh"):
        if line not in out:
            fail(f"limited-mode plan lacks {line!r}:\n{out}")
    if "0001-mine" in out or "record.md" in out:
        fail("the user's own ADR and record.md must not appear in the plan")
    sh(gov2 / "scripts/gov.sh", "upgrade", old, "--apply", rc=0)
    if (old / ".agents/tools/check_adr.py").exists() or not (old / ".agents/adr/0001-mine.md").exists() \
            or not (old / ".agents/tools/sync_plan.py").exists() or (old / "AGENTS.md").read_text() != "custom\n":
        fail("limited-mode --apply removed or changed something it must keep")
    if (old / ".agents/init-manifest").exists():
        fail("limited mode without --vars must not create a manifest")
    # with values it can compare everything and creates the manifest
    out = sh(gov2 / "scripts/gov.sh", "upgrade", old, "--vars", make_vars(old / "vars.env"), "--apply", rc=0).stdout
    if "NEEDS-VARS" in out or not (old / ".agents/init-manifest").is_file() or not (old / "plan.csv").is_file():
        fail(f"limited mode with --vars must create the missing files and the manifest:\n{out}")


# --------------------------------------------------------------------------- plan.sh, score.sh
def scaffolded(plan_check=True, agents="claude"):
    p = mkdir("proj")
    sh(ROOT / "scripts/gov.sh", "scaffold", p, "--vars",
       make_vars(p / "vars.env", f"AGENTS={agents}\nPLAN_CHECK={'yes' if plan_check else 'no'}\n"), rc=0)
    return p


def test_plan_and_score():
    p = scaffolded()
    (p / "plan.csv").write_text(
        "id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,depends,notes\n"
        'D-1,"Quoted, with comma",ann,in-progress,2d,2000-01-01,2000-01-02,"dod ""q""",,,,,,\n'
        "D-2,Done one,bob,done,1d,2000-01-01,2000-01-01,,,,,,,\n"
        "D-3,Future,ann,todo,1d,2999-01-01,2999-01-02,,,,,,D-1,\n")
    out = sh(p / ".agents/tools/plan.sh", "list", rc=0).stdout
    if not has(out, "D-1", "Quoted, with comma LATE", "1/3 done (33%)") or "D-3" not in out or "D-2 " not in out:
        fail(f"plan.sh list output wrong:\n{out}")
    mine = sh(p / ".agents/tools/plan.sh", "list", "--owner", "ann", rc=0).stdout
    if "D-2" in mine or "D-1" not in mine or "1/3 done" not in mine:
        fail(f"plan.sh --owner must filter rows but count the whole plan:\n{mine}")
    if "D-1" in sh(p / ".agents/tools/plan.sh", "list", "--status", "done", rc=0).stdout:
        fail("plan.sh --status filter")
    sh(p / ".agents/tools/plan.sh", "set-status", "D-1", "done", rc=2)  # the edit commands are gone on purpose

    # a fresh scaffold: only the things the agent still has to do may fail
    q = scaffolded()
    r = sh(ROOT / "scripts/score.sh", q, "--agent", "t", "--write")
    failing = [l for l in r.stdout.splitlines() if l.startswith("- [ ]")]
    if len(failing) != 1 or "Standup checks" not in failing[0]:
        fail(f"a fresh scaffold should fail only 'Standup checks filled':\n{r.stdout}")
    if not (q / ".agents/state/init-report.md").is_file():
        fail("score.sh --write must write the report")
    wp = q / ".agents/wiki/working-process.md"
    wp.write_text(wp.read_text() + "- the gate passes on the default branch\n")
    r = sh(ROOT / "scripts/score.sh", q, rc=0)
    if "score 15/15" not in r.stdout and "score " not in r.stdout:
        fail(f"score after filling the standup checks:\n{r.stdout}")
    if re.search(r"^- \[ \]", r.stdout, re.M):
        fail(f"all checks should pass after filling the standup checks:\n{r.stdout}")
    e = sh(ROOT / "scripts/score.sh", mkdir("empty"))
    if e.returncode == 0 or "Traceback" in e.stderr or "No such file" in e.stderr:
        fail(f"score.sh on an empty folder must fail cleanly: {e.stderr[-200:]}")
    (q / "CLAUDE.md").write_text("junk\n")
    (q / "AGENTS.md").write_text((q / "AGENTS.md").read_text() + "{{LEFT}}\n")
    r = sh(ROOT / "scripts/score.sh", q)
    if r.returncode == 0 or "CLAUDE.md is one line" not in r.stdout or "[ ] no {{placeholder}} left" not in r.stdout:
        fail("score.sh missed a bad CLAUDE.md or a leftover placeholder")


# --------------------------------------------------------------------------- plan_check.py
def test_plan_check():
    py = shutil.which("python3") or sys.executable
    pc = ROOT / "templates/.agents/plan-check/plan_check.py"
    d = mkdir("pc")
    run(["git", "init", "-q", "-b", "main"], cwd=d)
    run(["git", "commit", "-q", "--allow-empty", "-m", "init"], cwd=d, env=GIT_ENV)
    head = "id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,depends,notes\n"

    def report(rows):
        (d / "plan.csv").write_text(head + "".join(f"{r},,,,,,,,\n" if r.count(",") < 9 else r + "\n" for r in rows))
        r = run([py, str(pc), "--no-fetch", "--date", "2026-01-10"], cwd=d)
        ids = re.findall(r"^\| ([A-Z]-\d) \|", r.stdout, re.M)
        return r, ids

    behind = ["P-1,future,ann,todo,1d,2026-02-01,2026-02-02,,,,,,,", "P-2,plain,ann,todo,1d,,,,,,,,,",
              "P-3,window today,ann,in-progress,3d,2026-01-09,2026-01-12,,,,,,,",
              "P-4,blocks P-5,bob,in-progress,3d,2026-01-08,2026-01-15,,,,,,,",
              "P-5,waits,bob,todo,1d,2026-01-16,2026-01-17,,,,,,P-4,",
              "P-6,late plain,cara,in-progress,1d,2026-01-01,2026-01-03,,,,,,,",
              "P-7,late and blocks,ann,in-progress,1d,2026-01-01,2026-01-04,,,,,,,",
              "P-8,waits,bob,todo,1d,2026-01-16,2026-01-17,,,,,,P-7,"]
    r, ids = report(behind)
    if "BEHIND SCHEDULE" not in r.stdout or ids[:5] != ["P-7", "P-6", "P-4", "P-3", "P-2"]:
        fail(f"behind schedule order must be late+blocking, late, blocking, today, rest; got {ids}\n{r.stdout[-400:]}")
    on_track = [x for x in behind if not x.startswith(("P-6", "P-7"))]
    on_track = [x.replace(",P-7,", ",,") for x in on_track]
    r, ids = report(on_track)
    if "ON TRACK" not in r.stdout or ids[:2] != ["P-3", "P-4"] or ids[-1] != "P-1":
        fail(f"on track order must put today's tasks first; got {ids}\n{r.stdout[-300:]}")
    if "adr" in r.stdout.lower():
        fail("plan-check must not mention ADRs any more")
    r = run([py, str(pc), "--no-fetch", "--lang", "vi", "--date", "2026-01-10"], cwd=d)
    if r.returncode != 0 or "| ID |" not in r.stdout:
        fail(f"plan_check --lang vi: {r.stdout}{r.stderr}")


# --------------------------------------------------------------------------- claude-delete-session
def test_delete_session():
    src = ROOT / "bin/claude-delete-session"
    compile(src.read_text(encoding="utf-8"), str(src), "exec")
    try:
        import fcntl, pty, select, struct, termios
    except ImportError:
        print("note: no pty module here: skipped the claude-delete-session terminal test")
        return
    home = mkdir("home")
    proj = home / "work" / "app"
    proj.mkdir(parents=True)
    enc = lambda p: re.sub(r"[^A-Za-z0-9]", "-", str(p))

    def make(pdir, sid, title, age):
        d = home / ".claude/projects" / enc(pdir)
        d.mkdir(parents=True, exist_ok=True)
        f = d / f"{sid}.jsonl"
        f.write_text(json.dumps({"type": "user", "cwd": str(pdir), "gitBranch": "main", "message": {"content": "hi"}})
                     + "\n" + json.dumps({"type": "ai-title", "aiTitle": title}) + "\n")
        os.utime(f, (time.time() - age, time.time() - age))
        return f

    a_ = make(proj, "aaaa", "Tối ưu triển khai", 7200)
    side = a_.with_suffix("")
    (side / "subagents").mkdir(parents=True)
    (side / "data.txt").write_text("x")
    (side / "subagents" / "agent.jsonl").write_text(json.dumps({"type": "ai-title", "aiTitle": "SUBONLY"}) + "\n")
    b_ = make(proj, "bbbb", "Second session", 9000)
    c_ = make(home / "other", "cccc", "Other project OTHERONLY", 9000)

    def tui(keys, rows=24, cols=80):
        m, sl = pty.openpty()
        fcntl.ioctl(sl, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        env = dict(os.environ, HOME=str(home), TERM="xterm")
        env.pop("CLAUDE_CONFIG_DIR", None)
        pr = subprocess.Popen([sys.executable, str(src)], stdin=sl, stdout=sl, stderr=sl, cwd=proj, env=env, close_fds=True)
        os.close(sl)
        out = b""

        def drain(sec):
            nonlocal out
            end = time.time() + sec
            while time.time() < end:
                if select.select([m], [], [], 0.05)[0]:
                    try:
                        d = os.read(m, 65536)
                    except OSError:
                        return
                    if not d:
                        return
                    out += d

        drain(0.8)
        for k in keys:
            os.write(m, k.encode())
            drain(0.4)
        drain(0.6)
        try:
            rc = pr.wait(3)
        except subprocess.TimeoutExpired:
            pr.kill()
            rc = "timeout"
        os.close(m)
        return rc, out.decode("utf-8", "replace")

    for name, keys, kw in (("ctrl+A then esc", ["\x01", "\x1b"], {}), ("very wide terminal", ["\x01", "\x1b"], {"cols": 1000}),
                           ("terminal too small", ["\x1b"], {"rows": 5, "cols": 20}),
                           ("other project hidden by default", ["OTHERONLY", "\n"], {}),
                           ("subagent transcript not listed", ["SUBONLY", "\n"], {})):
        rc, out = tui(keys, **kw)
        if rc != 0 or "Traceback" in out or "Cancelled." not in out:
            fail(f"claude-delete-session [{name}]: rc={rc} {out[-300:]!r}")
    if not c_.exists():
        fail("claude-delete-session deleted a session of another project")
    rc, out = tui(["\x01", "OTHERONLY", "\n", "n\n"])
    if rc != 0 or "Aborted." not in out or not c_.exists():
        fail(f"claude-delete-session: answering n must keep the session: {out[-200:]!r}")
    rc, out = tui(["tối", "\n", "y\n"])
    if rc != 0 or "Deleted" not in out or a_.exists() or side.exists() or not b_.exists():
        fail(f"claude-delete-session: Vietnamese search + delete: rc={rc} {out[-300:]!r}")


# --------------------------------------------------------------------------- Windows scripts
def test_windows():
    ps1s = [ROOT / "install.ps1", ROOT / "scripts/gov.ps1", ROOT / "scripts/score.ps1",
            ROOT / "templates/.agents/tools/plan.ps1"]
    for f in ps1s:
        t = f.read_text(encoding="utf-8")
        if not t.isascii():
            fail(f"{f.relative_to(ROOT)} must be ASCII only (Windows PowerShell 5.1 misreads BOM-less UTF-8)")
        for bad in ("&&", "||", "??", "?."):
            if bad in t:
                fail(f"{f.relative_to(ROOT)} uses {bad!r}, which Windows PowerShell 5.1 does not parse")
    for f in ROOT.rglob("*.ps1"):
        raw = f.read_bytes()
        if ".git" not in f.parts and not raw.isascii() and not raw.startswith(b"\xef\xbb\xbf"):
            fail(f"{f.relative_to(ROOT)} has non-ASCII text but no UTF-8 BOM")
    for cmd, ps in (("install.cmd", "install.ps1"), ("scripts/gov.cmd", "gov.ps1"), ("scripts/score.cmd", "score.ps1"),
                    ("templates/.agents/tools/plan.cmd", "plan.ps1")):
        t = (ROOT / cmd).read_text()
        if "-ExecutionPolicy Bypass" not in t or ps not in t:
            fail(f"{cmd} must call {ps} with -ExecutionPolicy Bypass")
    attrs = (ROOT / ".gitattributes").read_text()
    if "*.sh text eol=lf" not in attrs or "*.ps1 text eol=crlf" not in attrs:
        fail(".gitattributes must force LF for *.sh and CRLF for *.ps1")
    sh_ = (ROOT / "install.sh").read_text()
    ps_ = (ROOT / "install.ps1").read_text().replace("\\", "/")
    for frag in (".claude/commands", ".cursor/commands", ".github/prompts", ".gemini/commands", ".opencode/commands",
                 ".config/opencode/commands", ".codex", "prompts", "project-init.md", "project-init.prompt.md",
                 "project-init.toml", "agent-governance scaffold"):
        if frag not in sh_ or frag not in ps_:
            fail(f"install.sh and install.ps1 disagree: {frag!r} missing from one of them")
    gs, gp = (ROOT / "scripts/gov.sh").read_text(), (ROOT / "scripts/gov.ps1").read_text()
    for word in ("detect", "scaffold", "upgrade", "record", "CONFLICT", "ORPHAN", "REMOVE", "NEEDS-VARS", "UNKNOWN",
                 ".agent-gov-new", "init-manifest", "gitignore.append", "pointer.md"):
        if word not in gs or word not in gp:
            fail(f"gov.sh and gov.ps1 disagree: {word!r} missing from one of them")
    pwsh = shutil.which("pwsh")
    if not pwsh:
        print("note: pwsh not found: the Windows scripts were only checked statically")
        return
    # with PowerShell present, both shells must produce the same project
    a, b = mkdir("parity"), mkdir("parity")
    v = make_vars(a / "vars.env", "AGENTS=claude,gemini\nPLAN_CHECK=yes\nPLAN=bash .agents/tools/plan.sh\n")
    (b / "vars.env").write_text(v.read_text())
    sh(ROOT / "scripts/gov.sh", "scaffold", a, "--vars", v, rc=0)
    run([pwsh, "-NoProfile", "-File", str(ROOT / "scripts/gov.ps1"), "scaffold", str(b), "--vars", str(b / "vars.env")], check_rc=0)
    ta = {r: c for r, _s, c in tree(a) if r not in ("vars.env", ".agents/init-manifest")}
    tb = {r: c for r, _s, c in tree(b) if r not in ("vars.env", ".agents/init-manifest")}
    if {k: v_.replace(b"\r", b"") for k, v_ in ta.items()} != {k: v_.replace(b"\r", b"") for k, v_ in tb.items()}:
        fail("gov.sh and gov.ps1 scaffolded different files: " + str(sorted(set(ta) ^ set(tb))[:5]))
    h = mkdir("home")
    run([pwsh, "-NoProfile", "-File", str(ROOT / "install.ps1"), "-Agent", "opencode"], cwd=a,
        env={"HOME": str(h), "USERPROFILE": str(h)}, check_rc=0)
    if not (h / ".config/opencode/commands/project-init.md").is_file():
        fail("install.ps1 under pwsh did not write the OpenCode command")


# --------------------------------------------------------------------------- repo hygiene
def test_hygiene():
    top = re.search(r"(?m)^## (\d+\.\d+\.\d+)", (ROOT / "CHANGELOG.md").read_text())
    if not top or top.group(1) != (ROOT / "VERSION").read_text().strip():
        fail("VERSION does not match the top CHANGELOG entry")
    gone = r"agent-init|AGENT_INIT|check_adr|sync_plan|PROJECT-CHECKS|check_update|plan\.py|--update|--with"
    for f in ROOT.rglob("*"):
        if not f.is_file() or ".git" in f.parts or "__pycache__" in f.parts or f.name in ("CHANGELOG.md", "smoke_test.py", ".env", "report.md", "gov.sh", "gov.ps1"):  # gov.* list legacy file names on purpose
            continue
        try:
            txt = f.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        m = re.search(gone, txt)
        if m:
            fail(f"{f.relative_to(ROOT)} still mentions {m.group(0)!r}")
    if (ROOT / "templates/.agents/adr").exists() or (ROOT / "scripts/score_init.py").exists():
        fail("ADR templates / score_init.py must be gone")
    init = (ROOT / "init.md").read_text()
    for rel in re.findall(r"`((?:scripts|templates)/[\w./-]+)`", init):
        if not (ROOT / rel.rstrip("/")).exists():
            fail(f"init.md mentions {rel}, which does not exist")
    for cmd in ("detect", "scaffold", "upgrade", "record"):
        if f"gov.sh {cmd}" not in init:
            fail(f"init.md does not explain gov.sh {cmd}")
    if (ROOT / "AGENTS.md").exists() or (ROOT / "plan.csv").exists():
        fail("the repo itself must not carry a scaffold")
    # generated agent files: no stray Python command, every placeholder is a known variable
    known = set(re.findall(r"^[A-Z_]+(?==)", VARS, re.M)) | {"PY", "PLAN", "ROLE_NAME", "ROLE", "ROLE_OWNS", "AGENTS", "PLAN_CHECK",
                                                             "GIT_HOST", "DEFAULT_BRANCH", "EXTERNAL_TRACKER"}
    for f in (ROOT / "templates").rglob("*"):
        if f.is_file():
            for k in re.findall(r"\{\{([A-Z_]+)\}\}", f.read_text(errors="ignore")):
                if k not in known:
                    fail(f"{f.relative_to(ROOT)} uses the unknown placeholder {{{{{k}}}}}")


def main():
    tests = [test_installer, test_detect_and_scaffold, test_upgrade, test_plan_and_score, test_plan_check,
             test_delete_session, test_windows, test_hygiene]
    only = sys.argv[1:]
    try:
        for t in tests:
            if only and t.__name__ not in only:
                continue
            before = len(FAILURES)
            try:
                t()
            except Exception as e:  # a crashed test is a failure, not a stack trace for the maintainer to decode
                fail(f"{t.__name__} crashed: {type(e).__name__}: {e}")
            print(f"{'ok  ' if len(FAILURES) == before else 'FAIL'} {t.__name__}")
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    for f in FAILURES:
        print("FAIL", f)
    if FAILURES:
        sys.exit(1)
    print("OK smoke test")


if __name__ == "__main__":
    main()

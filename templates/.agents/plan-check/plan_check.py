#!/usr/bin/env python3
"""plan-check: compare the plan with git and every MR/PR, and say who each task blocks.

Python standard library only. Read-only: it never edits the plan and never merges.

  plan_check.py [--owner NAME] [--date YYYY-MM-DD] [--lang en|vi|...] [--template FILE]
                [--plan FILE] [--base BRANCH] [--no-fetch]

It checks three things and prints ONE report (a verdict plus one task table):
  1. the plan      a CSV with the columns below
  2. the code      the base branch head, and every open or merged MR/PR
  3. the blockers  who is waiting on each task

What the report looks like (table columns, wording, language) lives in a template file:
templates/plan-check.<lang>.md. Edit that file, not this one.

Telling an open MR from a merged or closed one needs the host API. Put a token in PLAN_CHECK_TOKEN
(or GITLAB_TOKEN / GITHUB_TOKEN). Without it the tool still works from git alone and says so.

Plan columns (header names, any order; extra columns are ignored):
  id  title  owner  status  estimate  start  end  depends  adr
  status   todo | in-progress | done   ("To Do" / "In Progress" / "Done" also work)
  start/end  YYYY-MM-DD
  depends  ids this task waits on, separated by ";"     -> "who it blocks" is the inverse
  adr      ADR numbers this task delivers, e.g. "0007;0009"
           -> the task keeps blocking its dependants until those ADRs are no longer `proposed`
"""
import argparse
import csv
import datetime
import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
MR_SCAN = 60  # newest MR/PR heads to scan
MR_LAYOUTS = (  # GitLab, then GitHub: whichever host answers is used
    ("refs/merge-requests/*/head", r"refs/merge-requests/(\d+)/head"),
    ("refs/pull/*/head", r"refs/pull/(\d+)/head"),
)
PLAN_CANDIDATES = ("plan.csv", ".agents/plan.csv", "docs/plan.csv")
ADR_CANDIDATES = (".agents/adr", "docs/adr", "adr")
BASE_CANDIDATES = ("origin/main", "origin/master", "origin/develop", "main", "master", "develop")
STATUS_ALIASES = {"to-do": "todo", "todo": "todo", "in-progress": "in-progress", "doing": "in-progress", "done": "done"}
ROW_KEYS = ("id", "title", "owner", "status", "est", "start", "end", "plan", "git", "progress", "blocks")
REPORT_KEYS = ("date", "verdict", "summary", "sources", "table", "confirm")
LABEL_KEYS = (
    "ok late n_late due mismatch blk_yes blk_no src sync_ok sync_stale sync_none sync_skip mrs mrs_unverified "
    "nogit merged_todo done late_s waiting today no_mr future ontime review mism nocode merge leftover adr_wait confirm none"
).split()


# ---------------------------------------------------------------- git

def find_root():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else Path.cwd()


ROOT = find_root()


def git(*args):
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def git_ok(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True).returncode == 0


def base_ref(forced):
    cands = [forced] if forced else []
    head = git("symbolic-ref", "-q", "refs/remotes/origin/HEAD")
    if head:
        cands.append(head[len("refs/remotes/"):])
    cands += BASE_CANDIDATES
    for ref in cands:
        if git_ok("rev-parse", "--verify", "-q", ref + "^{commit}"):
            return ref
    return None


def id_rx(task_id):
    return re.compile(r"(?<![A-Za-z0-9])" + re.escape(task_id) + r"(?![A-Za-z0-9])", re.I)


def mr_heads(fetch):
    """-> (MR/PR numbers whose head is cached under refs/mr/<n>, host kind or None).

    refs/mr/* is a private namespace, never refs/heads, so no local branch is created. The host is
    detected by asking the remote for GitLab refs first, then GitHub refs: nothing to configure.
    """
    kind, layout, heads = None, None, {}
    if fetch and git("remote"):
        for glob, rx in MR_LAYOUTS:
            for line in git("ls-remote", "origin", glob).splitlines():
                sha, _, ref = line.partition("\t")
                m = re.fullmatch(rx, ref)
                if m:
                    heads[int(m.group(1))] = sha
            if heads:
                layout, kind = glob, ("gitlab" if "merge-requests" in glob else "github")
                break
    if heads:
        newest = sorted(heads, reverse=True)[:MR_SCAN]
        stale = [n for n in newest if git("rev-parse", "--verify", "-q", f"refs/mr/{n}") != heads[n]]
        if stale:
            subprocess.run(["git", "-C", str(ROOT), "fetch", "--quiet", "origin",
                            *[f"+{layout.replace('*', str(n))}:refs/mr/{n}" for n in stale]],
                           capture_output=True, text=True)
    cached = git("for-each-ref", "refs/mr", "--format=%(refname)").splitlines()
    return sorted((int(r.rsplit("/", 1)[1]) for r in cached), reverse=True)[:MR_SCAN], kind


def parse_remote(url):
    """'https://host/a/b.git' | 'git@host:a/b.git' | 'ssh://git@host:22/a/b.git' -> (host, 'a/b')."""
    m = re.match(r"^(?:[A-Za-z+]+://)?(?:[^@/]+@)?([^/:]+)(?::\d+)?[:/](.+?)(?:\.git)?/?$", url.strip())
    return (m.group(1), m.group(2)) if m else None


def api_get(url, kind):
    names = ("PLAN_CHECK_TOKEN",) + (("GITLAB_TOKEN", "GL_TOKEN") if kind == "gitlab" else ("GITHUB_TOKEN", "GH_TOKEN"))
    token = next((os.environ[n] for n in names if os.environ.get(n)), "")
    headers = {"Accept": "application/json", "User-Agent": "plan-check"}
    if token:
        headers["PRIVATE-TOKEN" if kind == "gitlab" else "Authorization"] = token if kind == "gitlab" else f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as r:  # noqa: S310
        return json.loads(r.read().decode())


def host_mrs(kind, remote_url):
    """-> (set of open MR/PR numbers, merged MRs [{n,title,src,dst}]) from the host API, or (None, None).

    This is what tells a CLOSED or already-MERGED MR from an open one, and sees through squash and
    stacked merges. Needs a token in PLAN_CHECK_TOKEN (or GITLAB_TOKEN / GITHUB_TOKEN); public GitHub
    repos work without one. On any failure (no token, offline, 401) it returns (None, None) and the
    report says the open/closed state is not verified. PLAN_CHECK_API_BASE overrides the API root.
    """
    parsed = parse_remote(remote_url) if kind else None
    if not parsed:
        return None, None
    host, path = parsed
    override = os.environ.get("PLAN_CHECK_API_BASE")

    def pages(url, n=3):
        out = []
        for p in range(1, n + 1):
            got = api_get(f"{url}{'&' if '?' in url else '?'}per_page=100&page={p}", kind)
            out += got
            if len(got) < 100:
                break
        return out

    try:
        if kind == "gitlab":
            base = (override or f"https://{host}") + "/api/v4/projects/" + urllib.parse.quote(path, safe="")
            opened = {m["iid"] for m in pages(f"{base}/merge_requests?state=opened")}
            merged = [dict(n=m["iid"], title=m["title"], src=m["source_branch"], dst=m["target_branch"])
                      for m in pages(f"{base}/merge_requests?state=merged&order_by=updated_at&sort=desc")]
        else:
            root = override or ("https://api.github.com" if host == "github.com" else f"https://{host}/api/v3")
            base = f"{root}/repos/{path}"
            opened = {m["number"] for m in pages(f"{base}/pulls?state=open")}
            merged = [dict(n=m["number"], title=m["title"], src=m["head"]["ref"], dst=m["base"]["ref"])
                      for m in pages(f"{base}/pulls?state=closed&sort=updated&direction=desc") if m.get("merged_at")]
    except (OSError, ValueError, KeyError, TypeError):
        return None, None
    return opened, merged


def via_merged_mr(rx, merged_mrs, base_branch):
    """'!950 -> !949' when a merged MR whose TITLE or SOURCE BRANCH names the id reached the base branch.

    Follows stacked MRs (merged into another MR's branch, which later reached the base). A squash
    merge leaves only the outer MR's title in the base history, so this is the only way to see the
    inner task. MR descriptions are NOT used: they list what the MR does NOT do.
    """
    by_source = {}
    for m in merged_mrs:  # newest first, so setdefault keeps the newest MR for a reused branch name
        by_source.setdefault(m["src"], m)
    for m in merged_mrs:
        if not (rx.search(m["title"]) or rx.search(m["src"])):
            continue
        chain, cur = [m], m
        for _ in range(4):
            if cur["dst"] == base_branch:
                return " -> ".join(f"!{c['n']}" for c in chain)
            nxt = by_source.get(cur["dst"])
            if not nxt or nxt in chain:
                break
            chain.append(nxt)
            cur = nxt
    return None


def git_state(rows, forced_base, fetch):
    """-> (meta, {task id: {state, short, commit, leftover}}).

    state: MERGED / OPEN-MR / PARTIAL / BRANCH-ONLY / NONE. "No merge on the base branch" does NOT
    mean "not done": the work may sit on an open MR. PARTIAL = merged AND a verified-open MR still
    names the id. Without the host API (open_set is None) a merged commit wins, because a squash-merged
    MR keeps looking open to git forever; the leftover MR is only noted.
    """
    base = base_ref(forced_base)
    if not base:
        return None, {}
    online = fetch and bool(git("remote"))
    if online:
        git("fetch", "origin", "--prune", "--quiet")
    base_branch = base[len("origin/"):] if base.startswith("origin/") else base
    commits = []  # (sha, subject, body)
    for rec in git("log", base, "-n", "1500", "--format=%h%x1f%s%x1f%b%x1e").split("\x1e"):
        p = rec.strip().split("\x1f")
        if len(p) >= 2:
            commits.append((p[0], p[1], p[2] if len(p) > 2 else ""))
    mrs_all, kind = mr_heads(fetch)
    open_set, merged_mrs = host_mrs(kind, git("remote", "get-url", "origin")) if online else (None, None)
    subjects = {n: git("log", f"{base}..refs/mr/{n}", "-n", "100", "--format=%s") for n in mrs_all}
    tips = {n: git("log", "-1", "--format=%s", f"refs/mr/{n}") for n in mrs_all}
    branches = [b for b in git("for-each-ref", "refs/remotes/origin", "--format=%(refname:short)").splitlines()
                if not b.endswith("/HEAD")]
    out = {}
    for r in rows:
        rx = id_rx(r["id"])
        merged = [(h, s) for h, s, b in commits if rx.search(s) or rx.search(b)]
        if not merged and merged_mrs:  # squash / stacked merges leave no id in the base history
            chain = via_merged_mr(rx, merged_mrs, base_branch)
            if chain:
                merged = [(chain, "")]
        mrs = [n for n in mrs_all if rx.search(subjects[n]) and (open_set is None or n in open_set)]
        mrs.sort(key=lambda n: (not rx.search(tips[n]), -n))  # the MR whose tip names the id first
        leftover = None
        if mrs and merged and open_set is None:
            leftover, mrs = mrs[0], []
        stray = [b for b in branches if rx.search(b)
                 and not git_ok("merge-base", "--is-ancestor", f"refs/remotes/{b}", base)]
        if mrs and merged:
            state = "PARTIAL"
        elif mrs:
            state = "OPEN-MR"
        elif merged:
            state = "MERGED"
        elif stray:
            state = "BRANCH-ONLY"
        else:
            state = "NONE"
        if mrs:
            n = mrs[0]
            short = f"MR !{n} (behind {git('rev-list', '--count', f'refs/mr/{n}..{base}') or '?'})"
        elif merged:
            short = merged[0][0]
        elif stray:
            short = stray[0]
        else:
            short = ""
        out[r["id"]] = dict(state=state, short=short, commit=merged[0][0] if merged else "", leftover=leftover)
    remote = git("ls-remote", "origin", f"refs/heads/{base_branch}").split() if online else []
    meta = dict(base=base, sha=git("rev-parse", "--short=8", base), remote=remote[0][:8] if remote else "",
                scanned=len(mrs_all), verified=open_set is not None)
    return meta, out


# ---------------------------------------------------------------- plan + ADR

def parse_date(value):
    try:
        return datetime.date.fromisoformat((value or "").strip()[:10])
    except ValueError:
        return None


def split_ids(value):
    return [t for t in re.split(r"[;,\s]+", value or "") if t]


def load_plan(path):
    with path.open(newline="", encoding="utf-8-sig") as f:
        rows = [{(k or "").strip().lower(): (v or "").strip() for k, v in row.items()} for row in csv.DictReader(f)]
    rows = [r for r in rows if r.get("id")]
    for r in rows:
        s = re.sub(r"[\s_]+", "-", r.get("status", "").lower())
        r["status"] = STATUS_ALIASES.get(s, "todo")
    return rows


def adr_pending(token):
    """Status text if the ADR is still `proposed` / has no status / is missing, else None (accepted, superseded)."""
    m = re.search(r"\d+", token)
    if not m:
        return "?"
    n = f"{int(m.group()):04d}"
    for d in ADR_CANDIDATES:
        for f in sorted((ROOT / d).glob(f"{n}-*.md")):
            s = re.search(r"^\s*[-*]?\s*\**Status\**:?\**\s*\**\s*([A-Za-z][A-Za-z-]*)",
                          f.read_text(encoding="utf-8", errors="replace"), re.I | re.M)
            status = s.group(1).lower() if s else "no status"
            return status if status in ("proposed", "no status") else None
    return "missing"


# ---------------------------------------------------------------- template

def find_template(explicit, lang):
    cands = [Path(explicit)] if explicit else [ROOT / ".agents/templates" / f"plan-check.{lang}.md",
                                               HERE / "templates" / f"plan-check.{lang}.md"]
    for c in cands:
        if c.is_file():
            return c
    raise SystemExit("report template not found: " + ", ".join(str(c) for c in cands))


def load_template(path):
    """-> (report, (header, row), labels) from the three fenced blocks of a template file."""
    text = path.read_text(encoding="utf-8")
    blocks = {m.group(2): m.group(3) for m in re.finditer(r"^(`{3,})(report|table|labels)\n(.*?)\n\1[ \t]*$", text, re.S | re.M)}
    for kind in ("report", "table", "labels"):
        if kind not in blocks:
            raise SystemExit(f"{path}: missing the ```{kind} block")
    lines = [ln for ln in blocks["table"].splitlines() if ln.strip()]
    if len(lines) != 2:
        raise SystemExit(f"{path}: the table block needs exactly two lines (header, row)")
    labels = {}
    for ln in blocks["labels"].splitlines():
        if "=" in ln and not ln.lstrip().startswith("#"):
            k, _, v = ln.partition("=")
            labels[k.strip()] = v.strip()
    missing = [k for k in LABEL_KEYS if k not in labels]
    if missing:
        raise SystemExit(f"{path}: missing label(s): {', '.join(missing)}")
    for tag, tpl, keys in (("report", blocks["report"], REPORT_KEYS), ("table row", lines[1], ROW_KEYS)):
        bad = sorted(set(re.findall(r"{(\w+)}", tpl)) - set(keys))
        if bad:
            raise SystemExit(f"{path}: unknown placeholder(s) in {tag}: {', '.join(bad)}. Valid: {', '.join(keys)}")
    return blocks["report"], (lines[0], lines[1]), labels


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--owner", help="only this owner's tasks (blockers are still computed from the whole plan)")
    ap.add_argument("--date", help="YYYY-MM-DD, default today")
    ap.add_argument("--lang", default=os.environ.get("PLAN_CHECK_LANG", "en"), help="picks templates/plan-check.<lang>.md")
    ap.add_argument("--template", help="a report template file (overrides --lang)")
    ap.add_argument("--plan", help="plan CSV, default: " + " or ".join(PLAN_CANDIDATES))
    ap.add_argument("--base", help="branch work is merged into (default: origin's default branch)")
    ap.add_argument("--no-fetch", action="store_true", help="do not touch the network; use cached refs")
    args = ap.parse_args()

    today = parse_date(args.date) if args.date else datetime.date.today()
    if today is None:
        raise SystemExit("--date must be YYYY-MM-DD")
    plan_path = Path(args.plan) if args.plan else next((ROOT / c for c in PLAN_CANDIDATES if (ROOT / c).is_file()), None)
    if not plan_path or not plan_path.is_file():
        raise SystemExit("plan CSV not found: pass --plan FILE (looked for " + ", ".join(PLAN_CANDIDATES) + ")")
    report_tpl, (head_tpl, row_tpl), L = load_template(find_template(args.template, args.lang))

    rows = load_plan(plan_path)
    meta, res = git_state(rows, args.base, fetch=not args.no_fetch)
    git_on = meta is not None
    dependants = {}
    for r in rows:
        if r["status"] != "done":
            for dep in split_ids(r.get("depends")):
                dependants.setdefault(dep.lower(), []).append(r["id"])

    order = {"late": 0, "today": 1, "mismatch": 1, "wait": 2, "adr": 3, "ok": 4, "future": 5}
    table, late, due_today, mism, cands, blocking, blocked = [], [], [], [], [], [], set()
    for r in rows:
        status = r["status"]
        st = res.get(r["id"], {"state": "N/A", "short": "", "commit": ""})
        delivered = st["state"] == "MERGED" if git_on else status == "done"
        pending = {a: p for a in split_ids(r.get("adr")) if (p := adr_pending(a))}
        if delivered and status == "done" and not pending:
            continue
        if args.owner and r.get("owner", "") != args.owner:
            continue  # verdict, blockers and table all describe the same rows
        start, end = parse_date(r.get("start")), parse_date(r.get("end"))
        if delivered and status != "done":
            sched, kind = L["merged_todo"], "ok"
            cands.append(r["id"])
        elif delivered:
            sched, kind = L["done"], "adr"
        elif end and end < today:
            sched, kind = L["late_s"].format(d=(today - end).days), "late"
            if st["state"] in ("OPEN-MR", "PARTIAL"):
                sched += " " + L["waiting"]
            if status == "done" and st["state"] == "NONE" and git_on:
                sched += " · " + L["mism"]
                mism.append(r["id"])
            late.append(f'{r["id"]} +{(today - end).days}d')
        elif status == "done":
            if st["state"] in ("OPEN-MR", "PARTIAL"):
                sched, kind = L["review"], "wait"
            else:
                sched, kind = L["mism"], "mismatch"
                mism.append(r["id"])
        elif end == today:
            sched = L["today"] + ("" if st["state"] in ("OPEN-MR", "PARTIAL") or not git_on else ", " + L["no_mr"])
            kind = "today"
            due_today.append(r["id"])
        elif start and start > today:
            sched, kind = L["future"].format(d=f"{start:%d/%m}"), "future"
        else:
            sched, kind = L["ontime"], "ok"

        cons = dependants.get(r["id"].lower(), []) if (not delivered or pending) else []
        why = ", ".join(f"{a} ({p})" for a, p in pending.items())
        block = (L["adr_wait"].format(x=why) if why else "") + ((" → " if why else "") + ", ".join(cons) if cons else "")
        if cons:
            blocking.append(r["id"])
            blocked.update(cons)
        title = r.get("title", "")
        git_cell = L["none"] if not git_on else (f'MERGED · {L["merge"].format(x=st["commit"])}'
                                                 + (" " + L["leftover"].format(n=st["leftover"]) if st.get("leftover") else "")
                                                 if st["state"] == "MERGED"
                                                 else f'{st["state"]} · {st["short"] or L["nocode"]}')
        cells = dict(id=r["id"], title=title if len(title) <= 46 else title[:45] + "…", owner=r.get("owner") or L["none"],
                     status=status, est=r.get("estimate") or L["none"], start=f"{start:%d/%m}" if start else L["none"],
                     end=f"{end:%d/%m}" if end else L["none"],
                     plan=f"{start:%d/%m}→{end:%d/%m}" if start and end else L["none"],
                     git=git_cell, progress=sched, blocks=block or L["none"])
        table.append((order[kind], end or today, {k: v.replace("|", "/") for k, v in cells.items()}))
    table.sort(key=lambda x: (x[0], x[1]))

    bits = []
    if late:
        bits.append(L["n_late"].format(n=len(late), ids=", ".join(late)))
    if due_today:
        bits.append(L["due"].format(ids=", ".join(due_today)))
    if mism:
        bits.append(L["mismatch"].format(ids=", ".join(mism)))
    bits.append(L["blk_yes"].format(a=len(blocking), b=len(blocked)) if blocked else L["blk_no"])
    if git_on:
        sync = (L["sync_skip"] if args.no_fetch else L["sync_none"] if not meta["remote"] else
                L["sync_ok"] if meta["remote"] == meta["sha"] else L["sync_stale"].format(r=meta["remote"]))
        mrs = L["mrs"].format(n=meta["scanned"]) + ("" if meta["verified"] else " · " + L["mrs_unverified"])
        sources = L["src"].format(n=len(rows), done=sum(r["status"] == "done" for r in rows), branch=meta["base"],
                                  sha=meta["sha"], sync=sync, mrs=mrs)
    else:
        sources = L["nogit"]
    n_cols = head_tpl.count("|") - 1
    table_md = "\n".join([head_tpl, "|" + "---|" * n_cols] + [row_tpl.format(**c) for _o, _e, c in table])
    out = report_tpl.format(
        date=f"{today:%Y-%m-%d}", verdict=L["late"] if late else L["ok"], summary=" · ".join(bits), sources=sources,
        table=table_md, confirm=L["confirm"].format(ids=", ".join(cands)) if cands else "")
    print(re.sub(r"\n{3,}", "\n\n", out).strip())


if __name__ == "__main__":
    main()

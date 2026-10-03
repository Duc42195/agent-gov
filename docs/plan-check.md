# plan-check

A daily standup check for any repo. It compares **the plan** with **the code** (the base branch and every
open or merged MR/PR), checks **who each task blocks**, and returns one report:

1. a verdict: **ON TRACK** or **BEHIND SCHEDULE**
2. one task table, with the blockers as a column of that table, in this order:
   - **on track:** the tasks of today (inside their start-end window), then the remaining tasks;
   - **behind schedule:** first the tasks that are late **and** block others, then the late tasks, then the tasks that block others, then today's tasks and the rest.

Python standard library only. Read-only: it never edits your plan and never merges.

## What you get

```text
## 2026-09-25 — 🔴 **BEHIND SCHEDULE**
3 task(s) past their end date: APP-3 +4d, APP-4 +2d, APP-5 +1d · Blocking others: **yes** (3 task(s) holding up 3)
Sources: plan (5 tasks, 2 done) · origin/main head `ff7431f7` matches remote ✅ · 1 MR/PR heads scanned · open/closed state of MRs not verified

| ID | Task | Owner | Est | Plan | Git | Progress | Blocks |
|---|---|---|---|---|---|---|---|
| APP-3 | Implement the export endpoint | bob | 3d | 17/09→21/09 | OPEN-MR · MR !12 (behind 0) | 🔴 LATE +4d (MR waiting) | APP-4 |
| APP-4 | Add export button to the UI | ann | 2d | 22/09→23/09 | NONE · no code yet | 🔴 LATE +2d | APP-5 |
| APP-5 | Write the user guide | cara | 1d | 24/09→24/09 | NONE · no code yet | 🔴 LATE +1d | — |
| APP-6 | Release notes | cara | 1d | 25/09→26/09 | NONE · no code yet | 🟢 on time | — |
```

Reading it: a task is **late** only if its work is not merged yet. An open MR counts as "late, MR waiting",
never as "not started". A task that is merged and `done` leaves the table.

## Install

`/project-init` offers it (question 10) and copies `.agents/plan-check/` and the command for your agent. Project-specific checks live in your own file, **`.agents/wiki/working-process.md`**, under `## Standup checks`: bullet lines such as "the gate passes on the default branch" or "a task is `done` but its `review` is `pending`". Init writes 3-6 of them to fit your project. `/plan-check` runs them (read-only) after the report and prints only the ones that fail. The script and the report table never change because of them, so upgrading agent-gov never conflicts with your checks.

Then type `/plan-check` (or `/plan-check <owner>`). With any other tool, or in a terminal: `python3 .agents/plan-check/plan_check.py` (or `python`/`py -3`, whichever your machine has). If Python is missing, the command replies `Python 3.8+ not found` and stops.

Needs `git` and Python 3.8+. No packages.

## Your plan

A CSV at `plan.csv`, `.agents/plan.csv` or `docs/plan.csv` (or pass `--plan FILE`). See `templates/plan.csv`.
Header names are case-insensitive, any order, extra columns are ignored. An Excel sheet exported as CSV works.

| Column | Meaning |
|---|---|
| `id` | the task id; it must appear in the commit subject or branch name of the work (`feat: export endpoint (APP-3)`) |
| `title`, `owner`, `estimate` | shown in the table; `--owner NAME` filters to one person |
| `status` | `todo`, `in-progress` or `done` (`To Do`, `In Progress`, `Done` also work) |
| `start`, `end` | `YYYY-MM-DD`; a task is late when `end` is before today and the work is not merged |
| `depends` | ids this task waits on, separated by `;`. **Who a task blocks is the inverse of this column** |

## Change what the report looks like

Everything visible is in a template file, not in the code: `templates/plan-check.en.md` (English) and
`templates/plan-check.vi.md` (Vietnamese). Each has three blocks you can edit:

- **return template**: the layout (`{date}` `{verdict}` `{summary}` `{sources}` `{table}` `{confirm}`)
- **table template**: the columns; add, drop or reorder them (`{id}` `{title}` `{owner}` `{est}` `{plan}` `{git}` `{progress}` `{blocks}` ...)
- **labels**: every word and emoji, including the verdict text

To customise for one project, copy a template to `.agents/templates/plan-check.<lang>.md`; it wins over the shipped one.
For another language, copy a template to `plan-check.<lang>.md` and run with `--lang <lang>`.
A template with an unknown placeholder or a missing label fails with a message that names it.

## Options

| Option | Default |
|---|---|
| `--owner NAME` | whole plan |
| `--lang en\|vi\|...` | `en` (or env `PLAN_CHECK_LANG`) |
| `--base origin/BRANCH` | origin's default branch. Use it when work merges into something else, e.g. `origin/release/x` |
| `--plan FILE` | `plan.csv`, then `.agents/plan.csv`, then `docs/plan.csv` |
| `--date YYYY-MM-DD` | today |
| `--template FILE` | overrides `--lang` |
| `--no-fetch` | never touches the network; uses cached refs |

## Make it accurate: give it a token

From git alone the tool cannot tell an **open** MR from a **closed or squash-merged** one, and cannot see a task
merged under another task's stacked MR. It then says so ("open/closed state of MRs not verified") and, when a
merge commit for the task exists, trusts the merge. For the exact answer, set a token in the environment:

```bash
export PLAN_CHECK_TOKEN=...     # or GITLAB_TOKEN / GITHUB_TOKEN
```

GitLab (self-hosted too) and GitHub are detected from the remote automatically. Public GitHub repos work without
a token. If the token is wrong or the host is unreachable, the tool falls back to git and says so. Never put the
token in a file in the repo.

## Limits you should know

- A task counts as merged only if its id is in a commit subject/body or MR title on the base branch. Put the task id
  in every commit subject. Without a token, a task merged only under another task's stacked MR reads as not merged.
- `depends` is written by people. The tool never guesses a dependency.
- The newest 60 MR/PR heads are scanned.

## Files

```
templates/.agents/plan-check/plan_check.py                 the script
templates/.agents/plan-check/templates/plan-check.en.md    report template, English
templates/.agents/plan-check/templates/plan-check.vi.md    report template, Vietnamese
templates/.claude/commands/plan-check.md                   the command (Cursor/Copilot variants alongside)
```

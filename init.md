# init.md — bootstrap agent governance for a new project

**You are an AI coding agent. Follow this file step by step.** It sets up a small, shared way of working so a project with several people (and several AI tools) stays consistent: one rulebook, one task list, one decision record, one running knowledge base.

Ground rules:
- Ask the user in the language they write in.
- Never overwrite an existing file. If a target exists, read it, keep its content, add only what is missing.
- Ask questions once, in a single batch (use your question tool if you have one). Do not interrogate.
- Never write secrets, tokens or passwords into any file.
- Do not commit or push. At the end, tell the user what to commit.
- When done, run Step 6. It is how this scaffold gets better.

Four axes:

| Axis | What | Files |
|---|---|---|
| 1. Context | what everyone must know | `AGENTS.md`, `plan.csv`, `.agents/adr/`, `.agents/wiki/` |
| 2. Action | how work gets closed | `/done <task-id>` command |
| 3. External | sync with trackers / git host | `.agents/tools/sync_plan.py` |
| 4. Team | who does what, how far, is it right | `.agents/roles.md` + columns in `plan.csv` |

## Where the templates are

The target project is the directory Claude Code was opened in. If this file sits in a subfolder (e.g. `./agent-gov/`), that folder is only the source: write into the project root, never into it.

All file contents live in `templates/`, mirroring the target paths. Find that folder next to this file, or in `~/.claude/templates/templates/`. Copy files from there; do not retype them. Only read a template when you are about to create it.

## Step 1 — Read what exists

Learn from the repo before asking:
- Git repo? Which host (`git remote -v`)? Default branch?
- A `plan.csv` from an older setup (at the root or elsewhere): keep its rows. Migrate them in place into the new columns (header in `templates/plan.csv`), moving it to the project root if needed; never discard rows.
- Existing `README*`, `AGENTS.md`, `CLAUDE.md`, `.agents/`, `plan.csv`, `docs/adr/`, notes.
- Code or docs only? Check manifests (`pyproject.toml`, `package.json`, `go.mod`, ...). Docs-only means no gate command.
- Gate command: test/lint from the manifest, `Makefile` or CI config.
- Which AI tool config folders exist (`.claude/`, `.cursor/`, `.github/`, `.opencode/`).
- **Python:** run `python3 --version`, `python --version`, `py -3 --version` in that order; the first that prints 3.8 or newer is `{{PY}}` (the `/project-init` command may already name it). If none works, `{{PY}}` = `python3` and the Profile line reads `Python: python3 (NOT FOUND at init: install Python 3.8+)`: tell the user, skip every step below that runs a script (Steps 5.1, 5.4 and 6), and say so in the report.
- **Upgrade mode:** if `.agents/init-version` exists, this project is already scaffolded. Do not re-run Steps 2–4. Compare it with `VERSION` next to this file. Same version → say so and stop. Older → read `CHANGELOG.md`, apply every `Upgrade:` line for versions after it, replace unmodified files in `.agents/tools/` with the templates (show a diff and ask for any file the project changed), never touch `plan.csv` rows, wiki, ADRs, a filled `Project checks` block in a `plan-check` command, or `AGENTS.md` content beyond the listed changes, then write the new version to `.agents/init-version`, run Step 6 and report what changed.

If the project has content, summarise it in a few lines and skip every question you can already answer.

## Step 2 — Ask what is missing

One batch, only what you could not learn. Every answer has a default, so the user may reply "defaults".

**System** (always ask 1–3 unless clear from the repo)
1. What is the project and who is it for?
2. What does "done" look like for the whole project?
3. Tech stack (default: detected, else "docs only").
4. Research project (experiments, results, paper)? → `{{IS_RESEARCH}}` `yes|no` (default `no`)
5. Task id prefix → `{{TASK_KEY}}` (default `TASK`)

**Tools** (skip if solo and defaults fit)
6. External tracker `jira|gsheet|excel|none` → `{{EXTERNAL_TRACKER}}` (default `none`)
7. Git host GitHub/GitLab/shared drive, default branch → `{{GIT_HOST}}`, `{{DEFAULT_BRANCH}}` (default: detected, else `main`)
8. AI tools used: Claude Code, Cursor, Copilot, OpenCode, other (default: detected from config folders, else Claude Code)

**Team** (skip if the repo is clearly solo)
9. Who, and which role each? Roles: `maintainer`, `dev`, `reviewer`, `qa`, `pm`, `researcher`, `writer`. One person may hold several. Solo → one row (default: the git user as `maintainer`), review needing a second person is skipped.

**Standup** (only if the project uses git with MR/PRs)
10. Do you want `/plan-check`, a standup command that compares `plan.csv` with git and every MR/PR, says on or behind schedule, and shows who blocks whom? → default `no`.

Set `{{PROJECT_NAME}}` from the folder name unless told otherwise. `{{PY}}` comes from Step 1; replace it everywhere you copy, so no command in the project says a bare `python` that this machine lacks. Set `{{GATE_CMD}}` to the gate command, or empty for docs-only.

## Step 3 — Confirm, then write

Show a short profile (what/goal/stack/type/team/tools) and the file list below. Get one yes.

## Step 4 — Scaffold

Copy, replacing every `{{PLACEHOLDER}}` (no braces left behind), never overwriting.

| Copy from `templates/` | To | Notes |
|---|---|---|
| `AGENTS.md` | `AGENTS.md` | Fill Profile lines `<one line>` and stack. If the file exists, merge sections in. Not research → delete the `Results:` bullet and the HTML comment above it. |
| `CLAUDE.md` | `CLAUDE.md` | One line `@AGENTS.md`. |
| `pointer.md` | each other AI tool's own config location | Only for tools that do not read `AGENTS.md` natively, e.g. `.cursor/rules/agents.mdc`, `.github/copilot-instructions.md`. |
| `gitignore.append` | `.gitignore` | Append missing lines; create if needed. |
| `.agents/roles.md` | same | Fill the table from Step 2. |
| `plan.csv` | `plan.csv` (project root) | Add rows for tasks the user named, else keep the example and say so. If one exists, migrate it, do not replace it. Columns: `status` `todo|in-progress|done`; `review` `pending|approved|changes`; `mr` MR/PR link; `dod` definition of done; `depends` ids this task waits on, `;`-separated; `adr` ADR numbers it delivers (it blocks its dependants until they are no longer `proposed`). |
| `.agents/adr/*` | same | Includes index README and template. |
| `.agents/wiki/*` | same | Four append-only logs. |
| *(the `VERSION` file next to `init.md`)* | `.agents/init-version` | Copy its content. Lets `/project-init` recognise an old scaffold later and upgrade it. |
| `.agents/tools/*.py` | same | `sync_plan.py`: set `BACKEND`, and implement only the chosen tracker's function. |
| `.claude/commands/done.md` | same | Claude Code. |
| `.cursor/commands/done.md` | same | Only if Cursor is used. |
| `.github/prompts/done.prompt.md` | same | Only if Copilot is used. |
| `.opencode/commands/done.md` | same | Only if OpenCode is used. |

Only if the user said yes to question 10, also copy:

| Copy from `templates/` | To | Notes |
|---|---|---|
| `.agents/plan-check/*` | same | The script and the report templates. Do not edit them. |
| `.claude/commands/plan-check.md` | same | Claude Code. |
| `.cursor/commands/plan-check.md` | same | Only if Cursor is used. |
| `.github/prompts/plan-check.prompt.md` | same | Only if Copilot is used. |
| `.opencode/commands/plan-check.md` | same | Only if OpenCode is used. |

Then **tailor the command**: in each copied `plan-check` command replace the line `<!-- PROJECT-CHECKS -->` with 3–6 lines, one check each, derived from the profile. Each line is one read-only command (or file read) and a condition: print one short line under the report table only when it fails. Keep the script and the report table untouched. Pick from what fits this project:
- has a gate → `{{GATE_CMD}}` passes on the base branch;
- research project → `{{PY}} .agents/tools/check_adr.py --reports <the report/paper paths>` prints `OK`;
- external tracker is not `none` → `{{PY}} .agents/tools/sync_plan.py push` shows no drift;
- a task is `done` but its `review` is still `pending`;
- an ADR is `proposed` while tasks that `depends` on its task are in progress;
- docs-only → no gate line; check instead that every `mr` link in `plan.csv` of a done task is filled.
Add to `AGENTS.md`, under "Working rules": `8. Standup: /plan-check compares plan.csv with git and every MR/PR, says on or behind schedule, and shows who blocks whom. Record a dependency with {{PY}} .agents/tools/plan.py set-deps <id> --depends "<id>;<id>".` and under "Reading the team record": `- Who blocks whom: depends and adr columns of plan.csv. /plan-check prints it.`
Tell the user the report layout is in `.agents/plan-check/templates/plan-check.<lang>.md` and that a token in `PLAN_CHECK_TOKEN` (or `GITLAB_TOKEN` / `GITHUB_TOKEN`) makes MR open/closed state exact.

Adapt `done.md` (any variant): docs-only → delete step 2. Not in git (shared drive) → keep only steps 1, 5, 6, 7 and put the file link in the `mr` column. Copy the `done` command only for tools in use; if the tool has no custom commands, put the steps in `AGENTS.md` instead.

## Step 5 — Verify and report

1. Run `{{PY}} .agents/tools/check_adr.py` (must print `OK`) and `{{PY}} .agents/tools/plan.py list` (must print the example row). Fix failures.
2. `grep -rn "{{" AGENTS.md .agents .claude .cursor .github .opencode` must find nothing.
3. Tracker not `none`: tell the user which TODO in `sync_plan.py` is left and which environment variables it needs.
4. If `/plan-check` was installed: no `<!-- PROJECT-CHECKS -->` marker may remain, and `{{PY}} .agents/plan-check/plan_check.py --no-fetch` must print a report.
5. Tell the user in a few lines: what was created, the four axes, how to close a task (`/done <id>`), suggested first commit `chore: add agent governance scaffold`. Do not commit.
6. Several people: each reads `AGENTS.md` and `.agents/roles.md` first; `plan.csv` shows who does what, how far, reviewed or not.

## Step 6 — Score and report (helps improve this scaffold)

1. From the project root run `{{PY}} <folder-of-init.md>/tools/score_init.py . --agent "<your tool name>" --model "<your model id>" --write`. Fix any failed check you can fix, then re-run.
2. Open `.agents/state/init-report.md` (git-ignored) and fill the **Self-report** section honestly and briefly: what did not work as written, what was ambiguous, what you changed. No secrets, no private project content.
3. Tell the user the score and that the report can be posted as an issue at the agent-gov repo ("Init report" template) to help improve it. Never post it yourself.

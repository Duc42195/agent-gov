# init.md — bootstrap or upgrade agent governance in a project

**You are an AI coding agent. Follow this file step by step.** It gives a project one rulebook (`AGENTS.md`), one task list (`plan.csv`), one decision log and a small knowledge base, so several people and several AI tools stay consistent.

Ground rules:
- Ask the user in the language they write in. Ask once, in one batch, and only what you could not learn from the project.
- Work only inside the target project: the folder you were opened in, never this folder (`$REPO`, the one holding this file). Change nothing outside the project.
- Never overwrite an existing file, never write secrets, never commit or push (at the end, say what to commit).
- Let the scripts do the copying, hashing and comparing: they cost no tokens. Read only the files a step names.

## The tools

`$REPO/scripts/gov.sh` (bash; Git Bash on Windows) or `gov.ps1` (`powershell -NoProfile -ExecutionPolicy Bypass -File ...`). This machine's settings are in `$REPO/.env`: use `gov.sh` when `AGENT_GOV_SHELL` is `bash`, `zsh`, `fish`, `git-bash` or `wsl`, `gov.ps1` when it is `powershell`, `pwsh` or `cmd`. `AGENT_GOV_PY` is the Python command (only `/plan-check` needs Python; `none` means it cannot be used). If no script can run, use the manual fallback at the end.

| Command | What it does |
|---|---|
| `gov.sh detect <project>` | prints facts about the project (manifest, git, profile, plan.csv, legacy files, gate guess) |
| `gov.sh scaffold <project> --vars FILE` | copies the templates, filled with the values in FILE; never overwrites; writes `.agents/init-manifest` |
| `gov.sh upgrade <project> [--vars FILE] [--apply]` | plans an upgrade (default) or applies it |
| `gov.sh record <project> <path>...` | after you merged `<path>.agent-gov-new` into `<path>` |
| `scripts/score.sh <project> [--write]` | checks the result |

## Step 1 — Read what exists

Run `gov.sh detect <project>`. Then:
- `manifest=yes` → this project was set up by agent-gov before: go to **Upgrade**.
- `manifest=no` and (`agents_md=yes`, or `legacy=` is not empty, or `.agents/` exists) → an older or hand-made setup: go to **Upgrade** (limited mode).
- otherwise → a new project: Steps 2–6.

## Step 2 — Confirm what you found, ask only what is missing

Build the profile from the detect output and the files (read the README or `AGENTS.md` only to word *What* and *Goal*). Show it as a short table: value and where it came from. **Ask once** about every item that is empty or doubtful, each with a default; if nothing is missing, only ask "is this right?".

| Key | Meaning | Where to infer it | Default |
|---|---|---|---|
| `WHAT`, `GOAL` | what the project is, what "done" looks like (one line each) | README, `AGENTS.md` | ask |
| `STACK` | tech stack | manifests (`package.json`, `pyproject.toml`, `go.mod`...) | `docs only` |
| `IS_RESEARCH` | experiments, results, a paper? (`yes`/`no`) | README, folders like `paper/`, `experiments/` | `no` |
| `TASK_KEY` | task id prefix | `task_prefix` in detect, ids in `plan.csv` | `TASK` |
| `GIT_HOST`, `DEFAULT_BRANCH` | GitHub/GitLab/none, branch | `git_host`, `default_branch` | detected |
| `GATE_CMD` | test/lint command (empty for docs only) | `gate_guess`, Makefile, CI | empty |
| `EXTERNAL_TRACKER` | `jira`, `gsheet`, `excel` or `none` | ask only if the team mentions one | `none` |
| `AGENTS` | AI tools used, comma list of `claude`, `cursor`, `copilot`, `gemini`, `opencode` | `agent_dirs` | `claude` |
| `ROLE_NAME`, `ROLE`, `ROLE_OWNS` | the first person; more people go in `roles.md` later | `git_user` | git user, `maintainer`, `everything` |
| `PLAN_CHECK` | want `/plan-check` (standup report: on or behind schedule, who blocks whom)? Only if the project uses git with MRs/PRs | | `no` |

`PY` and `PLAN` are set by the script from `.env`. The team is more than one person? Ask who, and which role each (`maintainer`, `dev`, `reviewer`, `qa`, `pm`, `researcher`, `writer`).

## Step 3 — Confirm, then write the values

Show the finished profile and the list of files to be created. Get one yes. Write the values as `KEY=VALUE` lines (one line each) to `<project>/.agents/state/init-vars.env`.

## Step 4 — Scaffold

Run `gov.sh scaffold <project> --vars <project>/.agents/state/init-vars.env`. Read its output:
- `EXISTS <file>`: the project already had that file, so it was kept. For `AGENTS.md`, merge in the sections it lacks (Profile, Working rules, Knowledge capture, Decision integrity), keeping the user's content. For `plan.csv`, keep every row and bring the columns to the header in `templates/plan.csv` (a task list in another format: ask first).
- `UNSET <file> {{X}}`: a value was missing; fix it in the vars file and the file.
- Then do the parts only you can do: add the team rows to `.agents/roles.md`; add tasks the user named to `plan.csv` (else leave the example row and say so); if `PLAN_CHECK=yes`, fill **`## Standup checks`** in `.agents/wiki/working-process.md` with 3 to 6 bullet lines that fit the project (read-only checks, see the examples there); if a tracker is used, note in `working-process.md` how to update it.
- Do not hand-edit other generated files: later upgrades compare them with the template.

## Step 5 — Verify

Run `scripts/score.sh <project>`. Fix what fails and run it again. Tell the user in a few lines: what was created, how to close a task (`/done <id>`), and the suggested first commit `chore: add agent governance scaffold`. Several people: each reads `AGENTS.md` and `.agents/roles.md` first.

## Step 6 — Report (helps improve this scaffold)

Run `scripts/score.sh <project> --agent "<your tool>" --model "<your model id>" --write`, fill the **Self-report** in `.agents/state/init-report.md` honestly and briefly (what did not work, what was ambiguous, what you changed; no secrets), and tell the user it can be posted as an issue at the agent-gov repo. Never post it yourself.

## Upgrade

1. Run `gov.sh upgrade <project>` (a dry run). Summarise it in at most ten lines and ask the user to apply it. Meaning of the lines: `ADD` new file, `UPDATE` replace an untouched file, `REMOVE` delete an untouched file that agent-gov dropped, `CONFLICT` the user changed it and the template changed, `ORPHAN` dropped by agent-gov but changed by the user (kept), `UNKNOWN`/`NEEDS-VARS` no manifest, so it cannot tell. Files agent-gov does not own (`record.md`, `action-history.md`, the user's own notes) are never touched.
2. After the user agrees, run it again with `--apply`. **Limited mode** (no manifest, you saw a WARNING): offer to build a vars file from `detect` and the `AGENTS.md` profile (confirm the values) and run `upgrade ... --vars FILE --apply`, which fills `NEEDS-VARS` files and creates the manifest so the next upgrade is complete.
3. For each `CONFLICT`: compare `<file>` and `<file>.agent-gov-new`, bring the new parts into the user's file keeping their content, then run `gov.sh record <project> <file>`.
4. Do the **`Migrate:`** lines of `$REPO/CHANGELOG.md` for every version newer than the manifest's `version` (no manifest: from `0.8.1`). They are for you: they move content from old files to new ones (for example ADRs into `decisions-log.md`, a custom `record.md` into the wiki). Read only the files named, copy or summarise the content into the new place, ask before anything bigger than a few paragraphs, and **never delete the old file without asking**.
5. Run `scripts/score.sh <project>` and report what changed.

## Manual fallback (no script can run)

Say that this loses the manifest and automatic upgrades. Copy every file under `$REPO/templates/` to the same path in the project, never overwriting: `pointer.md` becomes `.github/copilot-instructions.md` (Copilot) and `GEMINI.md` (Gemini); `gitignore.append` lines are appended to `.gitignore`; skip `.agents/plan-check/` and the `plan-check` commands unless `PLAN_CHECK=yes`; copy only the `.claude/`, `.cursor/`, `.github/`, `.opencode/` command files of the tools in use. Replace every `{{KEY}}` with the value from Step 2 (`PY` = the Python command; `PLAN` = `bash .agents/tools/plan.sh` or `powershell -NoProfile -File .agents/tools/plan.ps1`). No `{{` may remain.

# Changelog

Newest first. Heading format `## X.Y.Z — YYYY-MM-DD` is read by the upgrade mode of `init.md`.
Lines starting with `Upgrade:` tell an already-scaffolded project what to change by hand or by agent.
Version numbers follow the rule in the README ("Releasing"): patch = a fix that only replaces a script, minor = a feature or a change to files the project owns.

## 0.9.0 — 2026-10-03
Bigger release: installer scopes, a real upgrade path, bash instead of Python, ADRs removed. Projects keep working; `/project-init` brings them along.

Install
- `install.sh` / `install.ps1` / `install.cmd` have two scopes with a hard boundary: user-wide (default) writes only under your home folder; `--project` (`-Project`) writes only into the current folder and never touches your home. They no longer delete across scopes: a second copy only produces a warning, and `--uninstall` removes the copy you choose. A user-wide `--agent claude` still installs `claude-delete-session`; without `jq` it prints the settings rule instead of editing `settings.json` (no embedded Python any more).
- The installer records OS, terminal and Python command in `<agent-gov>/.env`; the README says which command to run for which terminal.
- Removed: all update checking (`--update` / `-Update` and the `git fetch` line in the generated command). Update the tool with `git pull`.
- The generated command works only on the project folder and does not mention or call anything user-wide. Copilot prompt files use `agent: agent` (not `mode:`). OpenCode is in the support list ([docs/agents.md](docs/agents.md)), with how well each agent was checked.

Upgrade engine
- `scripts/gov.sh` (and `gov.ps1`): `detect`, `scaffold`, `upgrade`, `record`. `.agents/init-manifest` records, per file, the hash of the template last taken. `upgrade` plans first (dry run): `ADD`, `UPDATE` (untouched file), `REMOVE` (a dropped template you never changed), `CONFLICT` (you changed it and the template changed: yours is kept, the new one is written as `<file>.agent-gov-new`), `ORPHAN`, `KEEP`. Files agent-gov does not own are never touched. A project with no manifest runs in limited mode using the templates of the released tags. The decision is made from the files, not from the version number, so a project is no longer skipped because it already "is" the latest version.
- `init.md` rewritten and shorter: `gov.sh detect` gathers facts, the agent shows the profile it assembled and asks only about what is missing; scripts do the copying (no agent tokens); upgrading is part of `/project-init`.

Removed or replaced
- ADRs are gone: decisions live in `.agents/wiki/decisions-log.md` (entries with `Topic:`, `Supersedes:`, and `Result:` for experiment results). Removed: `.agents/adr/`, `check_adr.py`, the `adr` column of `plan.csv`. The automatic run-id check for research reports no longer exists (the rule stays in `AGENTS.md`).
- `plan.py` is replaced by `plan.sh list` (`plan.ps1`, `plan.cmd`); there are no edit commands any more: agents edit the cell in `plan.csv`. `sync_plan.py` (an unfinished stub) is removed. `score_init.py` is now `scripts/score.sh` (`score.ps1`).
- Python is only needed for `/plan-check` and `claude-delete-session`.
- `/plan-check`: no more `Project checks` block inside the command; it reads `## Standup checks` in `.agents/wiki/working-process.md`. The table shows today's tasks first when on track; when behind schedule: late and blocking, late, blocking, then today's tasks and the rest. ADR logic removed.
- Folders: `tools/` split into `bin/` (machine tools) and `scripts/` (maintainer scripts); `docs/agents.md`, `docs/windows.md` added; README rewritten.

Upgrade (run `/project-init` in the project; it does these by script)
- Replace untouched generated files and add new ones (`.agents/tools/plan.sh`, `plan.ps1`, `plan.cmd`, the new `AGENTS.md`/commands as `.agent-gov-new` where you changed them); remove the untouched old `.agents/adr/README.md`, `0000-template.md`, `tools/check_adr.py`, `plan.py`, `sync_plan.py`.
- Write `.agents/init-manifest` (from this release on, the manifest replaces `.agents/init-version`).

Migrate (for the agent: copy or summarise, ask before anything big, never delete the old file without asking)
- Migrate: each `.agents/adr/NNNN-*.md` becomes an entry in `.agents/wiki/decisions-log.md` (Topic, Decision, Why, `Result:` for `Type: result`, `Supersedes:` when superseded). Keep the ADR files until the user agrees to delete them.
- Migrate: if `plan.csv` has an `adr` column with values, put them in `notes`, then drop the column.
- Migrate: if `/plan-check` is installed, move the lines of the `## Project checks` block of your plan-check command to `## Standup checks` in `.agents/wiki/working-process.md` (bullet lines), then take the new command.
- Migrate: `AGENTS.md`: replace commands that call `plan.py` by "edit the cell, then `<plan command> list`", and the ADR rules by the decision-log rules (the new text arrives as `AGENTS.md.agent-gov-new`).
- Migrate: projects from 0.3.x with their own `record.md` / `action-history.md`: decisions into `decisions-log.md`, process gotchas into `working-process.md`; keep the originals.
- Migrate: if a tracker was synced with `sync_plan.py`, write how to update it in `working-process.md`.

## 0.8.1 — 2026-10-03
- Fix `claude-delete-session`: it crashed with `_curses.error: addnwstr() returned ERR` (it wrote into the bottom-right cell of the screen). Rewritten to behave like `claude -r`: it lists the sessions of the current folder, type to search (Vietnamese and any word order work), `Ctrl+A` all projects, `Ctrl+B` current branch, `Ctrl+V` preview, `Tab` mark, `Enter` delete after y/N, `Esc` quit.
- It now reads the real session title (the latest `ai-title` record), no longer lists subagent transcripts as sessions, deletes the session's data folder with its file, warns when a session was modified in the last 5 minutes, and survives tiny or very wide terminals and `Ctrl+C`.
- README: in bash `!claude-delete-session` repeats an earlier command (that is why it ran `claude -r...`); the `!` is for the Claude Code prompt.
- The smoke test drives the tool in a pseudo terminal. The Windows `.ps1` is unchanged (old all-projects list).
- Upgrade: none for projects. Re-copy `tools/claude-delete-session` to `~/.local/bin` (run `install.sh --agent claude`).

## 0.8.0 — 2026-10-03
- Windows installer: `install.cmd` / `install.ps1` (`-Agent`, `-Project`, `-Update`), same agents and Python detection as `install.sh` (`py -3`, `python`, `python3`). For `claude` it copies `tools\claude-delete-session.ps1` to `~\.local\bin` and does not edit `settings.json`. Not yet tested on a real Windows machine.
- Fix: the user-wide OpenCode command directory is `~/.config/opencode/commands/`, not `~/.opencode/commands/` (0.7.0 wrote to the wrong place, so OpenCode never saw `/project-init`). The project directory `.opencode/commands/` was already right.
- Fix for Windows: `.gitattributes` keeps `*.sh` and `*.py` as LF (CRLF from `git clone` with autocrlf breaks bash), and `tools/claude-delete-session.ps1` now has a UTF-8 BOM (Windows PowerShell 5.1 misread its non-ASCII characters).
- Tests: the smoke test now checks the OpenCode paths, the `/plan-check` command of every agent (it was red at 0.7.0), and statically checks the Windows scripts.
- Upgrade: if you installed OpenCode with 0.7.0, run `install.sh --agent opencode` again and delete `~/.opencode/commands/project-init.md`.
- Upgrade: write `0.8.0` to `.agents/init-version`.

## 0.7.0 — 2026-10-01
- Added OpenCode as a supported agent: `install.sh --agent opencode` installs `/project-init` to `~/.opencode/commands/` (user-wide) or `.opencode/commands/` (`--project`). OpenCode is included in `--all` and in the interactive prompt.
- New templates: `templates/.opencode/commands/done.md` and `templates/.opencode/commands/plan-check.md`.
- `init.md` question 8 now lists OpenCode; scaffold table includes `.opencode/commands/` rows.
- `score_init.py` checks `.opencode/commands/` for `/done` and `/plan-check`.
- Upgrade: run `install.sh --agent opencode` to add the OpenCode command to an existing install; write `0.7.0` to `.agents/init-version`.

## 0.6.0 — 2026-10-01
- Removed the automatic update check: `.agents/tools/check_update.py` and rule 8 of `AGENTS.md` are gone (it depended on the agent choosing to run it, and did not fire reliably). Upgrading is manual: run `/project-init` in a project, or `install.sh --update` for the clone. `.agents/init-version` stays so `/project-init` can detect an old scaffold.
- `AGENT_GOV_NO_UPDATE_CHECK` and `AGENT_GOV_REMOTE` no longer exist. The `/plan-check` rule in `init.md` is now rule 8 instead of 9.
- Upgrade: delete `.agents/tools/check_update.py`, delete rule 8 ("At session start run ... check_update.py") from `AGENTS.md` (renumber a `/plan-check` rule 9 to 8), delete `.agents/state/update-check*`.
- Upgrade: write `0.6.0` to `.agents/init-version`.

## 0.5.0 — 2026-10-01
- Python detection: `install.sh` finds Python 3.8+ (`python3`, `python`, `py -3`) and writes it into the `/project-init` command, with a warning when there is none. Init records it as the `Python:` line of `AGENTS.md` and writes that interpreter into every command (`{{PY}}`), so no command says a bare `python`.
- `/plan-check` replies `Python 3.8+ not found. Install it, then run /project-init again...` when Python is missing; `/done` falls back to editing the row by hand and says so; `AGENTS.md` rule 8 says so once.
- `score_init.py` checks the `Python:` line and flags a bare `python` command when the project's interpreter is another one.
- Upgrade: add `- Python: <cmd>` to the Profile of `AGENTS.md` (detect it as in `init.md`), and replace every `python .agents/...` in `AGENTS.md`, `/done`, `/plan-check` and the ADR README with `<cmd> .agents/...`.
- Upgrade: add the missing-Python sentence to step 1 of each `plan-check` command (take it from the template); write `0.5.0` to `.agents/init-version`.

## 0.4.0 — 2026-10-01
- `check_update.py` runs at every session start with no rate limit and no state file (the 0.3.1 hourly/daily limits are gone). It stays silent when current or offline.
- `install.sh --agent claude` (user-wide) now installs `claude-delete-session` by default; the `--with` option is removed (it now fails with `unknown option`). `--project` and other agents do not install it.
- README rewritten: rules merged into the description, optional pieces merged into "Use it".
- Upgrade: replace `.agents/tools/check_update.py` with the template version and delete `.agents/state/update-check*`.
- Upgrade: write `0.4.0` to `.agents/init-version`.

## 0.3.1 — 2026-10-01
- Fix: update notices were hidden for 7 days after any check, even a check that said "up to date", so a release made right after was missed. `check_update.py` now asks at most once an hour (a failed try also waits an hour), repeats the same notice at most once a day, and keeps its state in `.agents/state/update-check.json`.
- Upgrade: replace `.agents/tools/check_update.py` with the template version (this is the fix). Delete the old `.agents/state/update-check` file.

## 0.3.0 — 2026-10-01
- Renamed agent-init to agent-gov: repo, URLs, default clone folder `~/.agent-gov`, env vars `AGENT_INIT_*` became `AGENT_GOV_*` (`AGENT_GOV_NO_UPDATE_CHECK`, `AGENT_GOV_REMOTE`).
- `/plan-check` standup command (optional, question 10 in `init.md`): plan vs git vs MR/PR, who blocks whom. Init tailors its `Project checks` block to the project. Docs in `docs/plan-check.md`.
- `plan.csv` gets `depends` and `adr` columns; `plan.py set-deps`.
- `tools/claude-delete-session` (+ `.ps1`) and `install.sh --with delete-session`.
- `score_init.py` checks plan-check when installed.
- Upgrade: replace `.agents/tools/check_update.py` with the template version (new repo URL and `AGENT_GOV_*` names).
- Upgrade: in `plan.csv` insert two empty columns `depends`,`adr` before `notes`; replace `.agents/tools/plan.py` with the template version.
- Upgrade: write `0.3.0` to `.agents/init-version`. Offer `/plan-check` as in `init.md` question 10.

## 0.2.0 — 2026-10-01
- Templates split out of `init.md` into `templates/`; script files are real files.
- `install.sh --agent` for claude, cursor, copilot, codex, gemini, other; `--update` pulls the latest.
- `tools/score_init.py` and the init report / issue template.
- `plan.csv` moved to the project root.
- Update notifications: `VERSION`, `.agents/init-version`, `.agents/tools/check_update.py`.
- Upgrade: move `.agents/plan.csv` to `plan.csv`.
- Upgrade: replace `.agents/tools/plan.py` with the template version (it reads `plan.csv` at the root).
- Upgrade: add `.agents/tools/check_update.py` and the session-start rule in `AGENTS.md`; write `0.2.0` to `.agents/init-version`.

## 0.1.0 — initial
- Single `init.md` with inline templates.

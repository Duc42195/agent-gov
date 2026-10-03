# Changelog

Newest first. Heading format `## X.Y.Z — YYYY-MM-DD` is read by the upgrade mode of `init.md`.
Lines starting with `Upgrade:` tell an already-scaffolded project what to change by hand or by agent.
Version numbers follow the rule in the README ("Releasing"): patch = a fix that only replaces a script, minor = a feature or a change to files the project owns.

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

# Changelog

Newest first. Heading format `## X.Y.Z — YYYY-MM-DD` is read by the upgrade mode of `init.md`.
Lines starting with `Upgrade:` tell an already-scaffolded project what to change by hand or by agent.
Version numbers follow the rule in the README ("Releasing"): patch = a fix that only replaces a script, minor = a feature or a change to files the project owns.

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

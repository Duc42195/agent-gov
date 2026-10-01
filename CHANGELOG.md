# Changelog

Newest first. Heading format `## X.Y.Z — YYYY-MM-DD` is read by `check_update.py`.
Lines starting with `Upgrade:` tell an already-scaffolded project what to change by hand or by agent.

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

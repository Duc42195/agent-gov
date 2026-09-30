# Changelog

Newest first. Heading format `## X.Y.Z — YYYY-MM-DD` is read by `check_update.py`.
Lines starting with `Upgrade:` tell an already-scaffolded project what to change by hand or by agent.

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

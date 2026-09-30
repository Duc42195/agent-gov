# agent-init

One file, `init.md`, that an AI coding agent follows to set up a shared way of working in a new project. It suits projects with several people and several AI tools.

The agent reads what already exists, asks about the system, the goal, the stack and the team (if the project is empty), then creates:

| Axis | What you get |
|---|---|
| 1. Context | `AGENTS.md` (one rulebook), `.agents/adr/` (one accepted decision per topic), `.agents/wiki/` (lessons that accumulate), `.agents/plan.csv` (the plan) |
| 2. Action | `/done <task-id>`: gate, commit, open MR/PR, flip status in `plan.csv`. Never merges. |
| 3. External | `.agents/tools/sync_plan.py`: stub adapter to mirror `plan.csv` to Jira / Google Sheets / Excel |
| 4. Team | `.agents/roles.md` plus the `owner`, `status`, `mr`, `reviewer`, `review` columns of `plan.csv`: who does what, how far, is it right |

No third-party packages. The helper scripts use only the Python standard library.

## Use it

**Recommended: GitHub template repo.**
1. Publish this repo, then in *Settings* tick *Template repository*.
2. For each new project click *Use this template*, clone the new repo, open Claude Code in it.
3. Type `/project-init`.

**Add to an existing project.** Copy `init.md`, `templates/` and `.claude/commands/project-init.md` into it, then type `/project-init`.

**Other AI tools (Cursor, Copilot, ...).** `init.md` and `templates/` are needed (`/done` variants for Cursor and Copilot are included). Tell the agent: "Read and follow init.md."

**Use it in every project without copying.** Put `init.md` and `templates/` in `~/.claude/templates/` and `project-init.md` in `~/.claude/commands/`.

`/init` is a built-in Claude Code command that creates `CLAUDE.md`, so this repo uses the name `/project-init`.

## Working rules the scaffold enforces

- `AGENTS.md` is the only rulebook. `CLAUDE.md` is one line that imports it.
- `plan.csv` is the source of truth for tasks. Git and the MR/PR state are the truth for "done".
- One topic has exactly one accepted ADR; a new decision supersedes the old one instead of contradicting it. `check_adr.py` checks numbering, the index and topics.
- For research projects, the chosen result of an experiment is an ADR with a run-id. Every table and figure in a report must match the accepted run; `check_adr.py --reports` flags the ones that do not.
- Whatever an agent learns (decision, fixed error, open question, gotcha) is appended to the wiki in the same session.

## Files

```
init.md                            the procedure the agent follows (short)
templates/                         every file the agent copies, mirroring target paths
  AGENTS.md, CLAUDE.md, pointer.md, gitignore.append
  .agents/                         roles, plan.csv, adr/, wiki/, tools/*.py
  .claude/ .cursor/ .github/       /done command per AI tool
tests/smoke_test.py                scaffolds into a temp dir and runs the checks
.claude/commands/project-init.md   one-line command: read init.md and follow it
```

## Test

`python tests/smoke_test.py` scaffolds the templates into an empty folder, runs `plan.py`, `sync_plan.py` and `check_adr.py` (including duplicate-topic and stale run-id detection) and fails on leftover placeholders. Run it after every change to `templates/`.

Every question in `init.md` has a default, so the user can answer "defaults" for a quick setup.

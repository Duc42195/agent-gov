# agent-init

One file, `init.md`, that an AI coding agent follows to set up a shared way of working in a new project. It suits projects with several people and several AI tools.

The agent reads what already exists, asks about the system, the goal, the stack and the team (if the project is empty), then creates:

| Axis | What you get |
|---|---|
| 1. Context | `AGENTS.md` (one rulebook), `.agents/adr/` (one accepted decision per topic), `.agents/wiki/` (lessons that accumulate), `plan.csv` (the plan) |
| 2. Action | `/done <task-id>`: gate, commit, open MR/PR, flip status in `plan.csv`. Never merges. |
| 3. External | `.agents/tools/sync_plan.py`: stub adapter to mirror `plan.csv` to Jira / Google Sheets / Excel |
| 4. Team | `.agents/roles.md` plus the `owner`, `status`, `mr`, `reviewer`, `review` columns of `plan.csv`: who does what, how far, is it right |

No third-party packages. The helper scripts use only the Python standard library.

## Use it

`install.sh` writes the `/project-init` command for the agent(s) you name: `claude`, `cursor`, `copilot`, `codex`, `gemini`, `all`, or `other` (no command file; you tell the agent to read `init.md`). Without `--agent` it asks.

**Every project, once per machine:**
```
git clone https://github.com/Duc42195/agent-init.git ~/.agent-init && ~/.agent-init/install.sh --agent claude
```

**One project only** (run from the project root; add `agent-init/` to `.gitignore` or delete it afterwards):
```
git clone https://github.com/Duc42195/agent-init.git && agent-init/install.sh --agent claude --project
```

Then restart the agent and type `/project-init`. Several agents: `--agent claude,cursor`.

| Agent | User-wide | `--project` |
|---|---|---|
| claude | `~/.claude/commands/` | `.claude/commands/` |
| cursor | `~/.cursor/commands/` | `.cursor/commands/` |
| copilot | not supported | `.github/prompts/` |
| codex | `~/.codex/prompts/` | not supported |
| gemini | `~/.gemini/commands/` | `.gemini/commands/` |
| other | no file: tell the agent "Read and follow /path/to/agent-init/init.md" | same |

**New projects from a template.** Tick *Template repository* in the GitHub settings, click *Use this template* per project; `.claude/commands/project-init.md` finds `./init.md` itself.

`/done` variants for Cursor and Copilot are in `templates/`.

`/init` is a built-in Claude Code command that creates `CLAUDE.md`, so this repo uses the name `/project-init`.

## Other agents, and helping improve this

Only Claude Code is tested here. If you use another agent, **please [raise an issue](https://github.com/Duc42195/agent-init/issues/new?template=init-report.yml)** with how it went, good or bad.

The last step of `init.md` makes the agent measure itself: `tools/score_init.py` checks the result objectively (files, leftover placeholders, tools run, profile filled, `/done` present) and writes `.agents/state/init-report.md` (git-ignored). The agent then fills a short self-report: what it could not follow, what was ambiguous, what it changed. Review that file, remove anything private, and paste it into the *Init report* issue. Nothing is sent automatically.

You can also score any project yourself: `python tools/score_init.py /path/to/project --agent NAME --model NAME`.

## Working rules the scaffold enforces

- `AGENTS.md` is the only rulebook. `CLAUDE.md` is one line that imports it.
- `plan.csv` is the source of truth for tasks. Git and the MR/PR state are the truth for "done".
- One topic has exactly one accepted ADR; a new decision supersedes the old one instead of contradicting it. `check_adr.py` checks numbering, the index and topics.
- For research projects, the chosen result of an experiment is an ADR with a run-id. Every table and figure in a report must match the accepted run; `check_adr.py --reports` flags the ones that do not.
- Whatever an agent learns (decision, fixed error, open question, gotcha) is appended to the wiki in the same session.

## Files

```
install.sh                         installs the /project-init command (global or per project)
init.md                            the procedure the agent follows (short)
templates/                         every file the agent copies, mirroring target paths
  AGENTS.md, CLAUDE.md, pointer.md, gitignore.append
  plan.csv                         the plan, at the project root
  .agents/                         roles, adr/, wiki/, tools/*.py
  .claude/ .cursor/ .github/       /done command per AI tool
tools/score_init.py                scores a scaffolded project, writes the init report
tests/smoke_test.py                scaffolds into a temp dir and runs the checks
.claude/commands/project-init.md   one-line command: read init.md and follow it
```

## Test

`python tests/smoke_test.py` scaffolds the templates into an empty folder, runs `plan.py`, `sync_plan.py` and `check_adr.py` (including duplicate-topic and stale run-id detection) and fails on leftover placeholders. Run it after every change to `templates/`.

Every question in `init.md` has a default, so the user can answer "defaults" for a quick setup.

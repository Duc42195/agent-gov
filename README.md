# agent-gov

One file, `init.md`, that an AI coding agent follows to set up a shared way of working in a new project. It suits projects with several people and several AI tools.

The agent reads what already exists, asks about the system, the goal, the stack and the team (if the project is empty), then creates:

| Axis | What you get |
|---|---|
| 1. Context | `AGENTS.md` (one rulebook), `.agents/adr/` (one accepted decision per topic), `.agents/wiki/` (lessons that accumulate), `plan.csv` (the plan) |
| 2. Action | `/done <task-id>`: gate, commit, open MR/PR, flip status in `plan.csv`. Never merges.<br>Optional `/plan-check`: standup report, see [docs/plan-check.md](docs/plan-check.md). |
| 3. External | `.agents/tools/sync_plan.py`: stub adapter to mirror `plan.csv` to Jira / Google Sheets / Excel |
| 4. Team | `.agents/roles.md` plus the `owner`, `status`, `mr`, `reviewer`, `review`, `depends`, `adr` columns of `plan.csv`: who does what, how far, is it right, who blocks whom |

No third-party packages. The helper scripts use only the Python standard library. Every question in `init.md` has a default, so you can answer "defaults" for a quick setup.

**The rules the scaffold enforces**

- `AGENTS.md` is the only rulebook. `CLAUDE.md` is one line that imports it.
- `plan.csv` is the source of truth for tasks. Git and the MR/PR state are the truth for "done".
- One topic has exactly one accepted ADR; a new decision supersedes the old one instead of contradicting it. `check_adr.py` checks numbering, the index and topics.
- For research projects, the chosen result of an experiment is an ADR with a run-id. Every table and figure in a report must match the accepted run; `check_adr.py --reports` flags the ones that do not.
- Whatever an agent learns (decision, fixed error, open question, gotcha) is appended to the wiki in the same session.
- At the start of every session the agent runs `check_update.py`, which tells you when a newer agent-gov exists (see [Updates](#updates)).

## Use it

`install.sh` writes the `/project-init` command for the agent(s) you name: `claude`, `cursor`, `copilot`, `codex`, `gemini`, `all`, or `other` (no command file; you tell the agent to read `init.md`). Without `--agent` it asks.

**Every project, once per machine:**
```
git clone https://github.com/Duc42195/agent-gov.git ~/.agent-gov && ~/.agent-gov/install.sh --agent claude
```

**One project only** (run from the project root; add `agent-gov/` to `.gitignore` or delete it afterwards):
```
git clone https://github.com/Duc42195/agent-gov.git && agent-gov/install.sh --agent claude --project
```

Then restart the agent and type `/project-init`. Several agents: `--agent claude,cursor`.

| Agent | User-wide | `--project` |
|---|---|---|
| claude | `~/.claude/commands/` | `.claude/commands/` |
| cursor | `~/.cursor/commands/` | `.cursor/commands/` |
| copilot | not supported | `.github/prompts/` |
| codex | `~/.codex/prompts/` | not supported |
| gemini | `~/.gemini/commands/` | `.gemini/commands/` |
| other | no file: tell the agent "Read and follow /path/to/agent-gov/init.md" | same |

**New projects from a template.** Tick *Template repository* in the GitHub settings, click *Use this template* per project; `.claude/commands/project-init.md` finds `./init.md` itself.

`/init` is a built-in Claude Code command that creates `CLAUDE.md`, so this repo uses the name `/project-init`.

**What else you get**

- **`/plan-check` (standup, offered by `/project-init`, question 10).** Compares `plan.csv` with git and every MR/PR, says ON TRACK or BEHIND SCHEDULE, and shows who each task blocks, in one table. Init copies it and **tailors the command to your project**: it fills a `Project checks` block with 3–6 read-only checks that fit (gate green, result ADRs match reports, tracker drift, reviews pending, ...). The script and the table template stay fixed. `/done` and `/plan-check` come in Claude Code, Cursor and Copilot variants. Details: [docs/plan-check.md](docs/plan-check.md).
- **`claude-delete-session` (Claude Code only, installed by default).** A terminal UI to find and delete old Claude Code sessions (`.jsonl` files under `~/.claude/projects`); run it as `claude-delete-session`, or `!claude-delete-session` inside Claude. A user-wide `install.sh --agent claude` copies it to `~/.local/bin` **and adds the rule `Bash(~/.local/bin/claude-delete-session)` to `~/.claude/settings.json`** so it runs without a prompt. It deletes files permanently. With `--project`, or for other agents, it is not installed. A Windows version is `tools/claude-delete-session.ps1` (not tested here, copy it yourself).

## Updates

Versions are in `VERSION` and `CHANGELOG.md`; each release lists `Upgrade:` steps for existing projects.

- **A scaffolded project** stores its version in `.agents/init-version`. `AGENTS.md` tells the agent to run `.agents/tools/check_update.py` at the start of every session. The script compares that version with `VERSION` on GitHub, prints the new changelog entries when the repo is newer, and prints nothing when you are current or offline. `check_update.py --force` also says why when it cannot answer. It changes no files. Opt out with `AGENT_GOV_NO_UPDATE_CHECK=1`. To upgrade, run `/project-init` in the project: it detects the old version, applies the `Upgrade:` steps and asks before touching files you modified.
- **Your clone of this repo:** `/project-init` first runs `git fetch` on it and tells you if it is behind. Update with `~/.agent-gov/install.sh --update` (fast-forward only, prints what changed).

Releasing: bump `VERSION` and add the matching top entry to `CHANGELOG.md` (the smoke test checks they agree).

## Other agents, and helping improve this

Only Claude Code is tested here. If you use another agent, **please [raise an issue](https://github.com/Duc42195/agent-gov/issues/new?template=init-report.yml)** with how it went, good or bad.

The last step of `init.md` makes the agent measure itself: `tools/score_init.py` checks the result objectively (files, leftover placeholders, tools run, profile filled, `/done` present) and writes `.agents/state/init-report.md` (git-ignored). The agent then fills a short self-report: what it could not follow, what was ambiguous, what it changed. Review that file, remove anything private, and paste it into the *Init report* issue. Nothing is sent automatically.

You can also score any project yourself: `python tools/score_init.py /path/to/project --agent NAME --model NAME`.

## Files

```
VERSION, CHANGELOG.md              release version and upgrade notes
install.sh                         installs /project-init (+ claude-delete-session for a user-wide claude install)
init.md                            the procedure the agent follows (short)
templates/                         every file the agent copies, mirroring target paths
  AGENTS.md, CLAUDE.md, pointer.md, gitignore.append
  plan.csv                         the plan, at the project root
  .agents/                         roles, adr/, wiki/, tools/*.py (incl. check_update.py), init-version
  .agents/plan-check/              standup script and report templates (optional)
  .claude/ .cursor/ .github/       /done and /plan-check commands per AI tool
docs/plan-check.md                 how /plan-check works and how to change its report
tools/score_init.py                scores a scaffolded project, writes the init report
tools/claude-delete-session{,.ps1} session cleaner
tests/smoke_test.py                scaffolds into a temp dir and runs the checks
.claude/commands/project-init.md   one-line command: read init.md and follow it
```

## Test

`python tests/smoke_test.py` scaffolds the templates into an empty folder, runs `plan.py` (including `set-deps`), `sync_plan.py`, `check_adr.py` (duplicate-topic and stale run-id detection) and `plan_check.py` on a throwaway git repo, tests `check_update.py`, `install.sh --update` and the delete-session install, and fails on leftover placeholders or the old name. Run it after every change to `templates/`.

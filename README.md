# agent-gov

A way for an AI coding agent to set up a shared way of working in a project, and keep it up to date. You install one command (`/project-init`); the agent then reads what the project already has, confirms it with you, asks only what is missing, and scaffolds the rest. It suits projects with several people and several AI tools.

| Axis | What you get |
|---|---|
| 1. Context | `AGENTS.md` (one rulebook), `plan.csv` (the plan), `.agents/wiki/` (decisions log, lessons, open questions, working process) |
| 2. Action | `/done <task-id>`: gate, commit, open MR/PR, update the row in `plan.csv`. Never merges. Optional `/plan-check`: standup report |
| 3. Team | `.agents/roles.md` plus the `owner`, `status`, `mr`, `reviewer`, `review`, `depends` columns of `plan.csv`: who does what, how far, is it right, who blocks whom |
| 4. Upgrade | `scripts/gov.sh` keeps the project in step with new releases without overwriting what you changed |

**The rules the scaffold enforces**

- `AGENTS.md` is the only rulebook. `CLAUDE.md` is one line that imports it.
- `plan.csv` is the source of truth for tasks. Git and the MR/PR state are the truth for "done".
- One topic has one current decision in `decisions-log.md`; a new decision supersedes the old one instead of contradicting it. For research projects every number in a report cites the run-id of the chosen result.
- Whatever an agent learns (decision, fixed error, open question, gotcha) is appended to the wiki in the same session.

No third-party packages. The core is plain `bash` (`install.sh`, `scripts/`, `plan.sh`), with PowerShell/cmd versions for Windows. Python 3.8+ is needed only for `/plan-check` and `claude-delete-session`.

## Install

Clone anywhere, then run the installer for **your terminal** and the agent(s) you use (`claude`, `cursor`, `copilot`, `gemini`, `opencode`, `all`):

| You use | Run |
|---|---|
| bash, zsh, fish on Linux or macOS; WSL; Git Bash | `git clone https://github.com/Duc42195/agent-gov.git ~/.agent-gov && ~/.agent-gov/install.sh --agent claude` |
| PowerShell or cmd.exe on Windows | `git clone https://github.com/Duc42195/agent-gov.git $HOME\.agent-gov`, then on its own line `& $HOME\.agent-gov\install.cmd -Agent claude` |

Restart the agent and type `/project-init` in a project. Details for Windows: [docs/windows.md](docs/windows.md).

- **User-wide (default)** writes only under your home folder, so `/project-init` works in every project. **One project only:** from the project's root add `--project` (`-Project`); it writes only into that folder and never touches your home. Remove with `--uninstall`. Installing both scopes makes the agent list `/project-init` twice; the installer then warns instead of deleting.
- The installer records your machine (OS, terminal, Python command) in `<agent-gov>/.env`. The agent reads it to run the right script version (`gov.sh` or `gov.ps1`) and the right Python command.
- Which agents are supported, and how well each was checked: [docs/agents.md](docs/agents.md). Other agents: tell them "Read and follow `<agent-gov>/init.md`".
- A user-wide `--agent claude` also installs `claude-delete-session` (see below).

## Use it

- **New project:** `/project-init`. The agent runs `gov.sh detect` (git, manifest, profile, `plan.csv`, gate guess), shows you the profile it assembled, asks only about what is missing, then `gov.sh scaffold` copies the templates (no agent tokens spent on copying). The last step scores the result and writes a report you can send back.
- **Project made with an older agent-gov** (even from before releases had manifests): run `/project-init` again. `gov.sh upgrade` first prints a plan: new files are added, untouched files are updated, files agent-gov dropped are removed if you never changed them, and a file you changed is never overwritten (the new version is written next to it as `<file>.agent-gov-new` for the agent to merge). Your own files (`record.md`, notes) are never touched. Moving old content (ADRs into the decisions log, a `record.md` into the wiki) is done by the agent from the `Migrate:` lines of [CHANGELOG.md](CHANGELOG.md), asking before anything big. To update this tool itself: `git -C ~/.agent-gov pull`.
- **`/plan-check` (optional, question 10 of init).** Compares `plan.csv` with git and every MR/PR and returns one table: on track (today's tasks, then the rest) or behind schedule (late tasks that also block others first, then late, then blockers, then the rest). Your own checks go under `## Standup checks` in `.agents/wiki/working-process.md`. Details: [docs/plan-check.md](docs/plan-check.md).
- **`claude-delete-session` (Claude Code only).** A terminal list like `claude -r`, for deleting: it shows the sessions of the folder you run it in, newest first; type to search, `Ctrl+A` all projects, `Ctrl+B` current git branch, `Ctrl+V` preview, `Tab` marks several, `Enter` deletes after a y/N question, `Esc` quits. It removes the session file and its data folder. Run it as `claude-delete-session` in a normal terminal, or `!claude-delete-session` at the Claude Code prompt (in bash the `!` repeats an earlier command, so do not type it there). The installer copies it to `~/.local/bin` and, if `jq` is installed, adds the rule `Bash(~/.local/bin/claude-delete-session)` to `~/.claude/settings.json` so it runs without a prompt (without `jq` it only prints the rule). Deleting is permanent. Other agents: see the "Deleting old sessions" table in [docs/agents.md](docs/agents.md).

## Other agents, and helping improve this

Only Claude Code is used here for real. If you use another agent, **please [raise an issue](https://github.com/Duc42195/agent-gov/issues/new?template=init-report.yml)** with how it went, good or bad. The last step of init runs `scripts/score.sh` (files, leftover placeholders, plan header, tools run, `/done` present, ...) and writes `.agents/state/init-report.md` (git-ignored) with a short self-report from the agent. Review it, remove anything private, and paste it into the *Init report* issue. Nothing is sent automatically. You can also run `scripts/score.sh /path/to/project --agent NAME --model NAME`.

## Files

```
init.md                        the procedure the agent follows
install.sh, install.ps1, install.cmd   install /project-init (bash / Windows)
scripts/gov.sh, gov.ps1, gov.cmd       detect, scaffold, upgrade, record
scripts/score.sh, score.ps1, score.cmd score a scaffolded project
templates/                     every file the scaffold copies, mirroring the target paths
  AGENTS.md, CLAUDE.md, plan.csv, pointer.md, gitignore.append
  .agents/                     roles, wiki/, tools/plan.{sh,ps1,cmd}, plan-check/ (optional)
  .claude/ .cursor/ .github/ .opencode/   /done and /plan-check per AI tool
bin/claude-delete-session{,.ps1}   machine tool (installed to ~/.local/bin)
docs/                          agents.md, windows.md, plan-check.md
tests/smoke_test.py            scaffolds into a temp dir and checks everything
.claude/commands/project-init.md   project-level /project-init for working inside this repo
VERSION, CHANGELOG.md          release number and upgrade notes
```

## Test and release

`python3 tests/smoke_test.py` runs the installer (both scopes), `gov.sh` (scaffold and every upgrade case), `plan.sh`, `score.sh`, `plan_check.py` on a throwaway git repo and `claude-delete-session` in a pseudo terminal, and statically checks the Windows scripts (and runs them if `pwsh` exists). Run it after every change.

**Releasing.** Bump `VERSION`, add the matching top entry to `CHANGELOG.md` (the smoke test checks they agree), commit, tag `vX.Y.Z`, push. Choose the number by what an existing project must do to upgrade:

| Bump | When | Existing projects |
|---|---|---|
| patch `0.9.1` | a bug fix; behaviour otherwise unchanged | nothing they own changes |
| minor `0.10.0` | a new feature, or a change that needs edits to files the project owns (`AGENTS.md`, `plan.csv` columns, command files) | `/project-init` upgrades them; `Migrate:` lines describe content moves |

Docs-only changes do not bump the version. We stay on `0.x` until the scaffold is stable.

# Supported agents

`install.sh` (or `install.cmd` on Windows) writes the `/project-init` command for the agent you name. After init, the rules live in `AGENTS.md`; every agent reads them, either natively or through a one-line pointer file.

| Agent | `/project-init` in the project (`--project`) | `/project-init` user-wide (default) | `/done`, `/plan-check` | How it reads the rules | Checked |
|---|---|---|---|---|---|
| **Claude Code** | `.claude/commands/` | `~/.claude/commands/` | yes, yes | `CLAUDE.md` imports `AGENTS.md` | **used for real** |
| **OpenCode** | `.opencode/commands/` | `~/.config/opencode/commands/` | yes, yes | `AGENTS.md` | paths match the docs; not run end to end |
| **GitHub Copilot** (VS Code) | `.github/prompts/*.prompt.md` | not supported | yes, yes | pointer `.github/copilot-instructions.md` | paths match the docs; not run |
| **Gemini CLI** | `.gemini/commands/*.toml` | `~/.gemini/commands/` | no, no (only `/project-init`) | pointer `GEMINI.md` | path and format match the docs; not run |
| **Cursor** | `.cursor/commands/` | `~/.cursor/commands/` | yes, yes | `AGENTS.md` (not verified) | **not confirmed**: Cursor's current docs describe skills instead; not run |
| **Codex** | not supported | `~/.codex/prompts/` | no, no | `AGENTS.md` | custom prompts are **deprecated** by Codex; not run |
| any other | no command file: tell the agent "Read and follow `<agent-gov>/init.md`" | | | `AGENTS.md` | |

Using another agent than Claude Code? **Please [raise an issue](https://github.com/Duc42195/agent-gov/issues/new?template=init-report.yml)** with how it went; the last step of init writes a report you can paste.

## Project or user-wide

- **User-wide** (default) writes only under your home folder, so `/project-init` is available in every project.
- **`--project`** (run from the project's root) writes only under that folder and nothing in your home folder.
- Installing both makes the agent list `/project-init` twice. The installer does not delete across scopes; it warns, and `install.sh --agent <name> --uninstall [--project]` removes the copy you choose. (The agent-gov repo itself ships a project-level `.claude/commands/project-init.md`, so Claude Code lists two in that folder; that is intended.)

## Deleting old sessions (from a terminal)

| Agent | How |
|---|---|
| Claude Code | `claude-delete-session` (installed by a user-wide `install.sh --agent claude`; at the Claude prompt type `!claude-delete-session`) |
| OpenCode | `opencode session list`, then `opencode session delete <sessionID>` |
| Gemini CLI | `gemini --list-sessions`, then `gemini --delete-session <index or id>`; or `/resume` and press `x` |
| Codex | no delete command in its docs; the storage location is not confirmed here |
| Cursor, Copilot | in the IDE's own chat history |

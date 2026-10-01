---
description: Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project
---
If the folder holding `init.md` is a git clone, run `git fetch --quiet` and `git status -sb` there first; if it is behind, tell the user in one line and ask to run `install.sh --update` before continuing.
Find `init.md` in the first of these that exists: `./init.md`, `./agent-gov/init.md`, `~/.claude/agent-gov/init.md`, `~/.claude/templates/init.md`. Read it and follow it step by step. Templates are in the `templates/` folder next to it.
The target is the project root (the directory Claude Code was opened in), never the folder that holds `init.md`.

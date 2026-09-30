#!/usr/bin/env bash
# Install the /project-init command for one or more AI agents.
#   install.sh [--agent claude,cursor,copilot,codex,gemini,all] [--project]
# No --agent: asks (or uses claude when not run in a terminal).
# Default scope is user-wide; --project installs into the current directory.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS=""; PROJECT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENTS="${2:?--agent needs a value}"; shift 2 ;;
    --project) PROJECT=1; shift ;;
    -h|--help) sed -n 2,6p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$AGENTS" ]; then
  if [ -t 0 ]; then
    read -r -p "Agent(s): claude, cursor, copilot, codex, gemini, other, all (comma separated) [claude]: " AGENTS
  fi
  AGENTS="${AGENTS:-claude}"
fi
[ "$AGENTS" = "all" ] && AGENTS="claude,cursor,copilot,codex,gemini"

DESC="Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project"
BODY="Read \`$REPO/init.md\` and follow it step by step. Templates are in \`$REPO/templates/\`.
The target is the project root, the directory this agent was opened in, never \`$REPO\` itself."

# scope_dir <project-relative dir> <user-wide dir or "">  -> prints the dir, or nothing if unsupported
scope_dir() {
  if [ "$PROJECT" = 1 ]; then echo "$PWD/$1"; elif [ -n "$2" ]; then echo "$2"; fi
}

write() {  # write <dir> <file> <content>; dir may be empty = unsupported here
  local agent="$1" dir="$2" file="$3" content="$4"
  if [ -z "$dir" ]; then
    echo "skipped $agent: no such scope (try --project or without it)" >&2; return
  fi
  mkdir -p "$dir"; printf '%s\n' "$content" > "$dir/$file"
  echo "installed $agent: $dir/$file"
}

IFS=',' read -ra LIST <<< "$AGENTS"
for a in "${LIST[@]}"; do
  a="$(echo "$a" | tr -d ' ' | tr 'A-Z' 'a-z')"
  case "$a" in
    claude)
      write claude "$(scope_dir .claude/commands "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands")" project-init.md \
"---
description: $DESC
---
$BODY" ;;
    cursor)
      write cursor "$(scope_dir .cursor/commands "$HOME/.cursor/commands")" project-init.md "$BODY" ;;
    copilot)  # VS Code prompt files: project only
      write copilot "$( [ "$PROJECT" = 1 ] && echo "$PWD/.github/prompts" )" project-init.prompt.md \
"---
description: $DESC
mode: agent
---
$BODY" ;;
    codex)    # Codex CLI custom prompts: user-wide only
      write codex "$( [ "$PROJECT" = 0 ] && echo "${CODEX_HOME:-$HOME/.codex}/prompts" )" project-init.md \
"---
description: $DESC
---
$BODY" ;;
    gemini)
      write gemini "$(scope_dir .gemini/commands "$HOME/.gemini/commands")" project-init.toml \
"description = \"$DESC\"
prompt = \"\"\"
$BODY
\"\"\"" ;;
    other|"")
      echo "other agent: no command file needed. Tell it: \"Read and follow $REPO/init.md\"" ;;
    *) echo "unknown agent: $a (claude, cursor, copilot, codex, gemini, other)" >&2; exit 2 ;;
  esac
done
echo "restart your agent, then run /project-init (or the prompt above for 'other')"

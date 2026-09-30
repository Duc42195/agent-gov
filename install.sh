#!/usr/bin/env bash
# Install the /project-init command.
#   install.sh             for every project (~/.claude/commands)
#   install.sh --project   for the current directory only (./.claude/commands)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = "--project" ]; then
  DEST="$PWD/.claude/commands"
else
  DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
fi
mkdir -p "$DEST"

cat > "$DEST/project-init.md" <<CMD
---
description: Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project
---
Read \`$REPO/init.md\` and follow it step by step. Templates are in \`$REPO/templates/\`.
The target is the project root, the directory Claude Code was opened in, never \`$REPO\` itself.
CMD
echo "installed $DEST/project-init.md -> $REPO"
echo "restart Claude Code, then type /project-init"

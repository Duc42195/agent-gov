#!/usr/bin/env bash
# Install the /project-init command for one or more AI agents.
#   install.sh [--agent claude,cursor,copilot,codex,gemini,all] [--project]
#   install.sh --update      pull the latest agent-gov (this clone) and show what changed
#   install.sh --with delete-session   also install tools/claude-delete-session (see below)
# No --agent (and no --with): asks (or uses claude when not run in a terminal).
# --with delete-session copies the tool to ~/.local/bin and adds the rule
#   Bash(~/.local/bin/claude-delete-session) to ~/.claude/settings.json (Claude Code only).
# Default scope is user-wide; --project installs into the current directory.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS=""; PROJECT=0; UPDATE=0; WITH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENTS="${2:?--agent needs a value}"; shift 2 ;;
    --project) PROJECT=1; shift ;;
    --update) UPDATE=1; shift ;;
    --with) WITH="${2:?--with needs a value}"; shift 2 ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$UPDATE" = 1 ]; then
  git -C "$REPO" fetch --quiet
  old="$(tr -d '[:space:]' < "$REPO/VERSION")"
  if [ "$(git -C "$REPO" rev-list --count HEAD..@{u})" = 0 ]; then echo "already up to date ($old)"; exit 0; fi
  git -C "$REPO" pull --ff-only --quiet
  echo "updated $old -> $(tr -d '[:space:]' < "$REPO/VERSION")"
  git -C "$REPO" diff --unified=0 HEAD@{1} HEAD -- CHANGELOG.md | grep '^+[^+]' | sed 's/^+//' || true
  echo "projects already scaffolded: run /project-init in them to upgrade"
  exit 0
fi

install_delete_session() {
  local bin="$HOME/.local/bin" settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  mkdir -p "$bin"
  cp "$REPO/tools/claude-delete-session" "$bin/claude-delete-session"
  chmod +x "$bin/claude-delete-session"
  echo "installed delete-session: $bin/claude-delete-session"
  if [ -f "$settings" ] && command -v python3 >/dev/null; then
    python3 - "$settings" <<'PYEOF'
import json, sys
path = sys.argv[1]
rule = "Bash(~/.local/bin/claude-delete-session)"
try:
    data = json.load(open(path))
    allow = data.setdefault("permissions", {}).setdefault("allow", [])
except (OSError, ValueError, AttributeError):
    print(f"settings: {path} is not a JSON object, left unchanged; add {rule} to permissions.allow yourself")
    sys.exit(0)
if rule in allow:
    print("settings: rule already present")
else:
    allow.append(rule)
    json.dump(data, open(path, "w"), indent=2)
    print(f"settings: added {rule} to {path}")
PYEOF
  else
    echo "settings: $settings not found, nothing changed"
  fi
  case ":$PATH:" in *":$bin:"*) ;; *) echo "NOTE: add to ~/.bashrc or ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac
  echo "use: claude-delete-session   (inside Claude: !claude-delete-session)"
}

if [ -n "$WITH" ]; then
  IFS=',' read -ra EXTRA <<< "$WITH"
  for w in "${EXTRA[@]}"; do
    case "$w" in
      delete-session) install_delete_session ;;
      *) echo "unknown --with: $w (delete-session)" >&2; exit 2 ;;
    esac
  done
  [ -z "$AGENTS" ] && exit 0
fi

if [ -z "$AGENTS" ]; then
  if [ -t 0 ]; then
    read -r -p "Agent(s): claude, cursor, copilot, codex, gemini, other, all (comma separated) [claude]: " AGENTS
  fi
  AGENTS="${AGENTS:-claude}"
fi
[ "$AGENTS" = "all" ] && AGENTS="claude,cursor,copilot,codex,gemini"

DESC="Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project"
BODY="First run \`git -C $REPO fetch --quiet && git -C $REPO status -sb\`; if it is behind, tell the user in one line and ask to run \`$REPO/install.sh --update\` before continuing. Then read \`$REPO/init.md\` and follow it step by step. Templates are in \`$REPO/templates/\`.
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

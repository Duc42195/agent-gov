#!/usr/bin/env bash
# Install the /project-init command for one or more AI agents.
#
#   install.sh --agent claude                    user-wide: writes only under your home folder
#   install.sh --agent claude --project          this project only: writes only under the current folder
#   install.sh --agent claude --uninstall [--project]   remove what this script wrote in that scope
#
# Agents: claude, cursor, copilot (project only), gemini, opencode, codex (deprecated), all, other.
# A project install never touches your home folder, and a user-wide install never touches the
# project. If a copy exists in the other scope it only warns (agents then list /project-init twice).
# Both modes record this machine (OS, shell, Python) in <agent-gov>/.env. Windows: use install.cmd.
# User-wide claude also installs bin/claude-delete-session into ~/.local/bin.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS=""; PROJECT=0; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENTS="${2:?--agent needs a value}"; shift 2 ;;
    --project) PROJECT=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$PROJECT" = 1 ] && [ "$PWD" = "$REPO" ]; then
  echo "run --project from your project's root folder, not from the agent-gov folder" >&2
  exit 2
fi

# -- this machine: OS, shell, Python ---------------------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
  esac
}
OS="$(detect_os)"
if [ "$OS" = windows ]; then SHELL_KIND="git-bash"; else SHELL_KIND="$(basename "${SHELL:-bash}")"; fi

# The first Python 3.8+ among python3, python, py (override the list with AGENT_GOV_PY_CANDIDATES).
# Python is only needed for /plan-check and claude-delete-session.
find_python() {
  local c cmd
  for c in ${AGENT_GOV_PY_CANDIDATES:-python3 python py}; do
    if [ "$c" = py ]; then cmd="py -3"; else cmd="$c"; fi
    if $cmd -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
      echo "$cmd"; return
    fi
  done
}
PY="$(find_python)"
[ -n "$PY" ] && echo "python: $PY" || echo "note: Python 3.8+ not found. /plan-check and claude-delete-session need it; everything else works without."

# -- where each agent keeps custom commands --------------------------------
# dir_for <agent> <user|project>  -> prints the directory, nothing if that scope is unsupported
dir_for() {
  local base
  if [ "$2" = user ]; then
    case "$1" in
      claude)   echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands" ;;
      cursor)   echo "$HOME/.cursor/commands" ;;
      gemini)   echo "$HOME/.gemini/commands" ;;
      opencode) echo "$HOME/.config/opencode/commands" ;;
      codex)    echo "${CODEX_HOME:-$HOME/.codex}/prompts" ;;
    esac
  else
    case "$1" in
      claude)   echo "$PWD/.claude/commands" ;;
      cursor)   echo "$PWD/.cursor/commands" ;;
      copilot)  echo "$PWD/.github/prompts" ;;
      gemini)   echo "$PWD/.gemini/commands" ;;
      opencode) echo "$PWD/.opencode/commands" ;;
    esac
  fi
}
file_for() { case "$1" in copilot) echo project-init.prompt.md ;; gemini) echo project-init.toml ;; *) echo project-init.md ;; esac; }
is_ours() { [ -f "$1" ] && grep -q "agent-governance scaffold" "$1"; }

SCOPE=user; [ "$PROJECT" = 1 ] && SCOPE=project
OTHER=project; [ "$SCOPE" = project ] && OTHER=user

# -- which agents -----------------------------------------------------------
if [ -z "$AGENTS" ]; then
  if [ -t 0 ]; then
    read -r -p "Agent(s): claude, cursor, copilot, gemini, opencode, codex, other, all (comma separated) [claude]: " AGENTS
  fi
  AGENTS="${AGENTS:-claude}"
fi
[ "$AGENTS" = "all" ] && AGENTS="claude,cursor,copilot,gemini,opencode"
IFS=',' read -ra LIST <<< "$AGENTS"

DESC="Set up the shared agent-governance scaffold (AGENTS.md, .agents/, /done) in this project"
BODY="Read \`$REPO/init.md\` and follow it step by step. The scripts and templates are in \`$REPO/\` (\`scripts/gov.sh\`, \`templates/\`). This machine's settings (shell, Python) are in \`$REPO/.env\`. Work only on the target project: the folder this agent was opened in, never \`$REPO\` itself, and do not change anything outside it."

content_for() {  # content_for <agent>
  case "$1" in
    claude|opencode|codex) printf -- '---\ndescription: %s\n---\n%s\n' "$DESC" "$BODY" ;;
    copilot) printf -- '---\ndescription: %s\nagent: agent\n---\n%s\n' "$DESC" "$BODY" ;;
    gemini) printf 'description = "%s"\nprompt = """\n%s\n"""\n' "$DESC" "$BODY" ;;
    *) printf '<!-- %s -->\n%s\n' "agent-governance scaffold: /project-init" "$BODY" ;;
  esac
}

install_delete_session() {
  local bin="$HOME/.local/bin" settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  local rule="Bash(~/.local/bin/claude-delete-session)"
  mkdir -p "$bin"
  cp "$REPO/bin/claude-delete-session" "$bin/claude-delete-session"
  chmod +x "$bin/claude-delete-session"
  echo "installed delete-session: $bin/claude-delete-session"
  if [ ! -f "$settings" ]; then
    echo "settings: $settings not found, nothing changed"
  elif command -v jq >/dev/null; then
    if jq -e --arg r "$rule" '(.permissions.allow // []) | index($r)' "$settings" >/dev/null 2>&1; then
      echo "settings: rule already present"
    elif jq --arg r "$rule" '.permissions //= {} | .permissions.allow //= [] | .permissions.allow += [$r]' "$settings" > "$settings.tmp" 2>/dev/null; then
      mv "$settings.tmp" "$settings"; echo "settings: added $rule to $settings"
    else
      rm -f "$settings.tmp"; echo "WARNING: could not edit $settings; add $rule to permissions.allow yourself"
    fi
  else
    echo "WARNING: jq not found, $settings left unchanged. To run claude-delete-session without a prompt, add \"$rule\" to permissions.allow yourself."
  fi
  case ":$PATH:" in *":$bin:"*) ;; *) echo "NOTE: add to ~/.bashrc or ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;; esac
  echo "use it in a terminal: claude-delete-session   (at the Claude Code prompt: !claude-delete-session)"
}

write_env() {
  cat > "$REPO/.env" <<ENV
# Written by install.sh. This machine's settings for agent-gov; not committed.
AGENT_GOV_REPO=$REPO
AGENT_GOV_OS=$OS
AGENT_GOV_SHELL=$SHELL_KIND
AGENT_GOV_INSTALLER=install.sh
AGENT_GOV_PY=${PY:-none}
AGENT_GOV_AGENTS=$1
ENV
  echo "recorded this machine in $REPO/.env (os=$OS shell=$SHELL_KIND python=${PY:-none})"
}

HAS_CLAUDE=0; DONE=""
for a in "${LIST[@]}"; do
  a="$(echo "$a" | tr -d ' ' | tr 'A-Z' 'a-z')"
  case "$a" in
    claude|cursor|copilot|gemini|opencode|codex) ;;
    other|"") echo "other agent: no command file needed. Tell it: \"Read and follow $REPO/init.md\""; continue ;;
    *) echo "unknown agent: $a (claude, cursor, copilot, gemini, opencode, codex, other)" >&2; exit 2 ;;
  esac
  dir="$(dir_for "$a" "$SCOPE")"
  if [ -z "$dir" ]; then
    case "$a" in
      copilot) echo "copilot: it has no user-wide commands. Run: install.sh --agent copilot --project   (from your project)" ;;
      codex)   echo "codex: its custom prompts are user-wide only. Run it without --project. (Codex deprecated custom prompts.)" ;;
    esac
    continue
  fi
  file="$dir/$(file_for "$a")"

  if [ "$UNINSTALL" = 1 ]; then
    if is_ours "$file"; then rm -f "$file"; echo "removed $a: $file"; else echo "nothing of ours at $file"; fi
    continue
  fi

  [ "$a" = codex ] && echo "note: Codex custom prompts are deprecated in favour of skills; this may stop working."
  mkdir -p "$dir"; content_for "$a" > "$file"
  echo "installed $a ($SCOPE): $file"
  DONE="${DONE:+$DONE,}$a"
  [ "$a" = claude ] && HAS_CLAUDE=1

  other_dir="$(dir_for "$a" "$OTHER")"
  if [ -n "$other_dir" ] && ! { [ "$OTHER" = project ] && [ "$PWD" = "$REPO" ]; } && is_ours "$other_dir/$(file_for "$a")"; then
    flag=""; [ "$OTHER" = project ] && flag=" --project"
    echo "WARNING: $a will list /project-init twice: another copy is at $other_dir/$(file_for "$a"). Remove it with: $REPO/install.sh --agent $a --uninstall$flag   (run it from the project for --project)"
  fi
done

if [ "$UNINSTALL" = 1 ]; then
  echo "(claude-delete-session in ~/.local/bin was left alone)"
  exit 0
fi

if [ "$SCOPE" = user ]; then
  # 0.7.0 wrote OpenCode's command to the wrong folder; that file is ours, so remove it.
  old="$HOME/.opencode/commands/project-init.md"
  if is_ours "$old"; then rm -f "$old"; echo "removed the misplaced file from 0.7.0: $old"; fi
  [ "$HAS_CLAUDE" = 1 ] && install_delete_session
elif [ "$HAS_CLAUDE" = 1 ]; then
  echo "(project install: claude-delete-session is user-wide, so it was not installed; run install.sh --agent claude without --project for it)"
fi

write_env "$DONE"
echo "restart your agent, then run /project-init (or the prompt above for 'other')"

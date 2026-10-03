#!/usr/bin/env bash
# score.sh - score how well /project-init scaffolded a project. bash + coreutils only.
#   score.sh [PROJECT_DIR] [--agent NAME] [--model NAME] [--write]
# Prints one line per check and a score. --write saves a paste-ready report to
# PROJECT_DIR/.agents/state/init-report.md with a self-report section for the agent to fill.
# Exit code 1 if any check fails. Windows: score.ps1.
set -uo pipefail

proj="."; agent="unknown"; model="unknown"; write=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="${2:?}"; shift 2 ;;
    --model) model="${2:?}"; shift 2 ;;
    --write) write=1; shift ;;
    -h|--help) sed -n 2,6p "$0"; exit 0 ;;
    *) proj="$1"; shift ;;
  esac
done
cd "$proj" || { echo "not a folder: $proj" >&2; exit 2; }
proj="$(pwd)"

passed=0; total=0; lines=""
check() {  # check <name> <0 if ok> [detail]
  total=$((total + 1))
  if [ "$2" = 0 ]; then passed=$((passed + 1)); lines="${lines}- [x] $1"$'\n'
  else lines="${lines}- [ ] $1${3:+ - $3}"$'\n'; fi
}

missing=""
for f in AGENTS.md CLAUDE.md plan.csv .agents/roles.md .agents/init-manifest \
         .agents/wiki/decisions-log.md .agents/wiki/learnings.md .agents/wiki/open-questions.md .agents/wiki/working-process.md; do
  [ -f "$f" ] || missing="$missing $f"
done
{ [ -f .agents/tools/plan.sh ] || [ -f .agents/tools/plan.ps1 ]; } || missing="$missing .agents/tools/plan.sh"
check "required files exist" "$([ -z "$missing" ] && echo 0 || echo 1)" "missing:$missing"

left="$(grep -rlE '\{\{[A-Z_]+\}\}' AGENTS.md .agents .claude .cursor .github .opencode GEMINI.md 2>/dev/null | grep -v '^\.agents/state/' | tr '\n' ' ')"
check "no {{placeholder}} left" "$([ -z "$left" ] && echo 0 || echo 1)" "$left"

check "CLAUDE.md is one line '@AGENTS.md'" "$([ -f CLAUDE.md ] && [ "$(tr -d '[:space:]' < CLAUDE.md)" = "@AGENTS.md" ] && echo 0 || echo 1)"
check "AGENTS.md profile filled" "$(grep -q '<one line' AGENTS.md 2>/dev/null && echo 1 || echo 0)" "'<one line' still in the Profile"
check "AGENTS.md has a Python line" "$(grep -q '^- Python:' AGENTS.md 2>/dev/null && echo 0 || echo 1)"
n=999; [ -f AGENTS.md ] && n="$(wc -l < AGENTS.md)"
check "AGENTS.md short (<= 80 lines)" "$([ "$n" -le 80 ] && echo 0 || echo 1)" "$n lines"

header="id,title,owner,status,estimate,start,end,dod,mr,reviewer,review,updated,depends,notes"
check "plan.csv header exact" "$([ -f plan.csv ] && [ "$(head -1 plan.csv | tr -d '\r')" = "$header" ] && echo 0 || echo 1)"
check "plan.csv has >= 1 task" "$([ -f plan.csv ] && [ "$(wc -l < plan.csv)" -ge 2 ] && echo 0 || echo 1)"
check "roles.md filled" "$([ -f .agents/roles.md ] && ! grep -qE '<name>|\{\{' .agents/roles.md && echo 0 || echo 1)"
gi=0; for l in '.agents/state/' '.agents/*.bak' '__pycache__/'; do grep -qxF "$l" .gitignore 2>/dev/null || gi=1; done
check ".gitignore has agent lines" "$gi"

if [ -f .agents/tools/plan.sh ]; then
  out="$(bash .agents/tools/plan.sh list 2>&1)"; rc=$?
  check "plan.sh list works" "$rc" "$(printf '%s' "$out" | tail -1)"
fi
done_cmd=1
for f in .claude/commands/done.md .cursor/commands/done.md .github/prompts/done.prompt.md .opencode/commands/done.md; do [ -f "$f" ] && done_cmd=0; done
check "a /done command exists" "$done_cmd"

if [ -d .agents/plan-check ]; then
  pc=1; for f in .claude/commands/plan-check.md .cursor/commands/plan-check.md .github/prompts/plan-check.prompt.md .opencode/commands/plan-check.md; do [ -f "$f" ] && pc=0; done
  check "a /plan-check command exists" "$pc"
  sc="$(awk '/^## Standup checks/{f=1;next} /^## /{f=0} f && /^- /{c++} END{print c+0}' .agents/wiki/working-process.md 2>/dev/null)"
  check "Standup checks filled in working-process.md" "$([ "${sc:-0}" -ge 1 ] && echo 0 || echo 1)" "no bullet line under '## Standup checks'"
  py=""; for c in python3 python; do command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null && { py="$c"; break; }; done
  if [ -n "$py" ]; then
    out="$("$py" .agents/plan-check/plan_check.py --no-fetch 2>&1)"
    check "plan_check.py prints a report" "$(printf '%s' "$out" | grep -q '| ID |' && echo 0 || echo 1)" "$(printf '%s' "$out" | tail -1 | cut -c1-120)"
  else
    echo "note: Python 3.8+ not found, skipped the plan_check.py run" >&2
  fi
fi

printf '%s' "$lines"
printf '\nscore %s/%s\n' "$passed" "$total"
if [ "$write" = 1 ]; then
  mkdir -p .agents/state
  research="other"; grep -q 'Research project: yes' AGENTS.md 2>/dev/null && research="research"
  {
    echo "# init report"; echo
    echo "- agent: $agent"; echo "- model: $model"; echo "- project type: $research"; echo "- score: $passed/$total"; echo
    echo "## Objective checks"; printf '%s' "$lines"; echo
    echo "## Self-report (the agent fills this in; keep it short, no project secrets or private content)"
    echo "- Steps of init.md I could not follow as written, and why:"
    echo "- Places where init.md was ambiguous or contradicted itself:"
    echo "- Files I had to change beyond the templates (list) and why:"
    echo "- Questions I asked the user (count) and any I could have answered from the repo:"
    echo "- Errors hit and how they were fixed:"
    echo "- Existing files I merged into instead of creating (list):"
    echo "- One change to init.md or the templates that would have saved the most effort:"
  } > .agents/state/init-report.md
  echo "report written: $proj/.agents/state/init-report.md"
fi
[ "$passed" = "$total" ]

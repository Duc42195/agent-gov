#!/usr/bin/env bash
# gov.sh - copy, inspect and upgrade the agent-gov scaffold in a project.
# bash + coreutils (+ git for old-project detection) only. Windows: scripts/gov.ps1 does the same.
#
#   gov.sh detect   <project>                       facts about the project, for the agent to confirm
#   gov.sh scaffold <project> --vars FILE           copy the templates (never overwrites a file)
#   gov.sh upgrade  <project> [--vars FILE] [--apply]   plan (default) or apply an upgrade
#   gov.sh record   <project> <path>...             after you merged <path>.agent-gov-new into <path>
#
# FILE holds KEY=VALUE lines (one line per value): PROJECT_NAME WHAT GOAL STACK IS_RESEARCH TASK_KEY
# GIT_HOST DEFAULT_BRANCH EXTERNAL_TRACKER GATE_CMD PY PLAN ROLE_NAME ROLE ROLE_OWNS AGENTS PLAN_CHECK.
# The manifest .agents/init-manifest remembers the values and, per file, the hash of the template
# last taken. A file equal to that hash is "unmodified" and is replaced on upgrade; a modified file
# is never overwritten (the new version is written next to it as <file>.agent-gov-new).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
TPL="$REPO/templates"
VERSION="$(tr -d '[:space:]' < "$REPO/VERSION")"
MANIFEST=".agents/init-manifest"
TAB="$(printf '\t')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

die() { echo "gov.sh: $*" >&2; exit 2; }

# -- hashing (CR removed so Windows checkouts compare equal) ---------------
hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then tr -d '\r' | sha256sum | cut -d' ' -f1
  else tr -d '\r' | shasum -a 256 | cut -d' ' -f1; fi
}
hash_file() { hash_stdin < "$1"; }

# -- variables -------------------------------------------------------------
getvar() { grep -m1 "^$1=" "$2" 2>/dev/null | cut -d= -f2- || true; }
shell_plan() {  # the command that runs plan.sh/plan.ps1 in this machine's shell
  local sh="" f="$REPO/.env"
  [ -f "$f" ] && sh="$(getvar AGENT_GOV_SHELL "$f")"
  case "$sh" in
    powershell|pwsh|cmd) echo "powershell -NoProfile -File .agents/tools/plan.ps1" ;;
    *) echo "bash .agents/tools/plan.sh" ;;
  esac
}
# make_vars <project> <vars file or ""> <out>: defaults < manifest < --vars file
make_vars() {
  local proj="$1" extra="$2" out="$3" py="" gu=""
  [ -f "$REPO/.env" ] && py="$(getvar AGENT_GOV_PY "$REPO/.env")"
  { [ -z "$py" ] || [ "$py" = none ]; } && py=python3
  gu="$(git -C "$proj" config user.name 2>/dev/null || true)"
  {
    echo "PROJECT_NAME=$(basename "$(cd "$proj" && pwd)")"
    echo "WHAT=<one line: what this project is>"; echo "GOAL=<one line: what done looks like>"
    echo "STACK=docs only"; echo "IS_RESEARCH=no"; echo "TASK_KEY=TASK"; echo "GIT_HOST=none"
    echo "DEFAULT_BRANCH=main"; echo "EXTERNAL_TRACKER=none"; echo "GATE_CMD="
    echo "PY=$py"; echo "PLAN=$(shell_plan)"
    echo "ROLE_NAME=${gu:-me}"; echo "ROLE=maintainer"; echo "ROLE_OWNS=everything"
    echo "AGENTS=claude"; echo "PLAN_CHECK=no"
    [ -f "$proj/$MANIFEST" ] && grep '^var ' "$proj/$MANIFEST" | sed 's/^var //'
    [ -n "$extra" ] && grep -E '^[A-Z_]+=' "$extra"
    true
  } > "$out.all"
  # last assignment of a key wins
  awk -F= '{ v[$1]=$0; if (!($1 in o)) { o[$1]=++n; k[n]=$1 } } END { for (i=1;i<=n;i++) print v[k[i]] }' "$out.all" > "$out"
}
sed_script() {  # sed_script <vars> <out>: one s||| per variable
  : > "$2"
  while IFS= read -r line; do
    local k="${line%%=*}" v="${line#*=}"
    v="$(printf '%s' "$v" | sed -e 's/[\\|&]/\\&/g')"
    printf 's|{{%s}}|%s|g\n' "$k" "$v" >> "$2"
  done < "$1"
}

# -- which template files belong in this project ---------------------------
has() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
# pairs <vars>: prints "dest<TAB>src" for every template; "all" ignores the agent/plan-check choice
pairs() {
  local vars="$1" mode="${2:-selected}" agents pc src dest
  agents="$(getvar AGENTS "$vars")"; pc="$(getvar PLAN_CHECK "$vars")"
  ( cd "$TPL" && find . -type f | sed 's|^\./||' | sort ) | while IFS= read -r src; do
    dest="$src"; ok=1
    case "$src" in
      gitignore.append) continue ;;
      pointer.md) continue ;;
      .agents/plan-check/*) [ "$pc" = yes ] || ok=0 ;;
      .claude/commands/done.md) has "$agents" claude || ok=0 ;;
      .claude/commands/plan-check.md) { has "$agents" claude && [ "$pc" = yes ]; } || ok=0 ;;
      .cursor/commands/done.md) has "$agents" cursor || ok=0 ;;
      .cursor/commands/plan-check.md) { has "$agents" cursor && [ "$pc" = yes ]; } || ok=0 ;;
      .github/prompts/done.prompt.md) has "$agents" copilot || ok=0 ;;
      .github/prompts/plan-check.prompt.md) { has "$agents" copilot && [ "$pc" = yes ]; } || ok=0 ;;
      .opencode/commands/done.md) has "$agents" opencode || ok=0 ;;
      .opencode/commands/plan-check.md) { has "$agents" opencode && [ "$pc" = yes ]; } || ok=0 ;;
    esac
    if [ "$ok" = 1 ] || [ "$mode" = all ]; then printf '%s\t%s\n' "$dest" "$src"; fi
  done
  # tools that do not read AGENTS.md get a one-line pointer file
  if [ "$mode" = all ] || has "$agents" copilot; then printf '.github/copilot-instructions.md\tpointer.md\n'; fi
  if [ "$mode" = all ] || has "$agents" gemini; then printf 'GEMINI.md\tpointer.md\n'; fi
}
render() { sed -f "$1" "$TPL/$2"; }  # render <sed script> <template path>

# -- manifest ---------------------------------------------------------------
manifest_hash() { [ -f "$1/$MANIFEST" ] && awk -F'\t' -v p="$2" '$1=="file" && $3==p {print $2}' "$1/$MANIFEST" || true; }
write_manifest() {  # write_manifest <project> <vars> <hash table: dest<TAB>hash>
  mkdir -p "$1/.agents"
  {
    echo "# agent-gov manifest, written by scripts/gov.sh. Do not edit by hand."
    echo "version $VERSION"
    sed 's/^/var /' "$2"
    sort "$3" | awk -F'\t' '{ printf "file\t%s\t%s\n", $2, $1 }'
  } > "$1/$MANIFEST"
}

# -- old releases (to recognise untouched files of a project without a manifest) --
hist_has() {  # hist_has <template path> <hash>: does any released tag carry that exact file?
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || return 1
  local tag h
  for tag in $(git -C "$REPO" tag -l 'v*'); do
    h="$(git -C "$REPO" show "$tag:templates/$1" 2>/dev/null | hash_stdin || true)"
    [ "$h" = "$2" ] && return 0
  done
  return 1
}
placeholder_free() { ! grep -q '{{' "$TPL/$1"; }

# ==========================================================================
cmd_detect() {
  local p="${1:?project folder}" f v
  [ -d "$p" ] || die "not a folder: $p"
  p="$(cd "$p" && pwd)"
  echo "project=$p"
  echo "gov_version=$VERSION"
  if [ -f "$p/$MANIFEST" ]; then
    echo "manifest=yes"; echo "manifest_version=$(awk '$1=="version"{print $2}' "$p/$MANIFEST")"
  else echo "manifest=no"; fi
  if git -C "$p" rev-parse --git-dir >/dev/null 2>&1; then
    local url br host=other
    url="$(git -C "$p" remote get-url origin 2>/dev/null || true)"
    br="$(git -C "$p" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
    [ -z "$br" ] && br="$(git -C "$p" branch --show-current 2>/dev/null || true)"
    case "$url" in *github*) host=GitHub ;; *gitlab*) host=GitLab ;; "") host=none ;; esac
    echo "git=yes"; echo "remote=$url"; echo "git_host=$host"; echo "default_branch=${br:-main}"
    echo "git_user=$(git -C "$p" config user.name 2>/dev/null || true)"
  else echo "git=no"; fi
  local dirs=""
  for v in claude:.claude cursor:.cursor opencode:.opencode gemini:.gemini copilot:.github/prompts; do
    [ -d "$p/${v#*:}" ] && dirs="${dirs:+$dirs,}${v%%:*}"
  done
  echo "agent_dirs=$dirs"
  if [ -f "$p/AGENTS.md" ]; then
    echo "agents_md=yes"
    for v in What Goal Stack "Research project" "Gate command" Python; do
      echo "profile_$(echo "$v" | tr 'A-Z ' 'a-z_')=$(grep -m1 -i "^- \**$v" "$p/AGENTS.md" | sed 's/^[^:]*:\**[ ]*//' | cut -c1-160 || true)"
    done
    echo "task_prefix=$(grep -m1 'Task id prefix' "$p/AGENTS.md" | sed 's/.*prefix:\** *`\{0,1\}\([A-Za-z0-9_-]*\).*/\1/' || true)"
  else echo "agents_md=no"; fi
  if [ -f "$p/plan.csv" ]; then
    echo "plan_csv=yes"; echo "plan_rows=$(($(wc -l < "$p/plan.csv") - 1))"; echo "plan_header=$(head -1 "$p/plan.csv" | cut -c1-200)"
  else echo "plan_csv=no"; fi
  echo "roles=$([ -f "$p/.agents/roles.md" ] && echo yes || echo no)"
  echo "wiki=$([ -d "$p/.agents/wiki" ] && echo yes || echo no)"
  local legacy=""
  for f in record.md action-history.md .agents/record.md .agents/action-history.md docs/adr .agents/adr .agents/tools/check_adr.py .agents/tools/plan.py .agents/tools/sync_plan.py; do
    [ -e "$p/$f" ] && legacy="${legacy:+$legacy,}$f"
  done
  echo "legacy=$legacy"
  local gate=""
  if [ -f "$p/package.json" ] && grep -q '"test"' "$p/package.json"; then gate="npm test"
  elif [ -f "$p/Makefile" ] && grep -q '^test:' "$p/Makefile"; then gate="make test"
  elif [ -f "$p/go.mod" ]; then gate="go test ./..."
  elif [ -f "$p/Cargo.toml" ]; then gate="cargo test"
  elif [ -f "$p/pyproject.toml" ] || [ -f "$p/pytest.ini" ] || [ -d "$p/tests" ]; then gate="pytest"; fi
  echo "gate_guess=$gate"
  echo "env_py=$([ -f "$REPO/.env" ] && getvar AGENT_GOV_PY "$REPO/.env" || true)"
  echo "env_shell=$([ -f "$REPO/.env" ] && getvar AGENT_GOV_SHELL "$REPO/.env" || true)"
}

cmd_scaffold() {
  local p="${1:?project folder}"; shift
  local extra=""
  while [ $# -gt 0 ]; do case "$1" in --vars) extra="${2:?--vars needs a file}"; shift 2 ;; *) die "unknown option: $1" ;; esac; done
  [ -d "$p" ] || die "not a folder: $p"
  p="$(cd "$p" && pwd)"
  [ -f "$p/$MANIFEST" ] && die "this project already has a manifest: use 'upgrade' (or delete $MANIFEST to start over)"
  make_vars "$p" "$extra" "$WORK/vars"; sed_script "$WORK/vars" "$WORK/sed"
  : > "$WORK/table"
  pairs "$WORK/vars" | while IFS="$TAB" read -r dest src; do
    render "$WORK/sed" "$src" > "$WORK/out"
    printf '%s\t%s\n' "$dest" "$(hash_file "$WORK/out")" >> "$WORK/table"
    if [ -e "$p/$dest" ]; then echo "EXISTS$TAB$dest"
    else mkdir -p "$(dirname "$p/$dest")"; cp "$WORK/out" "$p/$dest"; echo "ADD$TAB$dest"; fi
    grep -n '{{' "$WORK/out" >/dev/null 2>&1 && echo "UNSET$TAB$dest$TAB$(grep -o '{{[A-Z_]*}}' "$WORK/out" | sort -u | tr '\n' ' ')" || true
  done
  # .gitignore: append the lines that are missing
  if [ -f "$TPL/gitignore.append" ]; then
    touch "$p/.gitignore"
    while IFS= read -r l; do
      [ -n "$l" ] && ! grep -qxF "$l" "$p/.gitignore" && { echo "$l" >> "$p/.gitignore"; echo "APPEND$TAB.gitignore$TAB$l"; }
    done < "$TPL/gitignore.append"
  fi
  write_manifest "$p" "$WORK/vars" "$WORK/table"
  echo "MANIFEST$TAB$MANIFEST"
  echo "EXISTS means your file was kept as it is: merge the new template by hand if you want its content."
}

cmd_upgrade() {
  local p="${1:?project folder}"; shift
  local extra="" apply=0
  while [ $# -gt 0 ]; do case "$1" in --vars) extra="${2:?--vars needs a file}"; shift 2 ;; --apply) apply=1; shift ;; *) die "unknown option: $1" ;; esac; done
  [ -d "$p" ] || die "not a folder: $p"
  p="$(cd "$p" && pwd)"
  local limited=0
  if [ ! -f "$p/$MANIFEST" ]; then
    limited=1
    echo "WARNING: no manifest in this project (it was set up by an older agent-gov). Limited mode: only"
    echo "         files that match a released template are replaced; everything else is kept for you to merge."
  fi
  make_vars "$p" "$extra" "$WORK/vars"; sed_script "$WORK/vars" "$WORK/sed"
  : > "$WORK/table"; : > "$WORK/actions"
  local n_add=0 n_upd=0 n_conf=0 n_rm=0 n_orph=0 n_keep=0 n_need=0

  act() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$WORK/actions"; }
  pairs "$WORK/vars" | while IFS="$TAB" read -r dest src; do
    if [ "$limited" = 1 ] && [ -z "$extra" ] && ! placeholder_free "$src"; then
      if [ -e "$p/$dest" ]; then act UNKNOWN "$dest" "has placeholders and no manifest: cannot tell if you changed it (give --vars to compare)"
      else act NEEDS-VARS "$dest" "missing; give --vars to create it"; fi
      continue
    fi
    render "$WORK/sed" "$src" > "$WORK/new"
    nh="$(hash_file "$WORK/new")"; base="$(manifest_hash "$p" "$dest")"
    if [ ! -e "$p/$dest" ]; then
      act ADD "$dest"; printf '%s\t%s\n' "$dest" "$nh" >> "$WORK/table"
      [ "$apply" = 1 ] && { mkdir -p "$(dirname "$p/$dest")"; cp "$WORK/new" "$p/$dest"; }
      continue
    fi
    cur="$(hash_file "$p/$dest")"
    if [ "$cur" = "$nh" ]; then act SAME "$dest"; printf '%s\t%s\n' "$dest" "$nh" >> "$WORK/table"
    elif [ "$base" = "$nh" ]; then act KEEP "$dest" "your edits; the template did not change"; printf '%s\t%s\n' "$dest" "$nh" >> "$WORK/table"
    elif { [ -n "$base" ] && [ "$cur" = "$base" ]; } || { [ -z "$base" ] && placeholder_free "$src" && hist_has "$src" "$cur"; }; then
      act UPDATE "$dest"; printf '%s\t%s\n' "$dest" "$nh" >> "$WORK/table"
      [ "$apply" = 1 ] && cp "$WORK/new" "$p/$dest"
    else
      act CONFLICT "$dest" "you changed it and the template changed: merge $dest.agent-gov-new, then: gov.sh record <project> $dest"
      [ -n "$base" ] && printf '%s\t%s\n' "$dest" "$base" >> "$WORK/table"
      [ "$apply" = 1 ] && cp "$WORK/new" "$p/$dest.agent-gov-new"
    fi
  done

  # templates that no longer exist: remove untouched copies, keep (and report) changed ones
  pairs "$WORK/vars" all | cut -f1 | sort > "$WORK/known"
  if [ "$limited" = 0 ]; then
    awk -F'\t' '$1=="file"{print $3 "\t" $2}' "$p/$MANIFEST" | while IFS="$TAB" read -r dest h; do
      grep -qxF "$dest" "$WORK/known" && continue
      if [ ! -e "$p/$dest" ]; then act DROP "$dest" "already gone"
      elif [ "$(hash_file "$p/$dest")" = "$h" ]; then act REMOVE "$dest" "no longer part of agent-gov"; [ "$apply" = 1 ] && rm -f "$p/$dest"
      else act ORPHAN "$dest" "no longer part of agent-gov, but you changed it: kept"; printf '%s\t%s\n' "$dest" "$h" >> "$WORK/table"; fi
    done
  elif git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    for tag in $(git -C "$REPO" tag -l 'v*'); do
      git -C "$REPO" ls-tree -r --name-only "$tag" -- templates 2>/dev/null | sed 's|^templates/||'
    done | sort -u | while IFS= read -r old; do
      grep -qxF "$old" "$WORK/known" && continue
      [ -e "$TPL/$old" ] && continue
      [ -e "$p/$old" ] || continue
      ch="$(hash_file "$p/$old")"; gone=0
      for tag in $(git -C "$REPO" tag -l 'v*'); do
        [ "$(git -C "$REPO" show "$tag:templates/$old" 2>/dev/null | hash_stdin)" = "$ch" ] && { gone=1; break; }
      done
      if [ "$gone" = 1 ]; then act REMOVE "$old" "no longer part of agent-gov (untouched old copy)"; [ "$apply" = 1 ] && rm -f "$p/$old"
      else act ORPHAN "$old" "no longer part of agent-gov, but not an untouched copy: kept"; fi
    done
  fi

  # report
  sort -t"$TAB" -k1,1 -s "$WORK/actions" | while IFS="$TAB" read -r a d note; do
    case "$a" in SAME) continue ;; esac
    printf '%s\t%s%s\n' "$a" "$d" "${note:+  ($note)}"
  done
  for k in ADD UPDATE CONFLICT REMOVE ORPHAN KEEP UNKNOWN NEEDS-VARS; do
    c="$(awk -F'\t' -v k="$k" '$1==k' "$WORK/actions" | wc -l | tr -d ' ')"
    [ "$c" != 0 ] && printf '%s=%s ' "$k" "$c"
  done; echo
  if [ "$apply" = 1 ]; then
    if [ "$limited" = 1 ] && [ -z "$extra" ]; then
      echo "applied. No manifest was created (no --vars): run again with --vars to enable full upgrades."
    else
      write_manifest "$p" "$WORK/vars" "$WORK/table"; echo "applied. Manifest updated ($MANIFEST)."
    fi
  else
    echo "dry run: nothing was changed. Add --apply to do it."
  fi
}

cmd_record() {
  local p="${1:?project folder}"; shift
  [ $# -gt 0 ] || die "give the file(s) you merged"
  p="$(cd "$p" && pwd)"
  [ -f "$p/$MANIFEST" ] || die "no manifest in $p"
  make_vars "$p" "" "$WORK/vars"; sed_script "$WORK/vars" "$WORK/sed"
  awk -F'\t' '$1=="file"{print $3 "\t" $2}' "$p/$MANIFEST" > "$WORK/table"
  local f
  for f in "$@"; do
    src="$(pairs "$WORK/vars" all | awk -F'\t' -v d="$f" '$1==d{print $2}')"
    [ -n "$src" ] || die "$f is not an agent-gov template file"
    render "$WORK/sed" "$src" > "$WORK/new"
    grep -v "^$f$TAB" "$WORK/table" > "$WORK/table2" || true
    printf '%s\t%s\n' "$f" "$(hash_file "$WORK/new")" >> "$WORK/table2"; mv "$WORK/table2" "$WORK/table"
    rm -f "$p/$f.agent-gov-new"
    echo "RECORDED$TAB$f"
  done
  write_manifest "$p" "$WORK/vars" "$WORK/table"
}

case "${1:-}" in
  detect)   shift; cmd_detect "$@" ;;
  scaffold) shift; cmd_scaffold "$@" ;;
  upgrade)  shift; cmd_upgrade "$@" ;;
  record)   shift; cmd_record "$@" ;;
  -h|--help|"") sed -n 2,16p "$0" ;;
  *) die "unknown command: $1 (detect, scaffold, upgrade, record)" ;;
esac

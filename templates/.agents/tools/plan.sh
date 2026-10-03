#!/usr/bin/env bash
# plan.sh - print plan.csv with a done-percentage and late tasks marked. Read-only.
#   plan.sh list [--owner NAME] [--status todo|in-progress|done]
# Edit plan.csv itself to change a task (one row per task, keep the header). bash + awk only.
# Windows: plan.ps1 (PowerShell) or plan.cmd. The plan is <project>/plan.csv, or $PLAN_CSV.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
plan="${PLAN_CSV:-$root/plan.csv}"
cmd="${1:-list}"; shift || true
[ "$cmd" = list ] || { echo "usage: plan.sh list [--owner NAME] [--status STATUS]" >&2; exit 2; }
owner=""; status=""
while [ $# -gt 0 ]; do
  case "$1" in
    --owner) owner="${2:?--owner needs a name}"; shift 2 ;;
    --status) status="${2:?--status needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -f "$plan" ] || { echo "plan not found: $plan" >&2; exit 1; }

awk -v owner="$owner" -v status="$status" -v today="$(date +%F)" '
function parse(line, a,   n, i, c, f, q, len) {  # one CSV record, quotes and "" understood
  n = 0; f = ""; q = 0; len = length(line)
  for (i = 1; i <= len; i++) {
    c = substr(line, i, 1)
    if (q) { if (c == "\"") { if (substr(line, i + 1, 1) == "\"") { f = f c; i++ } else q = 0 } else f = f c }
    else if (c == "\"") q = 1
    else if (c == ",") { a[++n] = f; f = "" }
    else f = f c
  }
  a[++n] = f
  return n
}
{ sub(/\r$/, "") }
NR == 1 { n = parse($0, h); for (i = 1; i <= n; i++) col[tolower(h[i])] = i; next }
$0 == "" { next }
{
  parse($0, r)
  id = r[col["id"]]; if (id == "") next
  st = r[col["status"]]; ow = r[col["owner"]]; rv = r[col["review"]]; en = r[col["end"]]; ti = r[col["title"]]
  total++; if (st == "done") done++
  if (owner != "" && ow != owner) next
  if (status != "" && st != status) next
  late = (en != "" && en < today && st != "done") ? " LATE" : ""
  printf "%-10s %-12s %-12s %-9s %-10s %s%s\n", id, st, ow, rv, en, ti, late
}
END { if (total > 0) printf "\n%d/%d done (%d%%)\n", done, total, int(100 * done / total); else print "\n0/0 done" }
' "$plan"

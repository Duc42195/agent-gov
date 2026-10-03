# plan-check report template (English)

This file decides what the report looks like: the return layout, the table columns, and every
word and emoji. Edit it freely. `plan_check.py` only fills it in.

- Put a project override in `.agents/templates/plan-check.en.md`; it wins over this file.
- Make another language by copying this file to `plan-check.<lang>.md` and running with `--lang <lang>`.
- Only the three fenced blocks below are read. Everything else here is documentation.

## 1. Return template

Placeholders: `{date}` `{verdict}` `{summary}` `{sources}` `{table}` `{confirm}` (empty when there is nothing to confirm).

````report
## {date} — {verdict}
{summary}
{sources}

{table}

{confirm}
````

## 2. Table template

Exactly two lines: the header, then the row template. The separator line is added for you.
Row placeholders: `{id}` `{title}` `{owner}` `{status}` `{est}` `{start}` `{end}` `{plan}` `{git}` `{progress}` `{blocks}`.
Add, drop or reorder columns by editing both lines.

````table
| ID | Task | Owner | Est | Plan | Git | Progress | Blocks |
| {id} | {title} | {owner} | {est} | {plan} | {git} | {progress} | {blocks} |
````

## 3. Labels

One `key = value` per line. Keep every key; change the values. `{x}` marks a value the tool fills in.

````labels
# the verdict: ON TRACK unless at least one undelivered task is past its end date
ok = 🟢 **ON TRACK**
late = 🔴 **BEHIND SCHEDULE**

# the one-line summary
n_late = {n} task(s) past their end date: {ids}
due = due today: {ids}
mismatch = marked done but not found in git: {ids}
blk_yes = Blocking others: **yes** ({a} task(s) holding up {b})
blk_no = Blocking others: **no**

# the sources line
src = Sources: plan ({n} tasks, {done} done) · {branch} head `{sha}` {sync} · {mrs}
sync_ok = matches remote ✅
sync_stale = ⚠️ remote is at {r}, local is stale
sync_none = (no remote)
sync_skip = (not compared: --no-fetch)
mrs = {n} MR/PR heads scanned
mrs_unverified = open/closed state of MRs not verified
nogit = ⚠️ no git history found: the Git column is unavailable, using the plan status only

# the Progress column
merged_todo = ✅ merged, mark done
done = ✅ done
late_s = 🔴 LATE +{d}d
waiting = (MR waiting)
today = 🟡 due today
no_mr = no MR yet
future = ⏳ not yet (starts {d})
ontime = 🟢 on time
review = 🔎 done, MR waiting for review/merge
mism = ⚠️ marked done, not found in git

# the Git and Blocks columns
nocode = no code yet
merge = merge {x}
leftover = (MR !{n} still lists it, not verified open)
none = —

# the line under the table
confirm = **Merged but still not marked done:** {ids}. Mark them done only after the user confirms.
````

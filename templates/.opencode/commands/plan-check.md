---
description: Standup - check the plan, the code and every MR/PR, check who each task blocks, report on or behind schedule
---
Run the standup check. It is read-only until step 4.

1. Run `{{PY}} .agents/plan-check/plan_check.py`. If that command is not found (Python is not installed), reply only with: `Python 3.8+ not found. Install it, then use /plan-check again.` and stop.
   - Add `--owner $ARGUMENTS` if an owner was given.
   - Add `--lang vi` if the user writes Vietnamese. Any `templates/plan-check.<lang>.md` works.
   - Add `--base origin/<branch>` if work merges into a branch other than the repo default (for example a release branch).
   - Add `--plan <file>` if the plan CSV is not at `plan.csv`, `.agents/plan.csv` or `docs/plan.csv`.
   The script reads the plan, the base-branch history and every MR/PR, and checks who each task blocks.
2. Return exactly the report it printed: the verdict line (on or behind schedule) with the one-line summary under it, then the task table. The blockers are a column of the table, not a separate list. Name tasks by id only. Do not reword or reorder the table.
3. Read the section `## Standup checks` of `.agents/wiki/working-process.md`. Run each check on its lines (read-only) and print, under the table, one short line per check that FAILS. Print nothing for checks that pass. If the section is empty, say so in one line.
4. Then, short and separate, what needs the user's decision. For each task listed as "merged but still not marked done", ask the user to confirm, then set its `status` cell to `done` in `plan.csv`. Never mark a task done whose Git column is not MERGED.
5. If the user names a dependency the plan lacks, add its id to the `depends` cell of the task that waits (ids separated by `;`).

Rules
- "No merge on the base branch" does not mean "not done": the work may sit on an open MR, or have been squash-merged under another id. Say "not started" only when the Git column says NONE.
- If the report says the open/closed state of MRs is not verified, tell the user: a closed MR may be shown as open, and a task merged under another task's stacked MR may read as not merged. A token in `PLAN_CHECK_TOKEN` (or `GITLAB_TOKEN` / `GITHUB_TOKEN`) fixes both.
- Read-only: never merge, never push, never edit the plan before the user confirms.

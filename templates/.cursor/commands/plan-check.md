Run the standup check. It is read-only until step 3.

1. Run `python .agents/plan-check/plan_check.py`.
   - Add `--owner <owner>` if an owner was given.
   - Add `--lang vi` if the user writes Vietnamese. Any `templates/plan-check.<lang>.md` works.
   - Add `--base origin/<branch>` if work merges into a branch other than the repo default (for example a release branch).
   - Add `--plan <file>` if the plan CSV is not at `plan.csv`, `.agents/plan.csv` or `docs/plan.csv`.
   The script reads the plan, the base-branch history and every MR/PR, and checks who each task blocks.
2. Return exactly the report it printed: the verdict line (on or behind schedule) with the one-line summary under it, then the task table. The blockers are a column of the table, not a separate list. Name tasks by id only. Do not reword the table.
3. Then, short and separate, what needs the user's decision. For each task listed as "merged but still not marked done", ask the user to confirm, then set its `status` to `done` in the plan CSV (use `python .agents/tools/plan.py set-status <id> done` if the project has that tool, otherwise edit the cell). Never mark a task done whose Git column is not MERGED.
4. Run each line under "Project checks" below (read-only commands). Print, under the table, one short line per check that FAILS; print nothing for checks that pass.
5. If the user names a dependency the plan lacks, add its id to the `depends` column of the task that waits (ids separated by `;`). If a task delivers an ADR, put its number in `adr`.

Rules
- "No merge on the base branch" does not mean "not done": the work may sit on an open MR, or have been squash-merged under another id. Say "not started" only when the Git column says NONE.
- A task whose ADR is still `proposed` keeps blocking its dependants even when the task is done.
- If the report says the open/closed state of MRs is not verified, tell the user: a closed MR may be shown as open, and a task merged under another task's stacked MR may read as not merged. A token in `PLAN_CHECK_TOKEN` fixes both.
- Read-only: never merge, never push, never edit the plan before the user confirms.

## Project checks
<!-- PROJECT-CHECKS -->

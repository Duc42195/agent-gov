---
description: Finish a task - run the gate, commit, open the MR/PR, update plan.csv
argument-hint: <task-id>
allowed-tools: Bash, Read, Edit
---
Finish task `$ARGUMENTS`. Stop at the first step that fails and report it. Never merge.

1. Read `plan.csv` and confirm a row with id `$ARGUMENTS` exists. If not, stop.
2. Run `{{GATE_CMD}}`. If it fails, stop and show the failure. Do not commit.
3. Make sure the branch is `<type>/<task-id>-<slug>`; if you are on `{{DEFAULT_BRANCH}}`, create it. Commit this task's changes as `type(scope): subject (<task-id>)`, imperative and lowercase.
4. Push the branch and open the MR/PR with the commit subject as title and the task id in the body (`gh pr create` for GitHub, `glab mr create` for GitLab).
5. Edit the task's row in `plan.csv`: `status` = `done`, `mr` = the MR/PR link, `review` = `pending`, `updated` = today. Change only that row.
6. If an external tracker is configured (see the AGENTS.md profile), update it with the tracker's own CLI or API, following the notes in `.agents/wiki/working-process.md`.
7. Report: task id, commit, MR/PR link, who reviews (`reviewer` column or the maintainer in `.agents/roles.md`), and the next `todo` task for this owner.

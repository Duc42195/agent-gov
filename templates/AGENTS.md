# AGENTS.md — {{PROJECT_NAME}}

The single rulebook for every person and every AI tool in this repo. Other AI config files only point here.

## Profile
- What: <one line>
- Goal: <one line>
- Stack: <stack, or "docs only">
- Research project: {{IS_RESEARCH}}
- Task id prefix: `{{TASK_KEY}}` · Git host: {{GIT_HOST}} · Default branch: `{{DEFAULT_BRANCH}}` · External tracker: {{EXTERNAL_TRACKER}}
- Gate command: `{{GATE_CMD}}`

## Where things live (read the relevant one before you act)
| Need | Where |
|---|---|
| What is planned, who owns it, how far, reviewed or not | `.agents/plan.csv` (source of truth for tasks) |
| Why the system is the way it is | `.agents/adr/` (one accepted ADR per topic) |
| Lessons, gotchas, running "why" | `.agents/wiki/` |
| Who is who | `.agents/roles.md` |

An accepted ADR beats the wiki for formal decisions. The wiki holds the running why.

## Working rules
1. Work from `plan.csv`. Pick a task assigned to you (or unassigned), then `python .agents/tools/plan.py set-status <id> in-progress`.
2. Branch `<type>/<task-id>-<slug>`. Commit `type(scope): subject (<task-id>)`, imperative, lowercase.
3. Close a task with `/done <task-id>`. It commits, opens the MR/PR, updates `plan.csv`. It never merges.
4. A change is reviewed by someone other than its author before merge. The reviewer sets `review` to `approved` or `changes` in `plan.csv` (`plan.py set-review`).
5. The gate (`{{GATE_CMD}}`) must pass before `/done` commits.
6. Git and the MR/PR state are the truth. If `plan.csv` disagrees, fix the CSV. Never mark a task done that is not done.
7. No secrets in the repo. Tokens live in environment variables or `.agents/state/` (git-ignored).

## Knowledge capture (hard rule)
In the same session it happens, append (never delete, never rewrite history):
- a decision → `.agents/wiki/decisions-log.md` (and an ADR if it is a design-level choice)
- an error you hit and fixed → `.agents/wiki/learnings.md` as symptom · root cause · fix · lesson
- an open question opened, changed or closed → `.agents/wiki/open-questions.md`
- a process gotcha → `.agents/wiki/working-process.md`
To reverse an earlier call, append a superseding entry that points to the old one.

## Decision integrity
- One topic, one accepted ADR. Before recording a decision, read `.agents/adr/README.md` (index). If the topic already has an accepted ADR, extend it or write a new ADR that supersedes it (old one becomes `superseded-by NNNN`). Two accepted ADRs on one topic must never exist.
- Every accepted ADR has a `Topic:` line. Topics must fit together into one coherent system: if a new ADR conflicts with another topic, resolve it before accepting.
- Run `python .agents/tools/check_adr.py` before merging anything that touches `.agents/adr/`.
<!-- Research projects ({{IS_RESEARCH}} = yes) keep the block below; delete it otherwise. -->
- Results: the chosen result of an experiment is an ADR with `Type: result` and a `## Run of record` section (run-id, config, metrics, artifact path). A better run gets a new ADR that supersedes the old one. Every table, number and figure in a report, paper or wiki page carries its run-id and must equal the accepted result ADR. If it does not, regenerate it from that ADR. Do not add captions like "the table above is not from this run". Cite an older run only as `superseded-run-id: <id>`. Check with `python .agents/tools/check_adr.py --reports <paths>`.

## Reading the team record
- Who does what: `owner` column, `.agents/roles.md`.
- How far: `status`, `start`, `end`, `mr`, `updated` columns. `python .agents/tools/plan.py list [--owner NAME] [--status STATUS]` prints it with a done-percentage and marks late tasks.
- Is it right: `reviewer` and `review` columns, plus a green gate.

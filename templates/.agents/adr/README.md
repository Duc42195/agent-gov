# Architecture Decision Records

One ADR = one decision. **One topic has exactly one accepted ADR.** A later decision on the same topic supersedes the earlier one; nothing is deleted.

## Rules
- File name `NNNN-kebab-title.md`, next free number. Copy `0000-template.md`.
- `Status`: `proposed` · `accepted` · `accepted-in-part` · `superseded-by NNNN`.
- `Topic`: one short slug for the part of the system or the experiment this decides (`auth-method`, `dataset-split`, `exp-baseline`). Required for every accepted ADR.
- Conditions on an acceptance are written in the ADR file, not in a chat or review thread.
- Superseding: set the old ADR to `superseded-by NNNN`, mention the old number in the new ADR's Context, update the index below.
- `Type: result` ADRs record the chosen outcome of an experiment (see `Run of record`).
- Keep the index below current. `python .agents/tools/check_adr.py` checks numbering, index, topics and run-ids.

## Index
| # | Title | Status |
|---|---|---|

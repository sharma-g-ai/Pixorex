## Task
<!-- Title must start with the task ID, e.g. "PX-04-T01: Domain 1 schema" -->
- Task: PX-__-T__
- Spec requirement(s): REQ-__.__
- Contract ref(s): __ (or n/a)
- Autonomy grade: A0 / A1 / A2 / A3
- Operator (ran the agent): @__

## What changed
<!-- 2–4 lines. Behaviour, not a file list. -->

## Tests
- [ ] Failing tests written first; GIVEN/WHEN/THEN from the spec covered
- [ ] RLS isolation test added/updated (any data access)
- [ ] Role-boundary test added/updated (any endpoint)

## Checklist
- [ ] Diff ≤ 300 lines, ≤ 5 files of real change
- [ ] Audit row written in the same transaction for every *Audit* write
- [ ] No OPEN/BLOCKED item built; no new table or column
- [ ] Contract updated in this PR if an endpoint changed
- [ ] Spec and `STATE.md` updated
- [ ] AI review report attached below (PASS, or WARN with reasons)

## AI review report
<!-- Paste or link the report -->

## Reviewer reading order
AI review report → spec diff → test diff → code. Reviewers: you did not operate the agent on this task.

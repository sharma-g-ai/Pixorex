# Task: PX-XX-TNN — <short title>

> Copy to `tasks/PX-XX-TNN.md` (or paste into the Jira ticket). One task = one fresh agent session = one PR.

| Field | Value |
|---|---|
| Task ID | PX-XX-TNN |
| Spec | `specs/SPEC-PX-XX.md` → requirement(s) REQ-__ |
| BRD story | US-___ |
| Bounded context | BC-__ (<name>) |
| Autonomy grade | A0 / A1 / A2 / A3 (strictest applies if multiple contexts) |
| Operator | <name> |
| Reviewer | <name> (not the operator) |
| Architect co-sign needed | Yes (A0/A1) / No |
| Wave / sprint | S_ |
| Depends on | PX-XX-TNN (must be merged first) |

## Goal
One or two sentences: what behaviour exists after this task that did not before.

## Acceptance (GIVEN / WHEN / THEN)
1. GIVEN … WHEN … THEN …
2. GIVEN … WHEN … THEN …

## Files in scope (max 5)
- `path/to/file.py`
- `tests/.../test_file.py`

## Out of scope
- Anything not listed above. If it seems necessary, stop and ask the spec owner.

## Required tests
- [ ] Unit tests for the new logic
- [ ] Integration test for the endpoint / repository
- [ ] RLS isolation test (BU A cannot read or write BU B) — required for any data access
- [ ] Role-boundary test (each role sees only its scope) — required for any endpoint

## Constraints from the constitution that apply
- e.g. repository layer only for DB access; no new dependencies; audit event on state change

## Agent instructions
- Write failing tests first, then implement.
- List assumptions and open questions before coding.
- Stop if the task exceeds 5 files / 200 lines, touches an A0 area, or conflicts with CONSTITUTION.md.

## Done checklist
- [ ] Tests pass locally and in CI
- [ ] Secret scan and SAST clean
- [ ] AI review report attached to PR
- [ ] Diff ≤ 300 lines; PR title starts with task ID
- [ ] Spec updated if behaviour changed
- [ ] `STATE.md` updated

# GSD and the delivery playbook: who owns what

**Status: proposed.** For the two architects to approve. It is not part of the constitution until it is merged by a PR approved by both (CONSTITUTION §10).

The repo has two layers. The root files (`CONSTITUTION.md`, `ARCHITECTURE.md`, `STATE.md`, `specs/`, `TASK_TEMPLATE.md`, `start-session.sh`) are the team's delivery playbook. `.planning/` is the GSD layer, created by the ingest of the same documents. This note says which layer decides what, so the two do not overlap.

## Who owns what

| Question | Owner | Where |
|---|---|---|
| What V1 does and does not do | Playbook | `docs/PRD.md` |
| Tables, columns, keys, status values | Playbook | `docs/data-model.md` and `docs/data-model/` (frozen) |
| Endpoints, bodies, errors | Playbook | `contracts/` and `docs/api-contracts.md` |
| Non-negotiables, autonomy grades, gates G1 to G5, PR rules | Playbook | `CONSTITUTION.md` |
| Which tasks exist, who is on them, their status | Playbook | root `STATE.md` task board |
| Decisions on OPEN items | Playbook | root `STATE.md`, Decisions (CONSTITUTION §0) |
| How a phase is broken into plans, plan steps, execution and verification notes | GSD | `.planning/` |
| Roadmap by phase | GSD, mirroring the sprints | `.planning/ROADMAP.md` (sprint dates come from CONSTITUTION §6) |

## Rules

1. **GSD never edits the playbook files.** That means root `STATE.md`, `CONSTITUTION.md`, `ARCHITECTURE.md`, `specs/`, `contracts/`, `docs/PRD.md` and `docs/data-model*`. The operator updates their own `STATE.md` row in the same PR.
2. **One GSD plan is one PX task.** The plan name and every commit message start with the task ID (for example `PX-04-T01`). A plan stays within 5 files and 200 lines, and becomes one PR of at most 300 lines.
3. **Blocked means not planned.** Requirements marked BLOCKED, OPEN or `x-decision-pending` are left out of plans until the decision is recorded in root `STATE.md`. When it is recorded, the same PR updates the matching entry in `.planning/REQUIREMENTS.md`.
4. **Autonomy grades apply to plans.** A0 areas (Keycloak realm and authenticators, request-context middleware, RLS and grants, Vault loading): agents write tests only; people write the implementation. A1 areas: a person reviews the security- or integrity-relevant logic, and an architect co-signs.
5. **The playbook wins.** If a GSD plan and the constitution disagree, stop and raise it. Do not resolve it inside the plan.
6. **Gates are not skipped.** GSD verification does not replace G1 (spec signed), G2 (first PR per context), G3 (two approvals, AI review, coverage, contract lint) or G4 (sprint acceptance).

## Open question for the architects

`start-session.sh` builds a context bundle and refuses to start if the operator already has a task `in_progress` in `STATE.md`. GSD has its own plan-and-execute loop. Decide whether `start-session.sh` stays the session starter or GSD's execute step replaces it. Until then: set your `STATE.md` row to `in_progress` first, and give the agent the same context order (constitution, task, spec, `STATE.md`, at most 5 named files, the relevant ARCHITECTURE section, the relevant contract operations).

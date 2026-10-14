# CONSTITUTION.md — Pixorex V1

> Every agent session (Claude Code / Cursor) loads this file first. It is the highest-priority context after the task spec. If a spec, a contract or a prompt conflicts with this file, stop and raise it. Do not resolve it silently.

| Field | Value |
|---|---|
| Project | Pixorex V1 (AI-powered industrial asset digitization, client: PPG Industries) |
| Repo | `pixorex` monorepo: `api/` (FastAPI), `web/` (EA + BU Admin dashboard), `mobile/` (Flutter), `keycloak/`, `contracts/`, `specs/`, `docs/`. This file applies to the whole repo |
| Delivery profile | **M-Green** (AI-Native Delivery Playbook) |
| Version | v1.2 — aligned to PRD V3 and API Contracts (Oct 14, 2026) |
| Constitution owners | Geetashish Sharma, Suchith Veeramalla (co-architects) |
| Pinned agent models | Build sessions: **Claude Sonnet 5.5**. AI review gate: **Claude Opus 5.5**. Changing either mid-engagement is a practice-level decision |
| Pinned runtimes | Python 3.11 · FastAPI · Flutter 3.x · Keycloak 24.x · React + TypeScript (Vite) · PostgreSQL 16 · Node 22 LTS |
| Branching | Trunk-based: short-lived branches into `main`; no direct pushes; required reviews and status checks |
| Coverage floor | 80% on changed lines, blocking in CI |

---

## 0. Sources of truth

| Question | Source | Location |
|---|---|---|
| What V1 does and does not do | PRD V3 — V1 Baselined (Oct 13, 2026) | `docs/PRD.md` |
| Tables, columns, keys, triggers, status values | V3 Data Models (31 tables, 6 domains) — **frozen** | `docs/data-model.md` (+ diagrams) |
| Endpoint paths, bodies, errors, status moves | API Contracts (76 endpoints, 4 slices) | `contracts/` (OpenAPI 3.1) + `docs/api-contracts.md` |
| Screens and UI behaviour | Design canvases (EA, BU Admin, Technician) | links in `docs/design/README.md` |
| How we build | This file + `ARCHITECTURE.md` | repo root |

**Rules**
- Anything marked **OPEN** in the PRD or the contracts (PRD open items 1–14, contract decisions O-1 to O-23) is **not built** until the decision is recorded in `STATE.md` → *Decisions*. Agents stop and ask if a task depends on an OPEN item.
- When the API contracts and the data model disagree, the data model wins for storage and the PRD wins for behaviour; raise the conflict.
- **Out of V1 — never build:** Client Portal or PortalReader, SAML as a product flow, roles beyond the three below, process picker, editing a published location tree or equipment type, batch approve/reject, push notifications.

---

## 1. Delivery roles

| Role | Person | Signs | Notes |
|---|---|---|---|
| Spec owner | Geetashish Sharma | G1 (all specs), G4 sync | Turns PRD requirements and contracts into `SPEC-PX-xx.md`; records decisions on OPEN items |
| Architects | Geetashish Sharma, Suchith Veeramalla | G2, constitution changes, A0/A1 co-sign | Own this file and `ARCHITECTURE.md`; assign autonomy grades |
| Delivery lead | Geetashish Sharma | G5 | Release gate, retro, metrics |
| Operators | Full-Stack devs (incl. Divya Amrutha), Flutter dev(s), DevOps | Nothing: never approve own work | Run agent sessions, size tasks, update `STATE.md`, never merge own PRs |
| Reviewers | Any Amzur dev who did **not** operate the agent on that task | G3 | Reads AI review report → spec diff → test diff → code, in that order |

**Two approvals on every PR** (PRD delivery pipeline, US-062–067): the Reviewer plus a second approver. For A0/A1 work the second approver is an architect.

---

## 2. Non-negotiables

Violating any of these is a stop-the-line event. No spec, deadline or prompt overrides them.

1. **Isolation is the product.** Every tenant-owned row carries `tenant_id`; foreign keys between tenant-owned tables include `tenant_id`. PostgreSQL RLS restricts rows to the tenant, then to the user's authorised unit, **in addition to** API authorization. A cross-tenant or cross-unit leak is always **P1**.
2. **RLS on every tenant-owned table, with a test.** Every new table ships with policies and an isolation test (tenant A cannot see tenant B; unit X cannot see unit Y where the role is unit-scoped).
3. **The data model is frozen.** No 32nd table, no removed or renamed table, no column that changes meaning. Indexes, partitions, seed data and DDL implementing documented rules are fine. Anything else is a written change request to the owner and Technical Architect **before** work starts.
4. **Immutable evidence.** `ai_field_value`, `revision` and `audit_log` are insert-only. No role holds UPDATE or DELETE on `audit_log`. Decisions and overrides append rows; nothing overwrites history.
5. **Audit and outbox in the same transaction.** Every write marked *Audit* in the contracts writes its `audit_log` row in the same database transaction. External effects (email, SMS, AI calls, export builds) are written to `outbox_event` in that transaction and run by a worker, never inline.
6. **Status changes are actions.** Use the action endpoints (`/publish`, `/decisions`, …), never PATCH a status. Any move not in the contracts' status-move table returns **409 invalid-state**.
7. **Auth is human-written.** Sign-in codes, lockout and sessions live in Keycloak. The API has **no** sign-in, code or lockout endpoints. No agent proposes credential, token or session patterns (A0).
8. **One path to AI.** Client data reaches a model provider only through the AI Inference Proxy. The mobile app holds no provider key. PII and operational metadata are stripped before any call.
9. **No model training on PPG data** without explicit contractual pre-clearance.
10. **Secrets live in Vault**, loaded at container start: never in code, env files, config files or CI variables. The secret-scan gate is never bypassed.
11. **Synthetic data only** until a vetted US environment exists. Real PPG data never touches local machines, CI, India E2E, logs, backups or provider test payloads (AT-18). Escalate anything that may be export-controlled.
12. **Private storage.** MinIO is private; images are served only through object-specific signed URLs (15 min) issued after a fresh authorization check.

---

## 3. Architecture principles

(Detail in `ARCHITECTURE.md`; these are the rules agents follow.)

- **Layering (FastAPI):** `router → service → repository`. Routers validate and delegate; services hold rules and transactions; repositories are the only code touching the database.
- **Request context:** one middleware validates the token, loads the app user and device session, checks revocation, and sets the RLS context (`SET LOCAL`) for the transaction. Nothing else sets RLS context.
- **Roles from the database, not the token.** The token proves identity and tenant; `user_unit_role` decides what the user may do in the active unit.
- **Two independent scan statuses** (`processing_status`, `review_status`); transitions live in one service per status.
- **Idempotency:** creates take `Idempotency-Key`; for scans the key is `client_capture_id`.
- **Errors:** RFC 9457 `application/problem+json`; the `type` URI is the stable code listed in the contracts.
- **Contract first:** the OpenAPI files in `contracts/` are the interface. Changing an endpoint means changing the contract in the same PR, linted by Spectral.
- **Reuse first:** check shared patterns (outbox, audit writer, request context, offline queue) before writing new ones.
- **Observability:** structured JSON logs with `correlation_id`; no PII, tokens or secrets in logs.

---

## 4. Conventions

| Area | Rule |
|---|---|
| Task size | ≤ 5 files and ≤ 200 lines changed; one task per fresh agent session |
| Task ID | `PX-<spec>-T<nn>` (e.g. `PX-04-T03`) |
| Commit | `<task-id>: summary` |
| Branch | `<task-id>-short-slug`; lives ≤ 2 days |
| PR | Title starts with task ID; **≤ 300 lines diff**; links spec requirement(s) and contract ref(s); uses the PR template |
| Tests | Every requirement has ≥ 1 GIVEN/WHEN/THEN test. 80% coverage on changed lines |
| API names | Paths kebab-case, path params camelCase, JSON fields snake_case, UTC RFC 3339 dates, cursor pagination (`limit`, `cursor`) |
| DB names | As in the Data Models document. Do not rename |
| Python / Dart / TS | Ruff + mypy (strict on `app/auth`, `app/core`) · standard Dart lints · ESLint + strict TS |
| Dependencies | New dependency needs a one-line justification in the PR |
| Docs | Spec updated in the same PR as the behaviour change (G4 sync) |

---

## 5. Autonomy grades and bounded contexts

| Grade | Meaning |
|---|---|
| **A0** | Human-only. No unsupervised agent. Agent may write tests only. Architect co-signs |
| **A1** | Agent implements; human reviews the security- or integrity-relevant logic specifically; architect co-signs; AI review required |
| **A2** | Agent implements; AI review required; two approvals |
| **A3** | Agent implements; CI green and coverage floor suffice; two approvals. Presentational UI and config scaffolding only |

| ID | Context | Spec | PRD | Grade | Rules |
|---|---|---|---|---|---|
| BC-01 | Identity, sessions & invites | SPEC-PX-01 | FR-1.4–1.8 | **A0** (Keycloak, token middleware, session revocation) · A1 (invite endpoints) | Keycloak realm, OTP authenticators and request-context middleware are human-written |
| BC-02 | Mobile capture & offline queue | SPEC-PX-02 | FR-4.1–4.3 | A1 | AES-256 queue and key handling human-reviewed; architect co-signs encryption tasks |
| BC-03 | AI Inference Proxy & extraction | SPEC-PX-03 | FR-4.4–4.9 | A1 | Prompt building, PII stripping, injection defence and attempt budget human-reviewed |
| BC-04 | Tenancy, roles & RLS | SPEC-PX-04 | FR-1.1–1.3 | **A0** (RLS, grants, role checks) · A2 (CRUD around them) | RLS SQL, DB grants and authorization helpers human-written; architect reviews every policy |
| BC-05 | Locations | SPEC-PX-05 | FR-2 | A2 · A1 for publish freeze triggers | Freeze triggers tested with a mutation test |
| BC-06 | Equipment types & extraction contracts | SPEC-PX-06 | FR-3 | A2 · A1 for publish/freeze and contract binding | — |
| BC-07 | Audit, outbox & notifications | SPEC-PX-07 | FR-6.1–6.3 | A1 | Audit write path and grants human-reviewed; insert-only enforced by test |
| BC-08 | Review, delegation & escalation | SPEC-PX-08 | FR-5 | A1 | Self-approval trigger, first-decision guard and override chain human-reviewed |
| BC-09 | Data security | SPEC-PX-09 | NFR | **A0** | Vault, TLS, signed URLs, DLP human-written |
| BC-10 | DevSecOps & resilience | SPEC-PX-10 | EP-10/11 | A1 | DevOps engineer signs off every gate change |
| BC-11 | Exports, quota & retention | SPEC-PX-11 | FR-6.4–6.6 | A1 | DLP, scope checks and purge logic human-reviewed |
| UI | Web screens and Flutter screens | per feature spec | Screens | A2 · A3 for presentational components | Auth and token handling in the clients belong to BC-01 (A0) |

If a task touches more than one context, the **strictest** grade applies.

---

## 6. Gates

| Gate | When | What | Who signs |
|---|---|---|---|
| **G1** | Start of each sprint | Spec approved; every requirement has GIVEN/WHEN/THEN and a contract/PRD ref; OPEN items either decided or excluded | Spec owner + architect |
| **G2** | First PR in each bounded context | Layering, naming, errors, logging, request context and test structure match this file; becomes the baseline agents copy | Architect (personally) |
| **G3** | Every PR | AI review report (PASS, or WARN with accepted reasons) · task ID · suite green · coverage ≥ 80% on changed lines · diff ≤ 300 lines · contract lint clean · two approvals | Reviewer + second approver (architect for A0/A1) |
| **G4** | End of each sprint | Every GIVEN/WHEN/THEN in the sprint's specs exercised; isolation verified at the DB layer; specs synced; demo rehearsed | Verification owner + spec owner |
| **G5** | Sprint 6 | All 18 release tests (AT-01–AT-18) pass with evidence and a named owner; security scan clean; rollback tested | Delivery lead |

Sprint ends (2026): S2 Oct 20 · S3 Nov 03 · S4 Nov 17 · S5 Dec 01 · S6 Dec 15.

---

## 7. Agent working rules

Session context, in order: `CONSTITUTION.md` → the task file → the spec → `STATE.md` → ≤ 5 named files → the relevant `ARCHITECTURE.md` section → the relevant contract operation(s).

The agent **must**: work only on its task; list assumptions and open questions first; write tests first; stop if the task exceeds size limits, touches an A0 area, depends on an OPEN item, or conflicts with this file; never echo secrets, tokens or data.

The agent **must not**: add tables, columns, dependencies, services or AI endpoints; change a contract without the spec owner; disable or loosen a test, lint rule, RLS policy, grant or CI gate; modify A0 code except to add tests; invent requirements.

After every task the operator updates `STATE.md` and commits with the task ID.

---

## 8. Definition of done

- [ ] Two approvals, neither by the operator; architect for A0/A1
- [ ] Tests pass, including RLS isolation and role-boundary tests for any data access or endpoint
- [ ] Coverage ≥ 80% on changed lines; diff ≤ 300 lines
- [ ] Secret scan, SAST, dependency scan and contract lint clean
- [ ] AI review report attached
- [ ] Audit row written in the same transaction for every *Audit* write
- [ ] Spec, contract (if changed) and `STATE.md` updated
- [ ] Runs on the local Compose stack from a clean checkout

---

## 9. Environments

| Environment | Purpose | Data | Status |
|---|---|---|---|
| Local (Docker Compose) | Development and Sprint 2 demo | Synthetic only | **Active** |
| CI (GitHub Actions + Compose) | All tests, incl. RLS and auth | Synthetic only | **Active** |
| India E2E | Build and validation | Synthetic only (export control) | Not yet provisioned |
| US VPS | PPG validation, stakeholder demos | Real client data | Not yet provisioned |
| AWS us-east-1 | Production | Real client data | Not yet provisioned |

Until a vetted US environment exists, no real PPG data is used anywhere. Demos run on the local stack with seeded synthetic data and say so up front. Rehearse every demo on the exact machine and network first.

---

## 10. Change control

This file changes only by PR approved by both architects. Each G5 retro and each material incident ends with: *what should change here?*

| Version | Date | Change | Approved by |
|---|---|---|---|
| v1.0 | Oct 2026 | Baseline from AI-Native Delivery Playbook plan | **[TBD]** |
| v1.1 | Oct 14, 2026 | Monorepo; trunk-based, 80% floor; Sonnet build / Opus review; React + TS; Keycloak-direct sign-in; email + SMS OTP; local-only environments | **[TBD]** |
| v1.2 | Oct 14, 2026 | Aligned to PRD V3 and API Contracts: sources of truth, frozen data model, 3 roles, Client Portal and SAML out of V1, bounded contexts re-cut to PRD domains, two approvals per PR, PostgreSQL 16 / Node 22 | **[TBD]** |

# Pixorex V1

## What This Is

Pixorex V1 is AI-powered industrial asset digitization for PPG Industries, built by Amzur. A field technician photographs an equipment nameplate (1-4 photos), the AI Inference Proxy extracts the fields, the technician verifies each field and submits an immutable revision, and a different person (BU Admin, Enterprise Admin or a trusted delegated technician) approves or rejects that exact revision. All of this happens inside a multi-tenant tenant -> business unit -> location structure that admins configure and publish first. Surfaces: a Flutter mobile app for technicians, a React + TypeScript web dashboard for Enterprise Admins and BU Admins, a FastAPI API plus worker, and Keycloak one-time-code sign-in. There is no Client Portal in V1.

## Core Value

Every nameplate becomes a trustworthy reviewed record (the approved scan, its exact revision and its effective decision), captured fast by a technician, approved by a second person, and never visible outside its tenant and unit. If everything else fails, tenant/unit isolation and immutable evidence must hold (a cross-tenant or cross-unit leak is always P1).

## Business Context

- **Customer**: PPG Industries (client); delivered by Amzur (spec owner and architects: Geetashish Sharma, Suchith Veeramalla)
- **Revenue model**: SaaS-first with customer-hosted as a paid option; V1 builds the dedicated-deployment tier and must not preclude shared deployments later (ARCHITECTURE §3)
- **Success metric ("V1 done")**: all 18 PRD release tests AT-01 to AT-18 pass with evidence and a named owner, plus measurable NFRs: background extraction < 15 s at p95 and upload acknowledgement < 500 ms
- **Strategy notes**: docs/PRD.md (Pixorex PRD V3, V1 Baselined, Oct 13, 2026); BRD v2.1 and V3 Data Models linked in docs/PRD.md

## Requirements

### Validated

(None yet - ship to validate)

### Active

Full list with IDs, phase mapping and status: `.planning/REQUIREMENTS.md`. Scope by area (144 tracked entries: 136 requirements + 8 competing-variant entries):

- [ ] Tenancy, users, roles, sessions, invites, OTP sign-in, lockout, RLS isolation (FR-1.1 to FR-1.8, SPEC-PX-01/04 requirements) - Phase 1
- [ ] Audit log, outbox, worker, local Compose stack, Vault secrets, CI and security gates (FR-6.1, FR-6.2, SPEC-PX-07/10 requirements) - Phase 1
- [ ] Locations authoring and publish freeze (FR-2.1 to FR-2.6) - Phase 2
- [ ] Equipment types, extraction contracts, prompt versions (FR-3.1 to FR-3.7) - Phase 2
- [ ] Mobile capture, offline queue, AI Inference Proxy extraction, attempt budget, type mismatch (FR-4.1 to FR-4.9) - Phase 2
- [ ] Revisions, field verdicts, Submit Anyway, decisions, rework, delegation batches, escalation, notifications (FR-5.1 to FR-5.8, FR-6.3) - Phase 3
- [ ] Scoped CSV export, monthly quota, retention (FR-6.4 to FR-6.6) - Phase 4
- [ ] Release gate: all 18 release tests, performance, residency, backup/DR, deployment gate (GATE-G5, REQ-10.S6, NFRs) - Phase 5
- [ ] 16 screens (EA-01 to EA-04, BU-01 to BU-05, MOB-01 to MOB-07) delivered in the phase that owns their data

### Out of Scope

Excluded by CONSTITUTION §0 / PRD V1 scope. Nothing here is built or promised in V1.

- Client Portal, PortalReader persona, client login, publication projection, portal CSV (UX-006, US-006, EP-06 US-040 to US-043) - PRD post-V1; CONSTITUTION §0 never-build; AT-17 proves no such surface or table dependency exists
- SAML / enterprise SSO as a product flow (US-002) - admins sign in by email one-time code; admin MFA expectation is a separate open decision (P-4)
- Roles beyond the three (Reviewer, Super Admin, portal user, extra dashboard roles) - `is_trusted_reviewer` is a delegated capability, not a fourth role (O-1 settled by PRD)
- Process picker / process selection - one hidden default business process per unit (FR-1.1)
- Editing a published location tree or published equipment type; version-two type editing; clone and deactivate (O-4); location CSV import (US-035) - publish freezes both; a different type means a new type
- Batch approve / batch reject (US-032) - a review batch is a set of review assignments, never bulk approval
- Push notifications - bell panel and email only
- Quota alerts at 80/95/100 percent and any quota-alert experience; inactive-account detection (US-050, US-052) - alert levels stay tracked in quota_usage for later (contract 3.27 yields to PRD)
- Role change endpoint (O-16) - OPEN, no screen, no V3 rule; not built unless decided
- BU Admin self-service retention UI (US-038), JSON export, export download history, admin action logging (US-047) - deferred by BRD v2.1 to V1.1 or later
- Asset master, on-device VLM inference, ERP/CMMS integration, advanced analytics - post-V1
- Phase 2 items: Tier 2 SaaS, OAuth2/OIDC mobile auth, in-app billing engine, multi-language, full WCAG 2.1 AA audit, Helm/Kubernetes packaging, Azure Terraform modules
- A 32nd table, or any column that changes meaning - frozen data model (CON-NN-03); needs a written change request to owner and Technical Architect
- Tablet-native layouts; password flows; provider keys on the mobile app; model training on PPG data; real client data outside a vetted US environment - constitutional and NFR exclusions
- Release Plan positions in the contracts DOC that contradict the PRD (6 roles, SAML+MFA, portal-reads-DB, published-type versioning) - PRD/CONSTITUTION win

## Context

- **Ingest**: bootstrapped on 2026-10-14 from 10 planning docs: CONSTITUTION.md (precedence 0), ARCHITECTURE.md (1), SPEC-PX-01/04/07/10, docs/PRD.md, docs/api-contracts.md, docs/design/README.md, contracts/README.md. Intel in `.planning/intel/`; conflict report in `.planning/INGEST-CONFLICTS.md` (0 blockers, 6 warnings, 9 info; user-approved handling below).
- **Where we are**: Sprint 1 (design) is complete. Sprint 2 (S2) is in progress and ends Tue Oct 20, 2026 with 4 working days left (Oct 15, 16, 19, 20). The four ingested SPECs are Draft, awaiting G1. SPEC-PX-02, 03, 05, 06, 08, 09 and 11 are referenced but not yet written, so detail for Phases 2-5 rests on ARCHITECTURE §12, the PRD and the contracts catalog until those specs pass G1 at the start of each sprint.
- **Referenced but absent from the repo**: docs/data-model.md (frozen V3 Data Models, storage authority), contracts/*.yaml and .spectral.yaml (OpenAPI 3.1), keycloak/realm-pixorex.json, BRD-INDEX.md. REQ-04.01 cannot be verified against the Data Models document until it is available.
- **Sprint calendar (one roadmap phase per sprint)**: S2 ends Oct 20, S3 Nov 03, S4 Nov 17, S5 Dec 01, S6 Dec 15, 2026.
- **S2 demo script** (from the team's root STATE.md): EA signs in by email code and creates unit "Plant 04" and invites its BU Admin; BU Admin accepts, signs in, sees only Plant 04, invites a technician; technician accepts on phone, signs in by SMS and once by email, lands on Home and can switch units; role-gated views of the same seeded data; isolation suite run live; 5 wrong codes produce a 30-minute lock and an audit row. Demo runs on the local stack with synthetic data, stated up front.
- **Root STATE.md** is the team's sprint task board and the CONSTITUTION §0 decision register ("STATE.md -> Decisions"). It is not modified by GSD; `.planning/STATE.md` is GSD project memory.
- **Ingest conflict handling (user-approved)**: reference cycles among docs are benign navigational links. Four competing-variant pairs are kept visible and BLOCKED, with no winner picked: override authority (PRD open item 6), invite authority (PRD open item 5), audit read/export access (no decision ID registered yet), phone-change code ownership (O-12). Requirements depending on open decisions P-1, O-11, O-12, O-13, O-23, P-10, P-3 and other OPEN items are mapped to their phase and marked BLOCKED with the decision ID. Where the contracts DOC disagrees with the baselined PRD/CONSTITUTION on scope (O-1, O-2, O-4, O-6, quota alerts, O-22), the PRD/CONSTITUTION/SPEC position is used.

## Constraints

**Top-authority non-negotiables (CONSTITUTION §2, binding per source text; no ADR is formally Accepted, so none is a locked decision, but all are treated as top-authority rules):**

- **CON-NN-01 Isolation is the product**: every tenant-owned row carries tenant_id and FKs between tenant-owned tables include it; PostgreSQL RLS restricts to the tenant, then the user's authorised unit, in addition to API authorization. A cross-tenant or cross-unit leak is always P1.
- **CON-NN-02 RLS on every tenant-owned table, with a test**: every new table ships policies and an isolation test (tenant A cannot see B; unit X cannot see unit Y for unit-scoped roles).
- **CON-NN-03 The data model is frozen**: 31 tables, 6 domains. No 32nd table, no removed or renamed table, no column that changes meaning. Indexes, partitions, seed data and DDL implementing documented rules are fine.
- **CON-NN-04 Immutable evidence**: ai_field_value, revision and audit_log are insert-only; no role holds UPDATE or DELETE on audit_log; decisions and overrides append rows.
- **CON-NN-05 Audit and outbox in the same transaction**: every write marked Audit writes its audit_log row in the same DB transaction; external effects (email, SMS, AI calls, export builds) go to outbox_event in that transaction and run in a worker, never inline.
- **CON-NN-06 Status changes are actions**: use action endpoints (/publish, /decisions), never PATCH a status; any move outside the contracts' status-move table returns 409 invalid-state.
- **CON-NN-07 Auth is human-written**: sign-in codes, lockout and sessions live in Keycloak; the API has no sign-in, code or lockout endpoints; agents propose no credential, token or session patterns (A0).
- **CON-NN-08 One path to AI**: client data reaches a model provider only through the AI Inference Proxy; the mobile app holds no provider key; PII and operational metadata are stripped before any call.
- **CON-NN-09 No model training on PPG data** without explicit contractual pre-clearance.
- **CON-NN-10 Secrets live in Vault**: loaded at container start; never in code, env files, config files or CI variables; the secret-scan gate is never bypassed.
- **CON-NN-11 Synthetic data only** until a vetted US environment exists; real PPG data never touches local machines, CI, India E2E, logs, backups or provider test payloads (AT-18). Escalate anything possibly export-controlled.
- **CON-NN-12 Private storage**: MinIO is private; images are served only via object-specific signed URLs (15 min) issued after a fresh authorization check.

**Other constraints:**

- **Tech stack**: Flutter 3.x mobile (iOS 16+, Android 10+); React + TypeScript (Vite) web on Node 22 LTS; Python 3.11 + FastAPI API and worker (router -> service -> repository layering); Keycloak 24.x; PostgreSQL 16; MinIO (private, versioned); HashiCorp Vault; Mailpit locally; docker-compose local and CI stack; GitHub Actions. Monorepo `pixorex`: api/, web/, mobile/, keycloak/, contracts/, specs/, docs/.
- **Documentation authority (CON-S1..S4)**: scope = docs/PRD.md; tables/columns/keys/triggers/status values = V3 Data Models (frozen); endpoints/bodies/errors/status moves = API Contracts (76 endpoints, 4 slices); screens = design canvases (docs/design/README.md); how we build = CONSTITUTION + ARCHITECTURE. Storage conflicts: data model wins; behaviour conflicts: PRD wins; raise the conflict.
- **OPEN items are not built (CON-S2)**: anything marked OPEN in the PRD (items 1-14, labelled P-n in ARCHITECTURE) or contracts (O-1 to O-23) is not built until the decision is recorded in the root STATE.md -> Decisions. Agents stop and ask.
- **Timeline**: one phase per sprint; S2 ends Oct 20, S3 Nov 03, S4 Nov 17, S5 Dec 01, S6 Dec 15, 2026. Gate G1 at the start of each sprint; G4 at each sprint end; G5 at Sprint 6.
- **Environments**: Local (Compose) and CI (GitHub Actions + Compose) are active and synthetic-only. India E2E (synthetic only), US VPS and AWS us-east-1 (real client data) are not provisioned; procurement decision is needed by Sprints 3-4 for real-device offline sync testing, DAST, TLS 1.3/HSTS evidence, WAL-based RPO and the S6 release tests. Real client data stays on US infrastructure only.
- **Delivery and quality**: two approvals on every PR (architect for A0/A1 work); task size <= 5 files and <= 200 lines, PR diff <= 300 lines; 80% coverage on changed lines, blocking in CI; Ruff + mypy (strict on app/auth, app/core), ESLint + strict TS, Dart lints; contract changes in the same PR as behaviour, Spectral-linted; build sessions pinned to Claude Sonnet 5.5 and AI review gate to Claude Opus 5.5.
- **Autonomy grades**: A0 (human-only: Keycloak, token middleware, session revocation, RLS policies, grants, role checks, Vault/TLS/signed URLs/DLP), A1 (agent implements, human reviews integrity logic, architect co-signs), A2, A3 (presentational UI and config scaffolding only). Strictest grade applies across contexts.
- **Performance**: API p95 < 20 s excluding extraction; upload ack < 500 ms; background extraction < 15 s p95; mobile launch < 3 s on mid-range Android; scale 10 units per client, 10-20 users per unit, 1,000 scans per day per unit.
- **Security and compliance**: AES-256 at rest, TLS 1.3 only with HSTS >= 1 year, revocation effective within 60 s, audit log 1 year online + 3 years archived (floor cannot be lowered), RTO <= 4 h and RPO <= 1 h, breach notification within 24 h, US data residency.
- **Sea Stock boundary**: separate repo and constitution; shared Keycloak container (separate realm) and Vault (separate path); separate PostgreSQL instance and MinIO buckets.

## Key Decisions

No decision is formally Accepted (no ADR carries Accepted status; CONSTITUTION change-control approvals for v1.0-v1.2 are [TBD]). Every row is therefore recorded as Pending. Rows marked OPEN are explicitly undecided in the sources and gate the requirements named in `.planning/REQUIREMENTS.md`.

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CONSTITUTION non-negotiables CON-NN-01 to CON-NN-12 (see Constraints) | Self-declared binding for the whole repo; "if a spec, contract or prompt conflicts, stop and raise it" | — Pending |
| One roadmap phase per sprint (S2-S6) following ARCHITECTURE §12 | Matches the team's sprint calendar and gates; each phase is a vertical slice | — Pending |
| Three roles only (enterprise_admin, bu_admin, field_technician); delegated reviewer is a capability (ARCH-04) | PRD V3 baseline; O-1 settled by PRD/CONSTITUTION | — Pending |
| Apps sign in with Keycloak directly (Authorization Code + PKCE); OTP by SMS or email for technicians, email only for admins; no passwords, no SAML (ARCH-05) | Constitution §2.7; PRD FR-1.5; keeps credentials out of the API | — Pending |
| Keycloak users link to app_user via attributes app_user_id and tenant_id emitted as claims (ARCH-06) | Frozen model has no Keycloak-ID column | — Pending |
| Request pipeline: JWT -> app_user -> user_session -> active unit -> SET LOCAL RLS context -> role check; roles from the database, not the token (ARCH-07, CON-A2/A3) | Revocation must bite within 60 s; one place sets tenant context | — Pending |
| RLS on every tenant-owned table; API connects as a non-owner role without BYPASSRLS; migrations run as a separate owner role (ARCH-08, REQ-04.02) | Defense in depth for isolation | — Pending |
| Frozen 31-table, 6-domain data model; schema built per domain by sprint (ARCH-10) | Constitution §2.3; PRD invariants | — Pending |
| Active unit lives in user_session.active_bu_id keyed by X-Device-Id (O-11, OPEN, proposed) | Keeps the V3 model; token claim alternative from Release Plan | — Pending |
| Tenant and first Enterprise Admin created by an operator-only CLI api/scripts/bootstrap_tenant.py (P-1, OPEN, proposed) | No endpoint or invite covers the first tenant and EA | — Pending |
| user_unit_role authoritative; business_unit.bu_admin_user_id written in the same transaction with a deferred constraint trigger (P-10, OPEN, proposed) | Two sources for the same fact in the frozen model | — Pending |
| Activation and phone-change codes sent and checked by Keycloak required actions; Keycloak listener tells the API (O-12, OPEN, proposed) | Constitution §2.7 forbids API code/lockout endpoints; contracts 1.4-1.5 currently put it in the API | — Pending |
| Lock state for BU-01 read from Keycloak's attack-detection admin API (O-13, OPEN, proposed) | V3 stores no lock state | — Pending |
| Multi-unit invite: accepting one link accepts all pending invites for the email; is_primary = oldest invite's unit (O-23, OPEN, proposed) | Rule not stated in V3 | — Pending |
| SMS via Amzur's existing account; confirm DLT sender and OTP template (P-3, OPEN); email via outbox SMTP adapter, Mailpit locally, provider chosen before a shared environment | Residency and Vault storage apply | — Pending |
| Admin email code as MFA (P-4, OPEN, decision in S2, required before release) | PRD open item 4; not blocking S2 build | — Pending |
| All AI calls through the AI Inference Proxy; max 3 extraction attempts per scan across retries and re-extracts; confidence NULL when unscored (ARCH-13) | Constitution §2.8; PRD FR-4.5, FR-4.7 | — Pending |
| Outbox pattern with FOR UPDATE SKIP LOCKED worker, retry with backoff, at-least-once, idempotent handlers (ARCH-14) | Constitution §2.5; AT-15 | — Pending |
| Two independent scan statuses (processing_status, review_status); transition matrix = contracts' "Status moves" table (ARCH-12) | Resolves P-7 per ARCHITECTURE; PRD says the Data Models diagram is authoritative, so confirm | — Pending |
| Competing-variant pairs stay visible and BLOCKED, no winner picked: override authority (P-6), invite authority (P-5), audit access (unregistered), phone-change codes (O-12) | User-approved conflict handling; owner must record decisions | — Pending |
| Contracts-DOC Release Plan positions yield to PRD/CONSTITUTION; quota alerts excluded from V1; O-22 settled as S2 | INGEST-CONFLICTS info items | — Pending |
| Trunk-based branching, two approvals, 80% changed-line coverage, Sonnet build / Opus review, local-only environments (CONSTITUTION v1.1/v1.2) | Delivery profile M-Green | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-14 after ingest of 10 planning docs*

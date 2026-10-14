# Decisions (synthesized intel)

Sources: CONSTITUTION.md (manifest precedence 0) and ARCHITECTURE.md (manifest precedence 1). Both are typed ADR by manifest only.

Status note applied to every entry: neither source carries a formal `Status: Accepted` marker, so no entry is `locked`. Every entry is recorded as `proposed`. CONSTITUTION.md declares itself binding for the whole repo ("If a spec, a contract or a prompt conflicts with this file, stop and raise it") and its version approvals (v1.0, v1.1, v1.2) are all `[TBD]`. Treat entries tagged "binding per source text" as the highest-authority project rules even though they are not formally locked. Entries tagged OPEN are explicitly undecided in the source.

---

# Part A - CONSTITUTION.md (precedence 0)

## CON-S1: Sources of truth
- source: CONSTITUTION.md §0
- status: proposed
- decision: What V1 does and does not do = PRD V3 V1 Baselined (Oct 13, 2026) at docs/PRD.md. Tables, columns, keys, triggers, status values = V3 Data Models (31 tables, 6 domains, frozen) at docs/data-model.md (+ diagrams). Endpoint paths, bodies, errors, status moves = API Contracts (76 endpoints, 4 slices) at contracts/ (OpenAPI 3.1) + docs/api-contracts.md. Screens and UI behaviour = design canvases linked in docs/design/README.md. How we build = CONSTITUTION.md + ARCHITECTURE.md.
- scope: documentation authority, all of Pixorex V1

## CON-S2: OPEN items are not built
- source: CONSTITUTION.md §0 Rules
- status: proposed
- decision: Anything marked OPEN in the PRD or contracts (PRD open items 1-14, contract decisions O-1 to O-23) is not built until the decision is recorded in STATE.md -> Decisions. Agents stop and ask if a task depends on an OPEN item.
- scope: all tasks, specs, agents

## CON-S3: Data model vs contracts vs PRD tie-break
- source: CONSTITUTION.md §0 Rules
- status: proposed
- decision: When the API contracts and the data model disagree, the data model wins for storage and the PRD wins for behaviour; raise the conflict.
- scope: contracts, data model, PRD

## CON-S4: Out of V1 - never build
- source: CONSTITUTION.md §0 Rules
- status: proposed
- decision: Never build in V1: Client Portal or PortalReader, SAML as a product flow, roles beyond the three defined, process picker, editing a published location tree or equipment type, batch approve/reject, push notifications.
- scope: V1 product scope

## CON-R1: Delivery roles and signing authority
- source: CONSTITUTION.md §1
- status: proposed
- decision: Spec owner (Geetashish Sharma) signs G1 (all specs) and G4 sync, and records decisions on OPEN items. Architects (Geetashish Sharma, Suchith Veeramalla) sign G2, constitution changes, A0/A1 co-sign, own this file and ARCHITECTURE.md, assign autonomy grades. Delivery lead (Geetashish Sharma) signs G5. Operators (Full-Stack devs incl. Divya Amrutha, Flutter dev(s), DevOps) sign nothing, never approve own work, never merge own PRs, run agent sessions, size tasks, update STATE.md. Reviewers (any Amzur dev who did not operate the agent on that task) sign G3 and read AI review report -> spec diff -> test diff -> code, in that order.
- scope: delivery governance

## CON-R2: Two approvals on every PR
- source: CONSTITUTION.md §1
- status: proposed
- decision: Every PR needs the Reviewer plus a second approver (PRD delivery pipeline US-062 to US-067). For A0/A1 work the second approver is an architect.
- scope: pull requests, CI/branch protection

## CON-NN-01: Isolation is the product
- source: CONSTITUTION.md §2.1 (non-negotiable; binding per source text)
- status: proposed
- decision: Every tenant-owned row carries tenant_id; foreign keys between tenant-owned tables include tenant_id. PostgreSQL RLS restricts rows to the tenant, then to the user's authorised unit, in addition to API authorization. A cross-tenant or cross-unit leak is always P1.
- scope: tenant isolation, PostgreSQL RLS, all tenant-owned tables

## CON-NN-02: RLS on every tenant-owned table, with a test
- source: CONSTITUTION.md §2.2 (non-negotiable; binding per source text)
- status: proposed
- decision: Every new table ships with policies and an isolation test (tenant A cannot see tenant B; unit X cannot see unit Y where the role is unit-scoped).
- scope: RLS, migrations, isolation tests

## CON-NN-03: The data model is frozen
- source: CONSTITUTION.md §2.3 (non-negotiable; binding per source text)
- status: proposed
- decision: No 32nd table, no removed or renamed table, no column that changes meaning. Indexes, partitions, seed data and DDL implementing documented rules are fine. Anything else is a written change request to the owner and Technical Architect before work starts.
- scope: data model (31 tables, 6 domains)

## CON-NN-04: Immutable evidence
- source: CONSTITUTION.md §2.4 (non-negotiable; binding per source text)
- status: proposed
- decision: ai_field_value, revision and audit_log are insert-only. No role holds UPDATE or DELETE on audit_log. Decisions and overrides append rows; nothing overwrites history.
- scope: ai_field_value, revision, audit_log

## CON-NN-05: Audit and outbox in the same transaction
- source: CONSTITUTION.md §2.5 (non-negotiable; binding per source text)
- status: proposed
- decision: Every write marked Audit in the contracts writes its audit_log row in the same database transaction. External effects (email, SMS, AI calls, export builds) are written to outbox_event in that transaction and run by a worker, never inline.
- scope: audit_log, outbox_event, all writes

## CON-NN-06: Status changes are actions
- source: CONSTITUTION.md §2.6 (non-negotiable; binding per source text)
- status: proposed
- decision: Use the action endpoints (/publish, /decisions, ...), never PATCH a status. Any move not in the contracts' status-move table returns 409 invalid-state.
- scope: API status transitions

## CON-NN-07: Auth is human-written
- source: CONSTITUTION.md §2.7 (non-negotiable; binding per source text)
- status: proposed
- decision: Sign-in codes, lockout and sessions live in Keycloak. The API has no sign-in, code or lockout endpoints. No agent proposes credential, token or session patterns (A0).
- scope: authentication, Keycloak, API surface

## CON-NN-08: One path to AI
- source: CONSTITUTION.md §2.8 (non-negotiable; binding per source text)
- status: proposed
- decision: Client data reaches a model provider only through the AI Inference Proxy. The mobile app holds no provider key. PII and operational metadata are stripped before any call.
- scope: AI Inference Proxy, mobile app, privacy

## CON-NN-09: No model training on PPG data
- source: CONSTITUTION.md §2.9 (non-negotiable; binding per source text)
- status: proposed
- decision: No model training on PPG data without explicit contractual pre-clearance.
- scope: AI, client data

## CON-NN-10: Secrets live in Vault
- source: CONSTITUTION.md §2.10 (non-negotiable; binding per source text)
- status: proposed
- decision: Secrets are loaded from Vault at container start: never in code, env files, config files or CI variables. The secret-scan gate is never bypassed.
- scope: secrets management, CI

## CON-NN-11: Synthetic data only
- source: CONSTITUTION.md §2.11 (non-negotiable; binding per source text)
- status: proposed
- decision: Synthetic data only until a vetted US environment exists. Real PPG data never touches local machines, CI, India E2E, logs, backups or provider test payloads (AT-18). Escalate anything that may be export-controlled.
- scope: data residency, environments

## CON-NN-12: Private storage
- source: CONSTITUTION.md §2.12 (non-negotiable; binding per source text)
- status: proposed
- decision: MinIO is private; images are served only through object-specific signed URLs (15 min) issued after a fresh authorization check.
- scope: MinIO, image access

## CON-A1: Layering
- source: CONSTITUTION.md §3
- status: proposed
- decision: FastAPI layering is router -> service -> repository. Routers validate and delegate; services hold rules and transactions; repositories are the only code touching the database.
- scope: api/ code structure

## CON-A2: Request context
- source: CONSTITUTION.md §3
- status: proposed
- decision: One middleware validates the token, loads the app user and device session, checks revocation, and sets the RLS context (SET LOCAL) for the transaction. Nothing else sets RLS context.
- scope: api/ middleware, RLS

## CON-A3: Roles from the database, not the token
- source: CONSTITUTION.md §3
- status: proposed
- decision: The token proves identity and tenant; user_unit_role decides what the user may do in the active unit.
- scope: authorization

## CON-A4: Two independent scan statuses
- source: CONSTITUTION.md §3
- status: proposed
- decision: processing_status and review_status are independent; transitions live in one service per status.
- scope: scan lifecycle

## CON-A5: Idempotency
- source: CONSTITUTION.md §3
- status: proposed
- decision: Creates take Idempotency-Key; for scans the key is client_capture_id.
- scope: API creates

## CON-A6: Errors
- source: CONSTITUTION.md §3
- status: proposed
- decision: Errors are RFC 9457 application/problem+json; the type URI is the stable code listed in the contracts.
- scope: API errors

## CON-A7: Contract first
- source: CONSTITUTION.md §3
- status: proposed
- decision: The OpenAPI files in contracts/ are the interface. Changing an endpoint means changing the contract in the same PR, linted by Spectral.
- scope: contracts/, API changes

## CON-A8: Reuse first
- source: CONSTITUTION.md §3
- status: proposed
- decision: Check shared patterns (outbox, audit writer, request context, offline queue) before writing new ones.
- scope: shared patterns

## CON-A9: Observability
- source: CONSTITUTION.md §3
- status: proposed
- decision: Structured JSON logs with correlation_id; no PII, tokens or secrets in logs.
- scope: logging

## CON-C1: Conventions
- source: CONSTITUTION.md §4
- status: proposed
- decision: Task size <= 5 files and <= 200 lines changed; one task per fresh agent session. Task ID `PX-<spec>-T<nn>` (e.g. PX-04-T03). Commit `<task-id>: summary`. Branch `<task-id>-short-slug`, lives <= 2 days. PR title starts with task ID, PR diff <= 300 lines, links spec requirement(s) and contract ref(s), uses the PR template. Every requirement has >= 1 GIVEN/WHEN/THEN test; 80% coverage on changed lines. API names: paths kebab-case, path params camelCase, JSON fields snake_case, UTC RFC 3339 dates, cursor pagination (limit, cursor). DB names as in the Data Models document, do not rename. Python/Dart/TS: Ruff + mypy (strict on app/auth, app/core), standard Dart lints, ESLint + strict TS. New dependency needs a one-line justification in the PR. Spec updated in the same PR as the behaviour change (G4 sync).
- scope: naming, task size, PR rules, linting

## CON-C2: Project profile, pinned models and runtimes
- source: CONSTITUTION.md header table
- status: proposed
- decision: Project Pixorex V1 (AI-powered industrial asset digitization, client PPG Industries). Monorepo `pixorex`: api/ (FastAPI), web/ (EA + BU Admin dashboard), mobile/ (Flutter), keycloak/, contracts/, specs/, docs/. Delivery profile M-Green (AI-Native Delivery Playbook). Build sessions pinned to Claude Sonnet 5.5; AI review gate pinned to Claude Opus 5.5; changing either mid-engagement is a practice-level decision. Pinned runtimes: Python 3.11, FastAPI, Flutter 3.x, Keycloak 24.x, React + TypeScript (Vite), PostgreSQL 16, Node 22 LTS. Branching trunk-based: short-lived branches into main; no direct pushes; required reviews and status checks. Coverage floor 80% on changed lines, blocking in CI.
- scope: monorepo, tooling, runtimes, branching

## CON-G1: Autonomy grades
- source: CONSTITUTION.md §5
- status: proposed
- decision: A0 = human-only; no unsupervised agent; agent may write tests only; architect co-signs. A1 = agent implements; human reviews security- or integrity-relevant logic specifically; architect co-signs; AI review required. A2 = agent implements; AI review required; two approvals. A3 = agent implements; CI green and coverage floor suffice; two approvals; presentational UI and config scaffolding only. If a task touches more than one context, the strictest grade applies.
- scope: agent autonomy

## CON-G2: Bounded contexts and grades
- source: CONSTITUTION.md §5
- status: proposed
- decision: BC-01 Identity, sessions & invites (SPEC-PX-01, FR-1.4-1.8): A0 for Keycloak, token middleware, session revocation; A1 invite endpoints. BC-02 Mobile capture & offline queue (SPEC-PX-02, FR-4.1-4.3): A1, AES-256 queue and key handling human-reviewed. BC-03 AI Inference Proxy & extraction (SPEC-PX-03, FR-4.4-4.9): A1. BC-04 Tenancy, roles & RLS (SPEC-PX-04, FR-1.1-1.3): A0 for RLS, grants, role checks; A2 CRUD around them. BC-05 Locations (SPEC-PX-05, FR-2): A2, A1 for publish freeze triggers. BC-06 Equipment types & extraction contracts (SPEC-PX-06, FR-3): A2, A1 for publish/freeze and contract binding. BC-07 Audit, outbox & notifications (SPEC-PX-07, FR-6.1-6.3): A1. BC-08 Review, delegation & escalation (SPEC-PX-08, FR-5): A1. BC-09 Data security (SPEC-PX-09, NFR): A0 (Vault, TLS, signed URLs, DLP human-written). BC-10 DevSecOps & resilience (SPEC-PX-10, EP-10/11): A1, DevOps engineer signs off every gate change. BC-11 Exports, quota & retention (SPEC-PX-11, FR-6.4-6.6): A1. UI Web and Flutter screens: A2, A3 for presentational components; auth and token handling in clients belongs to BC-01 (A0).
- scope: bounded contexts BC-01 to BC-11, UI

## CON-GATE: Delivery gates G1-G5
- source: CONSTITUTION.md §6
- status: proposed
- decision: G1 (start of each sprint; spec owner + architect): spec approved, every requirement has GIVEN/WHEN/THEN and a contract/PRD ref, OPEN items decided or excluded. G2 (first PR in each bounded context; architect personally): layering, naming, errors, logging, request context, test structure match this file; becomes the baseline agents copy. G3 (every PR; reviewer + second approver, architect for A0/A1): AI review report PASS (or WARN with accepted reasons), task ID, suite green, coverage >= 80% on changed lines, diff <= 300 lines, contract lint clean, two approvals. G4 (end of each sprint; verification owner + spec owner): every GIVEN/WHEN/THEN in the sprint's specs exercised, isolation verified at DB layer, specs synced, demo rehearsed. G5 (Sprint 6; delivery lead): all 18 release tests (AT-01 to AT-18) pass with evidence and a named owner, security scan clean, rollback tested. Sprint ends 2026: S2 Oct 20, S3 Nov 03, S4 Nov 17, S5 Dec 01, S6 Dec 15.
- scope: delivery gates, sprint calendar

## CON-AG: Agent working rules
- source: CONSTITUTION.md §7
- status: proposed
- decision: Session context order: CONSTITUTION.md -> task file -> spec -> STATE.md -> <= 5 named files -> relevant ARCHITECTURE.md section -> relevant contract operation(s). Agent must: work only on its task; list assumptions and open questions first; write tests first; stop if the task exceeds size limits, touches an A0 area, depends on an OPEN item, or conflicts with this file; never echo secrets, tokens or data. Agent must not: add tables, columns, dependencies, services or AI endpoints; change a contract without the spec owner; disable or loosen a test, lint rule, RLS policy, grant or CI gate; modify A0 code except to add tests; invent requirements. After every task the operator updates STATE.md and commits with the task ID.
- scope: agent sessions

## CON-DOD: Definition of done
- source: CONSTITUTION.md §8
- status: proposed
- decision: Two approvals neither by the operator (architect for A0/A1); tests pass including RLS isolation and role-boundary tests for any data access or endpoint; coverage >= 80% on changed lines and diff <= 300 lines; secret scan, SAST, dependency scan and contract lint clean; AI review report attached; audit row written in the same transaction for every Audit write; spec, contract (if changed) and STATE.md updated; runs on the local Compose stack from a clean checkout.
- scope: all tasks

## CON-ENV: Environments
- source: CONSTITUTION.md §9
- status: proposed
- decision: Local (Docker Compose) - development and Sprint 2 demo, synthetic only, Active. CI (GitHub Actions + Compose) - all tests incl. RLS and auth, synthetic only, Active. India E2E - build and validation, synthetic only (export control), not yet provisioned. US VPS - PPG validation and stakeholder demos, real client data, not yet provisioned. AWS us-east-1 - production, real client data, not yet provisioned. Until a vetted US environment exists no real PPG data is used anywhere; demos run on the local stack with seeded synthetic data and say so up front; rehearse every demo on the exact machine and network first.
- scope: environments, data residency

## CON-CHG: Change control of the constitution
- source: CONSTITUTION.md §10
- status: proposed
- decision: The file changes only by PR approved by both architects. Each G5 retro and each material incident ends with "what should change here?". Version history: v1.0 (Oct 2026, baseline from AI-Native Delivery Playbook plan), v1.1 (Oct 14, 2026: monorepo; trunk-based, 80% floor; Sonnet build / Opus review; React + TS; Keycloak-direct sign-in; email + SMS OTP; local-only environments), v1.2 (Oct 14, 2026: aligned to PRD V3 and API Contracts: sources of truth, frozen data model, 3 roles, Client Portal and SAML out of V1, bounded contexts re-cut to PRD domains, two approvals per PR, PostgreSQL 16 / Node 22). Approved-by for v1.0, v1.1, v1.2 is [TBD] (absent).
- scope: constitution governance

---

# Part B - ARCHITECTURE.md (precedence 1)

## ARCH-01: What V1 is
- source: ARCHITECTURE.md §1
- status: proposed
- decision: A field technician photographs an equipment nameplate (1-4 photos), the AI Inference Proxy extracts the fields, the technician verifies each field and submits a revision, and a different person approves or rejects that exact revision, all inside a tenant -> business unit -> location structure that admins configure and publish first. The approved scan, its exact revision and its effective decision are the reviewed record. There is no Client Portal in V1.
- scope: V1 product shape

## ARCH-02: Components and technology
- source: ARCHITECTURE.md §2
- status: proposed
- decision: Mobile app Flutter (iOS 16+, Android 10+), mobile/, technician only (sign-in, unit switch, capture, offline queue AES-256 hardware-backed key, My Scans, delegated review), root/jailbreak detection, certificate pinning. Web dashboard React + TypeScript (Vite), web/, EA and BU Admin surfaces (EA-01-04, BU-01-05), no portal route. Backend API Python 3.11 + FastAPI, api/, /api/v1, 76 endpoints in 4 slices, no sign-in endpoints. Workers: same codebase, separate process (outbox worker, extraction runner, scheduled jobs for escalation, batch alerts, retention, export builds). Identity Keycloak 24.x, keycloak/ (one-time-code sign-in, lockout, sessions, realm config as code). Database PostgreSQL 16, 31 tables in 6 domains, RLS on every tenant-owned table. Object storage MinIO (private), photos at /{tenant}/{bu}/{scan}/{photo_no}, versioning on. Secrets HashiCorp Vault (AppRole in deployed environments, dev mode locally). AI: AI Inference Proxy -> OpenAI US endpoints with Zero Data Retention (OPEN P-14), internal only. Email: OPEN (SES earlier plan vs SendGrid/SMTP per BRD v2.1), Mailpit locally, sent only via the outbox worker. SMS: Amzur's existing SMS account (OPEN P-3: name, DLT registration), called by the Keycloak OTP authenticator, credentials in Vault. CI/CD GitHub Actions (see SPEC-PX-10).
- scope: system components, technology stack

## ARCH-03: Environments, topology and delivery model
- source: ARCHITECTURE.md §3
- status: proposed
- decision: docker-compose (local + CI) runs api (FastAPI), worker (outbox/jobs), keycloak (+ pixorex realm import, OTP authenticator jar, theme), postgres 16, minio, vault (dev mode), mailpit. Stages: 0 Local Compose + CI (synthetic, Active); 1 India E2E (synthetic, procurement deferred); 2 US VPS (real data, procurement deferred); 3 AWS us-east-1 (real data, procurement deferred). Dependency: offline sync testing on real devices (S4), DAST on the US VPS, TLS 1.3/HSTS evidence, WAL-based RPO and the S6 release tests need a deployed environment; procurement decision needed by Sprint 3-4. Delivery model (unchanged): SaaS-first, customer-hosted as a paid option; V1 builds the dedicated-deployment tier; the model must not preclude shared deployments later (tenant context is set in one place).
- scope: topology, environments, deployment model

## ARCH-04: Roles
- source: ARCHITECTURE.md §4.1
- status: proposed
- decision: Three roles plus one capability. enterprise_admin: whole tenant (bu_id null), Web. bu_admin: one unit, one active BU Admin per unit, Web. field_technician: one or more units, Mobile. Delegated reviewer: technician with is_trusted_reviewer and an open review_assignment, Mobile (MOB-07). One person = one app_user; each unit = one user_unit_role row. Removing someone from a unit sets removed_at and keeps their account and other units.
- scope: roles, user_unit_role

## ARCH-05: Sign-in design
- source: ARCHITECTURE.md §4.2
- status: proposed
- decision: Apps sign in with Keycloak directly. Technicians: system browser, Authorization Code + PKCE, code by SMS or email (their choice). Admins (EA, BU Admin): same flow from the web app, code by email only; no passwords, no SAML in V1; whether this meets the MFA expectation for privileged roles is OPEN P-4. Lockout: wrong codes counted per account across both channels; the 5th locks sign-in for 30 minutes and unlocks automatically (Keycloak brute-force detection; the custom authenticator must report failures to it). Code-request throttling per user and per destination. Audit: a Keycloak event listener posts sign-in, failure and lockout events to an internal API endpoint, which writes audit_log (category sign_in). Lock state shown to admins (BU-01, contract 1.18) is read from Keycloak's attack-detection admin API (OPEN O-13, proposed).
- scope: authentication, Keycloak, lockout, audit

## ARCH-06: Linking Keycloak users to app_user
- source: ARCHITECTURE.md §4.3
- status: proposed
- decision: The frozen model has no Keycloak-ID column, so the link lives in Keycloak: each Keycloak user carries attributes app_user_id and tenant_id, emitted as token claims by protocol mappers. Keycloak users are created by the API (invite acceptance, tenant bootstrap) through the Keycloak admin API.
- scope: identity linking

## ARCH-07: Request pipeline
- source: ARCHITECTURE.md §4.4
- status: proposed
- decision: Every authenticated call: (1) validate JWT (signature via Keycloak JWKS, expiry, audience), missing/invalid -> 401; (2) read tenant_id and app_user_id claims, load app_user (must be active); (3) load user_session for (user, X-Device-Id), create on first call, revoked_at set -> 401, revocation must bite within 60 seconds (cache <= 60 s); (4) resolve active unit (user_session.active_bu_id; O-11 proposed: keep V3 model, not a token claim) and caller's active roles; (5) open transaction and SET LOCAL app.tenant_id, app.user_id, app.bu_ids, app.is_ea; (6) endpoint authorization: role in target unit ({buId} in path) -> 403 if not held, EA passes for every unit in the tenant, rows of another tenant -> 404. The API connects as a non-owner role that cannot bypass RLS; migrations run as a separate owner role.
- scope: request context middleware, authorization

## ARCH-08: RLS model
- source: ARCHITECTURE.md §4.5
- status: proposed
- decision: Every tenant-owned table: policy tenant_id = current_setting('app.tenant_id')::uuid. Unit-owned tables additionally: bu_id = ANY(app.bu_ids) unless app.is_ea. audit_log: INSERT and SELECT only; no UPDATE/DELETE grant to any role. Exceptions per the model: tenant and the global prompt_version. Required test per table: rows created in tenant A / unit X are invisible to tenant B / unit Y, and writes across the boundary fail.
- scope: RLS policies

## ARCH-09: Tenant bootstrap (OPEN P-1, proposed)
- source: ARCHITECTURE.md §4.6
- status: proposed
- decision: OPEN. No endpoint or invite covers the first tenant and EA. Proposal: an operator-only CLI (api/scripts/bootstrap_tenant.py), run by Amzur, creating the tenant, the first app_user + enterprise_admin role, the Keycloak user with claims, and the default retention_config rows, with an audit row (actor system).
- scope: tenant provisioning

## ARCH-10: Data model domains and invariants (frozen V3, 31 tables)
- source: ARCHITECTURE.md §5
- status: proposed
- decision: Domain 1 Tenancy, users, sign-in (7: tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session) S2. Domain 2 Locations (3: location_hierarchy_version, location_level_rule, location_node) S2 version row created with each unit, S3 rest. Domain 3 Equipment types & contracts (5: equipment_type, equipment_type_version, field_definition, prompt_version, extraction_contract) S3. Domain 4 Scans, photos, extraction (4: scan, scan_photo, extraction_attempt, ai_field_value) S3. Domain 5 Review, delegation, escalation (6: revision, revision_field, review_decision, review_batch, review_assignment, escalation) S4. Domain 6 Audit, notifications, exports, quota, retention (6: audit_log, notification, export_job, quota_usage, retention_config, outbox_event) S2 for audit_log and outbox_event, S4-S5 rest. Invariants from the PRD: tenant_id/created_at/updated_at on every tenant-owned table; composite tenant FKs; insert-only ai_field_value, revision, audit_log; audit_log partitioned by month; triggers freeze published locations and fields and block self-decision; uniqueness rules listed in the PRD; version tables hold version 1 only in V1.
- scope: data model

## ARCH-11: bu_admin_user_id vs user_unit_role (OPEN P-10, proposed)
- source: ARCHITECTURE.md §5
- status: proposed
- decision: OPEN. Proposed: user_unit_role is authoritative; business_unit.bu_admin_user_id is written in the same transaction and a deferred constraint trigger checks they agree.
- scope: business_unit, user_unit_role

## ARCH-12: Scan lifecycle
- source: ARCHITECTURE.md §6
- status: proposed
- decision: Two independent columns. processing_status: queued_on_phone (phone only) -> uploading -> extracting -> ready_to_review / failed -> retake_required. review_status: draft -> waiting_for_approval -> approved / rejected; closed (replaced by retake); discarded. The contracts' "Status moves the API allows" table is the transition matrix (resolves P-7); any other move -> 409 invalid-state. My Scans tabs: Needs action (ready_to_review, rejected, failed, retake_required), In progress (queued_on_phone, uploading, extracting, waiting_for_approval), Approved. Key rules: client_capture_id makes uploads idempotent; at most 3 extraction attempts per scan across retries and re-extracts, then retake only; Submit Anyway lists empty required fields and can never be approved; first valid decision wins (409 for the loser); overrides append linked decision rows; 24-hour escalation to the EA. Effective-decision rule across revisions and overrides: OPEN P-11 (needed before S4).
- scope: scan lifecycle, review

## ARCH-13: AI Inference Proxy
- source: ARCHITECTURE.md §7
- status: proposed
- decision: Internal service (module + worker). Runs the scan's pinned extraction_contract (type version + platform-owned prompt version). Builds the request, strips PII and operational metadata, applies injection defences and per-tenant rate limits, reads provider secrets from Vault, records every call as an extraction_attempt (tokens, cost), writes one insert-only ai_field_value per field (confidence NULL when unscored). Background target < 15 s p95; upload acknowledgement < 500 ms. Whether proxy refusals consume an attempt: OPEN O-20. Ambiguous provider timeouts: OPEN P-12.
- scope: AI Inference Proxy

## ARCH-14: Outbox and jobs
- source: ARCHITECTURE.md §8
- status: proposed
- decision: outbox_event rows are written in the business transaction; the worker claims them (FOR UPDATE SKIP LOCKED), executes with retry and exponential backoff, and records the outcome with the event's correlation id (at-least-once, consumers idempotent, AT-15). Scheduled jobs: 24-hour escalation, batch no-progress alerts (1 day / 1 week), daily retention enforcement, async export builds.
- scope: outbox worker, scheduled jobs

## ARCH-15: Security controls
- source: ARCHITECTURE.md §9
- status: proposed
- decision: Transport TLS 1.3 only, HSTS >= 1 year (evidence needs a deployed environment). At rest AES-256 in PostgreSQL and MinIO, Vault-managed MinIO keys. Secrets from Vault at container start; secret scan blocks commits. Images: private MinIO, 15-minute object-specific signed URLs after a fresh auth check, none after revocation. Access changes (role/scope change or removal) effective within 60 s. Mobile: root/jailbreak detection, certificate pinning, hardware-backed AES-256 local store. Exports: scope recheck + DLP scan before delivery (DLP result storage OPEN O-14). Residency: real data on US infrastructure only; India E2E synthetic only. Backup/DR: daily encrypted snapshots (7 days), MinIO versioning, monthly restore test; 1-hour RPO needs WAL archiving or equivalent (OPEN P-13); RTO <= 4 h.
- scope: security, backup, DR

## ARCH-16: API conventions
- source: ARCHITECTURE.md §10
- status: proposed
- decision: REST + JSON under /api/v1; Bearer token on every call except invite preview/accept, /health, /ready; tenant from the token, never the URL; unit in the path as {buId}; X-Device-Id header on every app call; UUID ids with display numbers (record_no, batch_no); cursor pagination; RFC 9457 errors; Idempotency-Key on creates; no ETags (state checks give 409); status changes are POST actions; signed URLs 15 min, export links 1 hour.
- scope: API conventions

## ARCH-17: Repository layout and CODEOWNERS
- source: ARCHITECTURE.md §11
- status: proposed
- decision: Root: CONSTITUTION.md, ARCHITECTURE.md, STATE.md, TASK_TEMPLATE.md, BRD-INDEX.md, start-session.sh, docker-compose.yml. contracts/ (common.yaml, slice-*.yaml, .spectral.yaml, README.md); docs/ (PRD.md, data-model.md, api-contracts.md, design/README.md); specs/ (SPEC-PX-01 to SPEC-PX-11); tasks/ (PX-XX-TNN.md); api/ (app/{routers,services,repositories,auth,core,proxy,workers}, migrations/, scripts/{bootstrap_tenant.py,seed_synthetic.py}, tests/{unit,integration,isolation,contract}); keycloak/ (realm export, OTP authenticator Java SPI, event listener, theme); web/; mobile/; .github/{CODEOWNERS,workflows/,PULL_REQUEST_TEMPLATE.md}; .claude/ai-review-prompt.md. CODEOWNERS: api/app/auth/, api/migrations/, keycloak/, .github/workflows/ -> architects (+ DevOps for workflows).
- scope: repository structure, code ownership

## ARCH-18: Spec map
- source: ARCHITECTURE.md §12
- status: proposed
- decision: SPEC-PX-01 Identity/sessions/invites (FR-1.4-1.8; contracts 1.1-1.11; S2). SPEC-PX-02 Mobile capture & offline queue (FR-4.1-4.3; 2.21-2.23, 2.27; S3-S4). SPEC-PX-03 AI Inference Proxy & extraction (FR-4.4-4.9; 2.20, 2.23-2.26; S3). SPEC-PX-04 Tenancy/roles/RLS (FR-1.1-1.3; 1.12-1.19; S2). SPEC-PX-05 Locations (FR-2; 2.1-2.9; S3). SPEC-PX-06 Equipment types & contracts (FR-3; 2.10-2.19; S3). SPEC-PX-07 Audit/outbox/notifications (FR-6.1-6.3; 3.19-3.22; S2 foundation, S4). SPEC-PX-08 Review/delegation/escalation (FR-5; 3.1-3.18; S4). SPEC-PX-09 Data security (NFR; S2-S5). SPEC-PX-10 DevSecOps & resilience (EP-10/11; 4.3-4.4; S2, S6). SPEC-PX-11 Exports/quota/retention (FR-6.4-6.6; 3.23-3.27, 4.1-4.2; S4-S5).
- scope: spec-to-requirement mapping, sprint placement

## ARCH-19: Sea Stock relationship
- source: ARCHITECTURE.md §13
- status: proposed
- decision: Sea Stock is a separate repo and constitution with the same stack and patterns. Shared Keycloak container with a separate realm; shared Vault with a separate path; separate PostgreSQL instance; separate MinIO buckets and credentials. Shared code patterns (outbox, offline queue, proxy framework) change only with review from both teams.
- scope: cross-project boundaries

## ARCH-20: Open items affecting architecture
- source: ARCHITECTURE.md §14
- status: proposed
- decision: OPEN items and when needed: P-1 tenant + first EA bootstrap (S2); O-12 who sends/checks activation and phone-change codes (S2); O-13 API view of Keycloak lock state (S2); O-11 active unit in user_session vs token (S2); O-23 primary unit and multi-invite activation (S2); P-10 bu_admin_user_id vs user_unit_role (S2); P-3 SMS provider and DLT registration (S2); email provider SES vs SendGrid/SMTP (S2, Mailpit locally); P-4 admin MFA (S2 decision, before release); O-17 photo upload route (S3); O-20 and P-12 proxy refusals / ambiguous timeouts vs attempt budget (S3); P-11 effective-decision rule (S4); P-13 WAL-based backup for 1-hour RPO (before procurement); P-14 OpenAI US endpoints + ZDR evidence (before release); environment procurement (S3-S4).
- scope: open decisions register

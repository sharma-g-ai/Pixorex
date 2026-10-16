# ARCHITECTURE.md — Pixorex V1

> Agents load only the section relevant to the task. Binding rules live in `CONSTITUTION.md`. Column-level detail lives in the V3 Data Models document; endpoint detail lives in `contracts/`. This file explains how the pieces fit.

| Field | Value |
|---|---|
| Version | v1.2 — aligned to PRD V3 and API Contracts (Oct 14, 2026) |
| Owners | Geetashish Sharma, Suchith Veeramalla |
| Status | Items marked **OPEN** reference PRD open items (P-n) or contract decisions (O-n) |

---

## 1. What V1 is

A field technician photographs an equipment nameplate (1–4 photos), the AI Inference Proxy extracts the fields, the technician verifies each field and submits a revision, and a **different** person approves or rejects that exact revision. All of this happens inside a tenant → business unit → location structure that admins configure and publish first. The approved scan, its exact revision and its effective decision are the reviewed record. There is no Client Portal in V1.

---

## 2. Components

| Component | Technology | Notes |
|---|---|---|
| Mobile app | Flutter (iOS 16+, Android 10+), `mobile/` | Technician only: sign-in, unit switch, capture, offline queue (AES-256, hardware-backed key), My Scans, delegated review. Root/jailbreak detection, certificate pinning |
| Web dashboard | React + TypeScript (Vite), `web/` | Enterprise Admin and BU Admin surfaces (EA-01–04, BU-01–05). No portal route |
| Backend API | Python 3.12 + FastAPI, `api/` | `/api/v1`, 76 endpoints in 4 slices. No sign-in endpoints |
| Workers | Same codebase, separate process | Outbox worker, extraction runner, scheduled jobs (escalation, batch alerts, retention, export builds) |
| Identity | Keycloak 24.x, `keycloak/` | One-time-code sign-in, lockout, sessions; realm config as code |
| Database | PostgreSQL 18 | 31 tables in 6 domains (frozen V3 model); RLS on every tenant-owned table |
| Object storage | MinIO (private) | Photos at `/{tenant}/{bu}/{scan}/{photo_no}`, export files; versioning on |
| Secrets | HashiCorp Vault | Loaded at container start; AppRole in deployed environments, dev mode locally |
| AI | AI Inference Proxy → OpenAI (US endpoints, Zero Data Retention: **OPEN P-14**) | Internal only; apps never call it |
| Email | **OPEN**: SES (earlier plan) vs SendGrid/SMTP (BRD v2.1). Local: Mailpit | Sent only via the outbox worker |
| SMS | Amzur's existing SMS account (**OPEN P-3**: name, DLT registration) | Called by the Keycloak OTP authenticator; credentials in Vault |
| CI/CD | GitHub Actions | See SPEC-PX-10 |

---

## 3. Environments and topology

```
docker-compose (local + CI)
├── api          FastAPI
├── worker       outbox / jobs
├── keycloak     + pixorex realm import, OTP authenticator jar, theme
├── postgres     16
├── minio
├── vault        dev mode
└── mailpit      local email inbox
```

| Stage | Environment | Data | Status |
|---|---|---|---|
| 0 | Local Compose + CI | Synthetic only | **Active** |
| 1 | India E2E | Synthetic only (export control) | Procurement deferred |
| 2 | US VPS | Real client data | Procurement deferred |
| 3 | AWS us-east-1 | Real client data | Procurement deferred |

**Dependency:** offline sync testing on real devices (S4), DAST on the US VPS, TLS 1.3/HSTS evidence, WAL-based RPO and the S6 release tests need a deployed environment. Procurement decision needed by Sprint 3–4.

Delivery model (unchanged): SaaS-first, customer-hosted as a paid option. V1 builds the dedicated-deployment tier; the model must not preclude shared deployments later (tenant context is set in one place).

---

## 4. Identity, tenancy and access

### 4.1 Roles (PRD, 3 roles + 1 capability)

| Role (`user_unit_role.role`) | Scope | Surface |
|---|---|---|
| `enterprise_admin` | Whole tenant (`bu_id` null) | Web |
| `bu_admin` | One unit; one active BU Admin per unit | Web |
| `field_technician` | One or more units | Mobile |
| Delegated reviewer | Technician with `is_trusted_reviewer` and an open `review_assignment` | Mobile (MOB-07) |

One person = one `app_user`; each unit they work in = one `user_unit_role` row. Removing someone from a unit sets `removed_at` and keeps their account and other units.

### 4.2 Sign-in (apps → Keycloak directly)

- **Technicians:** system browser, Authorization Code + PKCE, code by **SMS or email** (their choice).
- **Admins (EA, BU Admin):** same flow from the web app, code by **email only**. No passwords, no SAML in V1. Whether this meets the MFA expectation for privileged roles is **OPEN P-4**.
- **Lockout:** wrong codes are counted per account across both channels; the 5th locks sign-in for 30 minutes and unlocks automatically (Keycloak brute-force detection; the custom authenticator must report failures to it).
- **Code-request throttling:** per user and per destination.
- **Audit:** a Keycloak event listener posts sign-in, failure and lockout events to an internal API endpoint, which writes `audit_log` (category `sign_in`).
- **Lock state shown to admins (BU-01, contract 1.18):** read from Keycloak's attack-detection admin API (**OPEN O-13**, proposed).

### 4.3 Linking Keycloak users to `app_user`

The frozen model has no Keycloak-ID column, so the link lives in Keycloak: each Keycloak user carries attributes `app_user_id` and `tenant_id`, emitted as token claims by protocol mappers. Keycloak users are created by the API (invite acceptance, tenant bootstrap) through the Keycloak admin API.

### 4.4 Request pipeline (every authenticated call)

1. Validate the JWT (signature via Keycloak JWKS, expiry, audience). Missing/invalid → 401.
2. Read `tenant_id` and `app_user_id` claims; load `app_user` (must be `active`).
3. Load `user_session` for (user, `X-Device-Id`); create on first call. `revoked_at` set → 401. Revocation must bite within **60 seconds** (cache ≤ 60 s).
4. Resolve the active unit (`user_session.active_bu_id`; **O-11** proposed: keep V3 model, not a token claim) and the caller's active roles.
5. Open the transaction and `SET LOCAL app.tenant_id`, `app.user_id`, `app.bu_ids` (units the caller may read), `app.is_ea`.
6. Endpoint authorization: role in the target unit (`{buId}` in path) → 403 if not held; EA passes for every unit in the tenant. Rows of another tenant → 404.

The API connects as a non-owner role that cannot bypass RLS. Migrations run as a separate owner role.

### 4.5 RLS model

- Every tenant-owned table: policy `tenant_id = current_setting('app.tenant_id')::uuid`.
- Unit-owned tables additionally: `bu_id = ANY(app.bu_ids)` unless `app.is_ea`.
- `audit_log`: INSERT and SELECT only; no UPDATE/DELETE grant to any role.
- Exceptions per the model: `tenant` and the global `prompt_version`.
- Required test per table: rows created in tenant A / unit X are invisible to tenant B / unit Y, and writes across the boundary fail.

### 4.6 Tenant bootstrap (**OPEN P-1**, proposed)

No endpoint or invite covers the first tenant and EA. Proposal: an operator-only CLI (`api/scripts/bootstrap_tenant.py`), run by Amzur, creating the `tenant`, the first `app_user` + `enterprise_admin` role, the Keycloak user with claims, and the default `retention_config` rows, with an audit row (actor `system`).

---

## 5. Data model (frozen V3, 31 tables)

| Domain | Tables | Sprint |
|---|---|---|
| 1 Tenancy, users, sign-in (7) | tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session | S2 |
| 2 Locations (3) | location_hierarchy_version, location_level_rule, location_node | S2 (version row, created with each unit) · S3 |
| 3 Equipment types & contracts (5) | equipment_type, equipment_type_version, field_definition, prompt_version, extraction_contract | S3 |
| 4 Scans, photos, extraction (4) | scan, scan_photo, extraction_attempt, ai_field_value | S3 |
| 5 Review, delegation, escalation (6) | revision, revision_field, review_decision, review_batch, review_assignment, escalation | S4 |
| 6 Audit, notifications, exports, quota, retention (6) | audit_log, notification, export_job, quota_usage, retention_config, outbox_event | S2 (audit_log, outbox_event) · S4–S5 |

Invariants (from the PRD): `tenant_id`, `created_at`, `updated_at` on every tenant-owned table; composite tenant FKs; insert-only `ai_field_value`, `revision`, `audit_log`; `audit_log` partitioned by month; triggers freeze published locations and fields and block self-decision; the uniqueness rules listed in the PRD. Version tables hold version 1 only in V1.

**OPEN P-10:** `business_unit.bu_admin_user_id` vs the `bu_admin` row in `user_unit_role`. Proposed: `user_unit_role` is authoritative; the column is written in the same transaction and a deferred constraint trigger checks they agree.

---

## 6. Scan lifecycle (two independent statuses)

| Column | Values |
|---|---|
| `processing_status` | queued_on_phone (phone only) → uploading → extracting → ready_to_review / failed → retake_required |
| `review_status` | draft → waiting_for_approval → approved / rejected; closed (replaced by retake); discarded |

The contracts' *Status moves the API allows* table is the transition matrix (resolves P-7). Any other move → 409 invalid-state. My Scans tabs: Needs action (ready_to_review, rejected, failed, retake_required), In progress (queued_on_phone, uploading, extracting, waiting_for_approval), Approved.

Key rules: `client_capture_id` makes uploads idempotent; at most **3 extraction attempts** per scan across retries and re-extracts, then retake only; Submit Anyway lists empty required fields and can never be approved; first valid decision wins (409 for the loser); overrides append linked decision rows; 24-hour escalation to the EA. Effective-decision rule across revisions and overrides: **OPEN P-11** (needed before S4).

---

## 7. AI Inference Proxy

Internal service (module + worker). Runs the scan's pinned `extraction_contract` (type version + platform-owned prompt version). Builds the request, strips PII and operational metadata, applies injection defences and per-tenant rate limits, reads provider secrets from Vault, records every call as an `extraction_attempt` (tokens, cost), writes one insert-only `ai_field_value` per field (confidence NULL when unscored). Background target < 15 s p95; upload acknowledgement < 500 ms. Whether proxy refusals consume an attempt: **OPEN O-20**. Ambiguous provider timeouts: **OPEN P-12**.

---

## 8. Outbox and jobs

`outbox_event` rows are written in the business transaction; the worker claims them (`FOR UPDATE SKIP LOCKED`), executes with retry and exponential backoff, and records the outcome with the event's correlation id (at-least-once, consumers idempotent — AT-15). Scheduled jobs: 24-hour escalation, batch no-progress alerts (1 day / 1 week), daily retention enforcement, async export builds.

---

## 9. Security

| Control | Design |
|---|---|
| Transport | TLS 1.3 only, HSTS ≥ 1 year (evidence needs a deployed environment) |
| At rest | AES-256 in PostgreSQL and MinIO; Vault-managed MinIO keys |
| Secrets | Vault at container start; secret scan blocks commits |
| Images | Private MinIO; 15-minute object-specific signed URLs after a fresh auth check; none after revocation |
| Access changes | Role/scope change or removal effective within 60 s |
| Mobile | Root/jailbreak detection, certificate pinning, hardware-backed AES-256 local store |
| Exports | Scope recheck + DLP scan before delivery (DLP result storage: **OPEN O-14**) |
| Residency | Real data on US infrastructure only; India E2E synthetic only |
| Backup / DR | Daily encrypted snapshots (7 days), MinIO versioning, monthly restore test; **1-hour RPO needs WAL archiving or equivalent (OPEN P-13)**; RTO ≤ 4 h |

---

## 10. API conventions (from the contracts)

REST + JSON under `/api/v1`; Bearer token on every call except invite preview/accept, `/health`, `/ready`; tenant from the token, never the URL; unit in the path as `{buId}`; `X-Device-Id` header on every app call; UUID ids with display numbers (`record_no`, `batch_no`); cursor pagination; RFC 9457 errors; `Idempotency-Key` on creates; no ETags (state checks give 409); status changes are POST actions; signed URLs 15 min, export links 1 hour.

---

## 11. Repository layout

```
pixorex/
├── CONSTITUTION.md  ARCHITECTURE.md  STATE.md  TASK_TEMPLATE.md  BRD-INDEX.md
├── start-session.sh
├── docker-compose.yml
├── contracts/            # common.yaml, slice-*.yaml, .spectral.yaml, README.md
├── docs/                 # PRD.md, data-model.md, api-contracts.md, design/README.md
├── specs/                # SPEC-PX-01 … SPEC-PX-11
├── tasks/                # PX-XX-TNN.md
├── api/
│   ├── app/{routers,services,repositories,auth,core,proxy,workers}
│   ├── migrations/       # DDL, RLS policies, grants, triggers
│   ├── scripts/          # bootstrap_tenant.py, seed_synthetic.py
│   └── tests/{unit,integration,isolation,contract}
├── keycloak/             # realm export, OTP authenticator (Java SPI), event listener, theme
├── web/                  # React + TS (Vite)
├── mobile/               # Flutter
├── .github/{CODEOWNERS,workflows/,PULL_REQUEST_TEMPLATE.md}
└── .claude/ai-review-prompt.md
```

CODEOWNERS: `api/app/auth/`, `api/migrations/`, `keycloak/`, `.github/workflows/` → architects (+ DevOps for workflows).

---

## 12. Spec map

| Spec | Context | PRD | Contracts | Sprint |
|---|---|---|---|---|
| SPEC-PX-01 | Identity, sessions & invites | FR-1.4–1.8 | 1.1–1.11 | S2 |
| SPEC-PX-02 | Mobile capture & offline queue | FR-4.1–4.3 | 2.21–2.23, 2.27 | S3–S4 |
| SPEC-PX-03 | AI Inference Proxy & extraction | FR-4.4–4.9 | 2.20, 2.23–2.26 | S3 |
| SPEC-PX-04 | Tenancy, roles & RLS | FR-1.1–1.3 | 1.12–1.19 | S2 |
| SPEC-PX-05 | Locations | FR-2 | 2.1–2.9 | S3 |
| SPEC-PX-06 | Equipment types & contracts | FR-3 | 2.10–2.19 | S3 |
| SPEC-PX-07 | Audit, outbox & notifications | FR-6.1–6.3 | 3.19–3.22 | S2 (foundation) · S4 |
| SPEC-PX-08 | Review, delegation & escalation | FR-5 | 3.1–3.18 | S4 |
| SPEC-PX-09 | Data security | NFR | — | S2–S5 |
| SPEC-PX-10 | DevSecOps & resilience | EP-10/11 | 4.3–4.4 | S2 · S6 |
| SPEC-PX-11 | Exports, quota & retention | FR-6.4–6.6 | 3.23–3.27, 4.1–4.2 | S4–S5 |

---

## 13. Sea Stock relationship

Separate repo and constitution, same stack and patterns. Shared Keycloak container with a separate realm; shared Vault with a separate path; **separate PostgreSQL instance**; separate MinIO buckets and credentials. Shared code patterns (outbox, offline queue, proxy framework) change only with review from both teams.

---

## 14. Open items affecting architecture

| Ref | Item | Needed by |
|---|---|---|
| P-1 | Tenant + first EA bootstrap (proposed CLI, §4.6) | **S2** |
| O-12 | Who sends/checks activation and phone-change codes | **S2** |
| O-13 | API view of Keycloak lock state (proposed admin API read) | **S2** |
| O-11 | Active unit in `user_session` vs token (proposed: V3 model) | **S2** |
| O-23 | Primary unit and multi-invite activation | **S2** |
| P-10 | `bu_admin_user_id` vs `user_unit_role` (proposed §5) | **S2** |
| P-3 | SMS provider and DLT registration | **S2** |
| — | Email provider (SES vs SendGrid/SMTP) | S2 (Mailpit locally) |
| P-4 | Admin MFA | S2 decision, before release |
| O-17 | Photo upload route (API vs signed MinIO URL) | S3 |
| O-20, P-12 | Proxy refusals and ambiguous timeouts vs attempt budget | S3 |
| P-11 | Effective-decision rule | S4 |
| P-13 | WAL-based backup for 1-hour RPO | Before procurement |
| P-14 | OpenAI US endpoints + ZDR evidence | Before release |
| — | Environment procurement | S3–S4 |

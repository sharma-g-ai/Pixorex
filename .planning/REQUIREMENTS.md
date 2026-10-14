# Requirements: Pixorex V1

**Defined:** 2026-10-14
**Core Value:** Every nameplate becomes a trustworthy reviewed record, approved by a second person and never visible outside its tenant and unit.

**Sources:** docs/PRD.md (functional requirements, permissions matrix, NFRs, release tests, screens), specs/SPEC-PX-01, 04, 07, 10 (Sprint 2 spec-level requirements), docs/api-contracts.md and CONSTITUTION.md (gates). Synthesized in `.planning/intel/`. Per-FR acceptance is absent in the PRD; acceptance lives in the release tests (AT-01 to AT-18) and in the SPEC GIVEN/WHEN/THEN criteria.

**ID conventions:** source IDs are reused. `FR-n.n` and screen IDs come from the PRD; `AT-nn` are PRD release tests; `REQ-01.nn`, `REQ-04.nn`, `REQ-07.nn`, `REQ-10.nn` are SPEC-level requirements that refine PRD FRs and are mapped to the same phase as their parent FR unless noted. Suffixes `a/b/c` (REQ-01.02a/b, REQ-01.11a/b/c) split a SPEC requirement so the part gated by an open decision is separate from the buildable part. `NFR-*` and `PERM-matrix` name PRD rows that carry no ID. `GATE-G5` (CONSTITUTION §6) and `REQ-10.S6` (SPEC-PX-10 S6 slice) are derived; their detail is specified at the Sprint 6 G1.

**Status legend:**
- `Pending` - ready to plan and build.
- `Pending (partial: X)` - buildable apart from a named sub-behaviour gated by open decision X; confirm X before that sub-behaviour is planned.
- `BLOCKED (X)` - gated by open decision X. Per CONSTITUTION §0 nothing OPEN is built until the decision is recorded in the root STATE.md -> Decisions. Mapped to its phase so the dependency is visible.

**Decision IDs:** `P-n` = PRD open item n (ARCHITECTURE label); `O-n` = API-contract open decision n. Defined in the Open Decisions Register below.

## v1 Requirements

### Tenancy, users and sign-in (PRD functional requirements 1)

- [ ] **FR-1.1**: A tenant owns business units; creating a unit seeds exactly one default business process (is_default = true); the UI has no process picker.
- [ ] **FR-1.2**: Every tenant-owned row carries tenant_id with composite tenant FKs; PostgreSQL RLS restricts rows to the tenant, then the user's authorised unit, alongside API authorization.
- [ ] **FR-1.3**: A user's role in a unit is one user_unit_role row (enterprise_admin with bu_id null, bu_admin, field_technician); one active BU Admin per unit; business_unit.bu_admin_user_id null means "No BU Admin". (partial: P-10)
- [ ] **FR-1.4**: Invitations are single-use magic links expiring 24 h after sending (token hash only; a multi-unit invite is one row per unit with the same hash); a technician confirms name and mobile and verifies the number by texted code; a BU Admin verifies email by code; an expired invite raises invite_expired. (partial: P-5, O-12, O-23, P-3; see REQ-01.10, REQ-01.11a/b/c)
- [ ] **FR-1.5**: Sign-in is by one-time code (technicians choose SMS or email; admins email); Keycloak counts wrong codes per account across both channels; the 5th locks sign-in for 30 minutes with automatic unlock and an audit_log row (sign_in). (partial: P-3 for SMS; P-4 admin MFA decision needed before release)
- [ ] **FR-1.6**: Each device session records the unit in use; switching units needs no new sign-in and updates app_user.last_bu_id, which opens at next sign-in. **BLOCKED (O-11)**
- [ ] **FR-1.7**: Removing a user revokes all their sessions; changing a phone revokes the other devices; the API denies a revoked session within 60 seconds.
- [ ] **FR-1.8**: A phone number changes only after the code sent to the new number is verified; five wrong codes lock changes for 30 minutes; the change signs out other devices, writes a users audit row and emails the user. **BLOCKED (O-12)**

### Locations (PRD functional requirements 2)

- [ ] **FR-2.1**: The EA defines a unit's levels (e.g. Facility, Building, Shop, Bin, Sub-bin) as location_level_rule rows: name, order (1 = top), required/optional/off; the top level is always required. (partial: O-5 depth limit)
- [ ] **FR-2.2**: The EA builds the node tree: each location_node has a parent, materialised path and level; names are unique among siblings; until publish the EA can add, rename, move or delete any node.
- [ ] **FR-2.3**: Publishing sets location_hierarchy_version to published (version_no 1) and freezes the full tree as tree_snapshot; afterwards levels and nodes are locked by trigger; the publish screen first shows a preview and an irreversible-change warning.
- [ ] **FR-2.4**: The mobile picker shows tenant.name as a read-only Customer header above the levels; Customer is not a level and not a selectable node.
- [ ] **FR-2.5**: The phone caches tree_snapshot, shows only levels that are not off, enforces required levels and offers the last-used location for one-tap confirm; an invalid or unauthorised location needs manual repair and is never silently replaced.
- [ ] **FR-2.6**: Each scan stores its location_node_id and a location_path_snapshot taken at capture time.

### Equipment types and extraction contracts (PRD functional requirements 3)

- [ ] **FR-3.1**: A BU Admin creates an equipment type for their unit from blank, as a copy, or as an AI-assisted draft (created_via); names are unique per unit; only a not_published type can be renamed, edited or deleted.
- [ ] **FR-3.2**: Until publish the BU Admin adds, edits, reorders and deletes fields (key, label, order, data type text/number/date/dropdown/boolean, required and critical flags, format rule, unique-in-unit flag, review threshold default 0.85); a dropdown needs 2 or more choices.
- [ ] **FR-3.3**: AI assistance proposes fields from reference images and marks them ai_suggested; a person reviews and edits them; AI never publishes a type. **BLOCKED (O-15)**
- [ ] **FR-3.4**: Publishing freezes the type's single version (version_no 1, publisher and time) and its fields, and creates an active extraction contract binding that version to one prompt version; a published type cannot be renamed, changed or deleted.
- [ ] **FR-3.5**: Prompt versions are platform-owned, global, managed by Amzur, never edited after use and never hold client data; a new prompt version adds a new contract; a blocked contract stops new attempts.
- [ ] **FR-3.6**: The mobile type picker lists only published types of the active unit's default process.
- [ ] **FR-3.7**: A dropdown extraction must match one of the choices or the field is flagged format_failed; a boolean is stored as true/false in values_json; unique-in-unit compares with the unit's other scans of that type.

### Scans, photos and extraction (PRD functional requirements 4)

- [ ] **FR-4.1**: The phone generates client_capture_id offline, unique per tenant; a repeated upload (including a retry after a lost response) returns the existing scan; scan.bu_id is the unit active at capture.
- [ ] **FR-4.2**: A scan has 1-4 photos, numbered and unique per scan; bytes live in private MinIO at /{tenant}/{bu}/{scan}/{photo_no}; the database stores only the key and a SHA-256; image-quality numbers stay on the phone. (partial: O-17 upload route)
- [ ] **FR-4.3**: An offline capture is held in the AES-256 encrypted local queue under its client_capture_id and syncs oldest-first when connectivity and the OS allow; foreground reconciliation on app resume is the mandatory fallback; failed or blocked items stay visible and are never silently deleted.
- [ ] **FR-4.4**: A scan pins one extraction contract at creation; the pin changes only on a re-extract; a newer publish never upgrades it silently.
- [ ] **FR-4.5**: Every AI call through the AI Inference Proxy is an extraction_attempt: attempt_no 1-3 per scan across all types, trigger first/retry/re-extract, status queued/running/succeeded/failed/timed out, with contract, tokens and cost; after 3 only a retake is possible. (partial: O-20 proxy refusals, P-12 ambiguous timeouts)
- [ ] **FR-4.6**: The mobile app holds no provider key; the Proxy builds the outbound request, strips PII and operational metadata, applies prompt-injection defenses and per-tenant rate limits, and reads secrets from Vault.
- [ ] **FR-4.7**: AI answers are stored insert-only, one ai_field_value per field; confidence is NULL when the model gives no score; flag reasons are low_confidence, format_failed, no_confidence, missing_required, critical_not_found.
- [ ] **FR-4.8**: An attempt records detected_label, suggested_type_id and suggestion_confidence; the app shows the Type mismatch screen and a re-extract with another type happens only after the technician approves it.
- [ ] **FR-4.9**: Extraction targets under 15 seconds at p95 in the background; the technician gets an immediate acknowledgement (< 500 ms) and is never blocked waiting for extraction.

### Review, delegation and escalation (PRD functional requirements 5)

- [ ] **FR-5.1**: Submit for Review creates an immutable revision holding the final values by field key; only the scan's own technician can create one; origin is technician_review or rejection_fix.
- [ ] **FR-5.2**: The technician's verdict per field is a revision_field: accepted, corrected, unreadable (with reason and note) or left empty; each verdict links to the untouched AI value.
- [ ] **FR-5.3**: Submit Anyway sends a revision with required fields still empty and lists them in empty_required_fields; in V1 such a revision cannot be approved and must be rejected for rework.
- [ ] **FR-5.4**: A decision approves or rejects one exact revision as bu_admin, enterprise_admin or delegated_technician; the decider can never be the scan's technician (trigger); the first valid decision is current; an override inserts a new linked row; a reject carries a category. (partial: P-11 effective-decision rule, P-6 override authority, O-21 reject note)
- [ ] **FR-5.5**: A rejected scan returns to its technician with the category shown; the fix is a new rejection_fix revision sent to the named reviewer; the rejected revision is preserved.
- [ ] **FR-5.6**: A BU Admin or EA creates a review batch of 1-50 scans for one trusted technician; scans that technician captured are left out; a batch is a set of review assignments, never bulk approval. (partial: O-18 trusted-reviewer eligibility)
- [ ] **FR-5.7**: Reassign changes the assignee, closes old assignment rows and writes an audit row; take back may carry a message; send reminder sets reminded_at; alert timestamps stop repeat alerts.
- [ ] **FR-5.8**: A scheduled job creates an escalation (not_approved_24h or no_bu_admin) once a scan has waited 24 hours; the EA can send a reminder; the first decision resolves it; the BU Admin still sees the scan.

### Audit, notifications, exports, quota and retention (PRD functional requirements 6)

- [ ] **FR-6.1**: The audit log is append-only and partitioned by month, actor type user/system, categories sign_in, users, locations, equipment_types, review, override, escalation, export, retention; kept 1 year online and 3 years archived (floor cannot be lowered). Read/export scope is governed by the audit-access pair below.
- [ ] **FR-6.2**: Work that must follow a commit (emails, texts, AI proxy calls, export builds) is written to outbox_event in the same transaction as the change and its audit row; a worker runs it with retry and backoff.
- [ ] **FR-6.3**: Notifications appear in the bell panel and by email, with no push; 17 kinds (Domain 6 of the Data Models document).
- [ ] **FR-6.4**: A CSV export is a job for scans or audit_log limited to the requester's authorised units; up to 1,000 rows return in the request; above that the job is queued, the file stored in MinIO, the link valid 1 hour and an export_ready alert sent; every job writes an audit row and passes a DLP scan before delivery. (partial: O-14 DLP result storage; audit_log export kind follows the audit-access pair)
- [ ] **FR-6.5**: Quota usage is one row per unit per month counting unique scans, counted when the server accepts the scan (a retry never counts twice); at the limit the server refuses with HTTP 402 and an actionable message; the 80/95/100 percent alert levels are tracked but the alert experience is post-V1. **BLOCKED (P-9 / O-7: where the ceiling is stored)**
- [ ] **FR-6.6**: Retention is set per data class with a tenant default (bu_id null) and a hard floor; the API rejects a value below the floor with HTTP 400; a daily enforcement job applies defaults (source images 30 days, AI attempts 90 days, approved records 7 years, revision history 7 years, user accounts 90 days after deactivation), skips legally held records and audits every purge. (partial: O-8 config endpoints, P-2 image-clock start, P-8 audit-log retention holding)

### Permissions (PRD permissions matrix)

- [ ] **PERM-matrix**: The server decides every operation from the user's role in the active unit (rows a-j: create unit/assign BU Admin, build/publish locations, create/publish equipment type, invite/disable technician, capture own scan, decide own scan [never], decide another's exact revision, delegate batch, override a decision, read/export scans and audit). Role-boundary tests extend with every endpoint added in later phases. (partial: P-5 invite row, P-6 override row)

### Sprint 2 specification requirements (SPEC-PX-01, SPEC-PX-04, SPEC-PX-07, SPEC-PX-10; all Draft, awaiting G1)

Identity, sessions and invites (SPEC-PX-01, BC-01):

- [ ] **REQ-01.01**: Keycloak realm `pixorex` as code, imported on start; public clients pixorex-web and pixorex-mobile with Authorization Code + PKCE; no password grant; protocol mappers emit tenant_id and app_user_id claims. (A0)
- [ ] **REQ-01.02a**: Sign-in by emailed one-time code for technicians and admins; single-use, short-lived codes; non-active users receive no code; expired/used/invalid codes fail with an explicit message and count as wrong codes. (A0; FR-1.5)
- [ ] **REQ-01.02b**: Sign-in by SMS one-time code for technicians with a verified phone, using Amzur's SMS account (Vault credentials). (A0; FR-1.5) **BLOCKED (P-3)**
- [ ] **REQ-01.03**: Lockout: 5th wrong code (both channels) locks sign-in 30 minutes with time remaining shown, auto-unlock, one audit_log row (sign_in, actor system) via the event listener; a correct code after 4 wrong ones resets the counter. (A0; AT-03)
- [ ] **REQ-01.04**: Code-request throttling per user and per destination (thresholds [TBD] in the spec). (A0)
- [ ] **REQ-01.05**: Keycloak event listener posts LOGIN, LOGIN_ERROR and lockout events to an internal, network-restricted, non-public API endpoint authenticated by a Vault-held secret; writes audit_log (sign_in) with no code value; retries without blocking sign-in. (A0; G2 must confirm this internal endpoint is consistent with CON-NN-07)
- [ ] **REQ-01.06**: Request-context middleware per ARCHITECTURE §4.4: 401 for missing/expired/foreign tokens, removed users and revoked sessions (within 60 s); SET LOCAL app.tenant_id, app.user_id, app.bu_ids, app.is_ea, absent on the next pooled connection; public paths only /health, /ready, /invites/preview, /invites/accept; last_active_at updated at most once per [TBD] interval. (A0; partial: O-11 active-unit resolution step)
- [ ] **REQ-01.07**: GET /me (contract 1.1): units with role, is_primary, assigned_by_name, active_bu_id, last_bu_id and tenant.name; EA lists all tenant units; removed units not listed.
- [ ] **REQ-01.08**: PUT /me/active-unit (contract 1.2): sets user_session.active_bu_id for the device and app_user.last_bu_id with no new sign-in; 403 for a unit without an active role; other devices unchanged. **BLOCKED (O-11)**
- [ ] **REQ-01.09**: POST /me/sign-out (contract 1.3): sets this device's user_session.revoked_at, writes audit_log (sign_in), returns 204; other devices stay signed in.
- [ ] **REQ-01.10**: Create and manage invites (contracts 1.8-1.11): one invite row per unit with the same token_hash and 24 h expiry, outbox email and audit row in one transaction; GET list scoped by role; resend issues a new token and window; cancel; token hash only; invite_expired intent recorded via outbox until notifications land in S4. **BLOCKED (P-5 who may invite whom; see invite-authority pair)**
- [ ] **REQ-01.11a**: Invite preview and accept core (contracts 1.6-1.7): preview returns role, email, units, inviter, expiry (token only in body); 409 invite-expired/used/cancelled; accept creates app_user (status invited), one user_unit_role per invite row, the Keycloak user with attributes, marks the invite used, audit row, all in one transaction; technicians never gain web dashboard access.
- [ ] **REQ-01.11b**: Activation verification: after accept, the user verifies phone (technician) or email (admin) and app_user.status becomes active. **BLOCKED (O-12)**
- [ ] **REQ-01.11c**: Multi-unit activation and is_primary choice when invites from several units exist. **BLOCKED (O-23)**
- [ ] **REQ-01.12**: Phone change (contracts 1.4-1.5): saved only after the code sent to the new number is verified; 5 wrong codes lock changes 30 minutes; success revokes other sessions, emails the user, audit (users); number in use -> 409 phone-in-use. **BLOCKED (O-12; see phone-change-codes pair)**
- [ ] **REQ-01.13**: Client sign-in: web OIDC Authorization Code + PKCE with tokens in memory and silent refresh; mobile system-browser (AppAuth) + PKCE with tokens in Keychain/Keystore; X-Device-Id generated once per install; locked state shown on return. (A0 token handling, A2 screens)

Tenancy, roles and RLS (SPEC-PX-04, BC-04):

- [ ] **REQ-04.01**: Migrations create Domain 1 (tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session) plus location_hierarchy_version exactly as in the V3 Data Models; tenant_id/created_at/updated_at and composite tenant FKs; DB-enforced uniqueness (email per tenant, E.164 phone, one active BU Admin per unit, one default process per unit). (A1)
- [ ] **REQ-04.02**: API connects as a non-owner role without BYPASSRLS; migrations run under a separate owner role used only by the migration job. (A0)
- [ ] **REQ-04.03**: RLS policies on every Domain 1 table and location_hierarchy_version per ARCHITECTURE §4.5; no RLS context returns zero rows; isolation test harness tests/isolation/ (2 tenants x 2 units) reused by every later table. (A0; FR-1.2)
- [ ] **REQ-04.04**: Single authorization module `require_role(roles, bu_id)` used by every router; EA passes for any unit in the tenant; delegated_technician helper for open review_assignment; role-boundary test generated from each endpoint's x-roles. (A0)
- [ ] **REQ-04.05**: Tenant bootstrap CLI `bootstrap_tenant.py` (operator-only, not reachable over HTTP): creates tenant, first app_user + enterprise_admin role, Keycloak user with claims, default retention_config rows and an audit row (actor system); idempotent. (A1) **BLOCKED (P-1)**
- [ ] **REQ-04.06**: Synthetic seed `seed_synthetic.py`: 2 tenants, 3 units, EA, BU Admins, technicians (fake data, test SMS destinations), one unit with no BU Admin; no real PPG data. (A2)
- [ ] **REQ-04.07**: List and read units (contracts 1.12, 1.14): EA sees every tenant unit with BU Admin or null, counts, locations_status and `?no_bu_admin=true`; BU Admin sees only units they run.
- [ ] **REQ-04.08**: Create unit (contract 1.13): business_unit + exactly one default business_process + location_hierarchy_version (not_published) + audit row in one transaction; optional BU Admin by invite_email or existing user_id; 409 duplicate-name; 403 for non-EA. **BLOCKED (P-10)**
- [ ] **REQ-04.09**: BU Admin management (contracts 1.15-1.17): list; assign (409 unit-has-bu-admin; cancels a pending BU Admin invite); remove (removed_at, bu_admin_user_id null, account kept, all-units removal revokes every session, replacement invite); removed unit returns 403 within 60 s while other units still work (AT-12). **BLOCKED (P-10)**
- [ ] **REQ-04.10**: Technician management (contracts 1.18-1.19): list with name, email, status, units, last_active_at and sign_in_locked_until; remove from a unit (access ends within 60 s, audit row, 403 for another unit's technician). **BLOCKED (O-13)**

Audit, outbox and notifications foundation (SPEC-PX-07, BC-07):

- [ ] **REQ-07.01**: audit_log table per the Data Models document, partitioned by month, categories and actor types; no UPDATE/DELETE grant to any role; writes succeed in months without a pre-created partition; tenant-scoped RLS. The "readable by EA only" clause is governed by the audit-access pair and is not built until decided. (A1; FR-6.1)
- [ ] **REQ-07.02**: Audit writer `audit.record(category, action, object_type, object_id, details)` using the current transaction and request context; exactly one row per audited write; none on rollback; details never contain tokens, codes, secrets or invite tokens. (A1)
- [ ] **REQ-07.03**: `outbox.enqueue(kind, payload, correlation_id)` writes outbox_event in the same transaction as the change and its audit row; no row on rollback. (A1; FR-6.2)
- [ ] **REQ-07.04**: Outbox worker + email adapter: claims with FOR UPDATE SKIP LOCKED, exponential-backoff retry up to [TBD] attempts, then failed and logged; idempotent handlers; invite_email arrives in Mailpit with the magic link. (A2; FR-6.2, AT-15)

DevSecOps and resilience, Sprint 2 slice (SPEC-PX-10, BC-10/BC-09):

- [ ] **REQ-10.01**: `docker compose up` from a clean checkout starts api, worker, keycloak (realm imported), postgres 16, minio, vault (dev) and mailpit healthy, migrations apply and /ready is ready; `make seed` loads the synthetic dataset; clone-to-signed-in-demo-user in under 30 minutes from the README.
- [ ] **REQ-10.02**: FastAPI skeleton with the layering, problem+json error handler, JSON logging with correlation_id and startup config validation; /health (public) and /ready (503 with per-dependency ok/fail, no versions or secrets). G2 baseline PR for the API. (Contracts 4.3, 4.4)
- [ ] **REQ-10.03**: api, worker and keycloak read DB, Keycloak admin, SMS, SMTP and listener secrets from Vault at start, not env vars or files; fail fast if Vault is unreachable. (A0)
- [ ] **REQ-10.04**: CI: path-filtered workflows (api ruff/mypy/pytest + isolation suite; web lint/typecheck/tests/build; mobile analyze/tests; keycloak SPI build + realm import smoke test); contracts/ change triggers all; changed-line coverage below 80% fails.
- [ ] **REQ-10.05**: CI security gates: secret scan on every push/PR, SAST, dependency scan (blocking on high/critical), container image scan (blocking on critical); any skipped or errored gate blocks merge.
- [ ] **REQ-10.06**: CI contract and PR rules: Spectral lint of contracts/ with .spectral.yaml; PR diff > 300 lines fails (generated files and lockfiles excluded); PR title starts with a task ID `PX-\d{2}-T\d{2}`.
- [ ] **REQ-10.07**: Branch protection and ownership: main has no direct pushes, 2 approvals, CODEOWNERS review, all checks required, linear history.
- [ ] **REQ-10.08**: AI review job runs .claude/ai-review-prompt.md with the pinned review model against the diff, linked spec and constitution and posts PASS/WARN/FAIL; FAIL blocks merge. (May slip to S3.)

Sprint 4 specification stubs (SPEC-PX-07; detail specified at Sprint 4 G1):

- [ ] **REQ-07.05**: Notifications: 17 kinds, bell panel + email, no push (contracts 3.19-3.21). (FR-6.3)
- [ ] **REQ-07.06**: Audit log read (contract 3.22). **BLOCKED (audit-access pair: unregistered decision)**

### Non-functional requirements (PRD NFRs; all need implementation evidence before they count as met)

- [ ] **NFR-performance**: API responses within 20 s at p95 excluding AI extraction; submitted-scan acknowledgement under 500 ms; background extraction under 15 s at p95; mobile launch under 3 s on a mid-range Android.
- [ ] **NFR-availability**: 99.9% uptime with planned maintenance off-peak only; RTO 4 hours or less, RPO 1 hour or less. **BLOCKED (P-13)**
- [ ] **NFR-scale**: 10 units per client, 10-20 users per unit, 1,000 scans per day per unit.
- [ ] **NFR-encryption**: AES-256 at rest in PostgreSQL and MinIO with Vault-managed MinIO keys; TLS 1.3 only in transit with HSTS of at least 1 year. (partial: environment procurement for TLS/HSTS evidence)
- [ ] **NFR-secrets**: All secrets loaded from HashiCorp Vault at container start, never from env vars or config files; secret-scan gates block any commit with credentials.
- [ ] **NFR-image-storage**: MinIO is private; images are served only by object-specific presigned URLs valid 15 minutes, issued after a current authorization check; none after revocation.
- [ ] **NFR-access-control**: Every API call validates the Keycloak token, session freshness, action permission, tenant and unit scope; a role/scope change or removal takes effect within 60 seconds. (partial: O-11)
- [ ] **NFR-mobile-security**: Root/jailbreak detection blocks the scan workflow; TLS certificate pinning; all local data AES-256 encrypted with a hardware-backed key.
- [ ] **NFR-mobile-platform**: iOS 16+ and Android 10+ (API 29+); offline-first capture; background sync where the OS permits with foreground reconciliation as the mandatory fallback; human verification and submission never automated; no tablet-native layout.
- [ ] **NFR-data-residency**: All real client data stays on US infrastructure; the India E2E environment holds synthetic data only; OpenAI calls use US endpoints with Zero Data Retention (needs deployment evidence). **BLOCKED (P-14)**
- [ ] **NFR-ai-privacy**: PII and operational metadata are stripped before any image is sent to the provider; logs record only which categories were stripped.
- [ ] **NFR-compliance**: Audit log kept 1 year online and 3 years archived; breach notification to designated PPG contacts within 24 hours; SOC 2 readiness documents available for review. (partial: P-8)
- [ ] **NFR-export**: CSV only; exports up to 1,000 records immediate, larger exports background jobs with a 1-hour download link; all exports pass a DLP scan. (partial: O-14)
- [ ] **NFR-backup**: Daily encrypted PostgreSQL snapshots retained 7 days; MinIO object versioning on all buckets; monthly restore test against the 4-hour RTO; daily snapshots alone cannot meet the 1-hour RPO so a WAL-based or equivalent design is needed. **BLOCKED (P-13)**
- [ ] **NFR-delivery-pipeline**: Two reviewer approvals per PR, SAST and dependency scanning, container scanning, DAST on the US VPS, and a deployment gate that blocks on any failed or skipped check. Sprint 2 delivers the PR/CI gates (REQ-10.04 to REQ-10.07); DAST and the deployment gate are carried by REQ-10.S6.

### Screens (PRD: 16 screens, no portal route, no process selector)

- [ ] **EA-01**: Units overview, create, edit: unit name/status, BU Admin or vacant, user and scan counts, recent escalation; create unit, assign or revoke admin. No cross-tenant assignment; warn on vacancy. (partial: P-5, P-10)
- [ ] **EA-02**: Locations setup: Customer read-only header, level rules, nodes, hierarchy preview, publish confirmation; no reopening after publish; block invalid parent, cycle and duplicate sibling.
- [ ] **EA-03**: Scans and escalations: authorised units only, 24-hour and no-admin escalations, scan detail, remind, decide; decided or expired escalation not actionable; first-decision race returns a conflict. **BLOCKED (P-11)**
- [ ] **EA-04**: Audit, export, alerts: category/time/unit filters, append-only event view, CSV export, notification bell; exports recheck scope and DLP; no portal access. (partial: audit-access pair; CSV export completes with FR-6.4 in Phase 4)
- [ ] **BU-01**: Staff and invites: users, unit role, verified phone, status, pending and expired invites, primary and trusted flags; one active BU Admin; expired invite must be recreated. (partial: P-5, O-13)
- [ ] **BU-02**: Equipment type builder: type list, create blank/copy/AI assist, fields, required and critical flags, dropdown options, preview, publish; AI draft needs human validation; no edit of a published type. (partial: O-15)
- [ ] **BU-03**: Review queue and decision: submitted revision, photos, raw AI value, technician verdict, flags, missing fields, approve or reject; own scan cannot be approved; missing mandatory field blocks approval; race shows 409. **BLOCKED (P-11)**
- [ ] **BU-04**: Delegation console: trusted reviewer, eligible scans, batch of 1-50, progress, remind, reassign, take back; excludes the reviewer's own captures; stale assignments cannot decide. (partial: O-18)
- [ ] **BU-05**: Usage and CSV: monthly BU scan usage, scans and audit filters, exports; no process selector; no quota push notifications. (partial: P-9 / O-7 ceiling display)
- [ ] **MOB-01**: Activate and sign in: SMS or email choice for technicians, code challenge, phone verification, retry timer; expired, invalid and locked states explicit; no unlock approval. (partial: O-12, P-3)
- [ ] **MOB-02**: Home and context: unit switch, type list, last location, offline queue count, My Scans; no unassigned unit; no process picker. Sprint 2 delivers Home and unit switch; later panels light up as their data lands. (partial: O-11)
- [ ] **MOB-03**: Capture and preview: camera with 1-4 photo count, quality retake or confirm, location breadcrumb; never transmit before confirmation; a retry creates no duplicate capture.
- [ ] **MOB-04**: Offline queue: queued count, upload and extraction status, retry, repair or discard where permitted; no silent deletion on retry exhaustion or age.
- [ ] **MOB-05**: My Scans and fields: Needs action / In progress / Approved tabs; photos with flagged fields; accepted, corrected, unreadable, left empty; unknown confidence never scored as high; submit needs an explicit action.
- [ ] **MOB-06**: Type mismatch and retake: detected label, suggested permitted type, remaining attempt budget, explicit re-extract or new retake; fourth attempt blocked; physical retake creates a new linked scan.
- [ ] **MOB-07**: Delegated review: only the trusted reviewer's currently assigned reviews; raw value, result and revision; approve or reject; no own scan; stale assignment returns 409. **BLOCKED (P-11)**

### Release tests (PRD: V1 is accepted when all 18 pass in representative environments)

Mapped to the first phase whose Draft SPEC cites the test, otherwise the phase in which every prerequisite for a full pass lands. GATE-G5 re-runs all 18 at Sprint 6.

- [ ] **AT-01**: Duplicate uploads, including a timeout after a successful commit: one scan per tenant and client_capture_id, one counted scan, same ACK on retry. (Idempotency is observable in Phase 2 via FR-4.1; the counted-scan half needs FR-6.5.)
- [ ] **AT-02**: Capture offline, then switch user or unit before sync: encrypted queue stays isolated and cannot sync into the wrong context; explicit reauthorisation or repair. (Real-device offline sync testing is scheduled S4, ARCHITECTURE §3.)
- [ ] **AT-03**: Unverified phone, or 5 wrong codes: activation blocked; 30-minute lock, then automatic unlock. (partial: O-12, P-3)
- [ ] **AT-04**: Publish locations, then try to rename, move or add: server refuses; the frozen snapshot stays.
- [ ] **AT-05**: Publish a type, then try to edit or rename a field: server refuses; a copy can be created and published separately.
- [ ] **AT-06**: No provider confidence, invalid dropdown value, missing mandatory field: NULL confidence, explicit format and required flags, no silent pass.
- [ ] **AT-07**: Mismatch plus two failures use all 3 attempts: attempt 4 blocked; retake creates a linked new scan; no hidden scan on retry.
- [ ] **AT-08**: Submit Anyway with a mandatory field empty: revision accepted for review with the gap shown; approval blocked; reject and rework available.
- [ ] **AT-09**: Two reviewers act on one revision at once: exactly one current decision; the other gets 409; override is a separate action.
- [ ] **AT-10**: Batch assigned to a trusted technician who captured some of the scans: own scans excluded, up to 50 others assigned; a reassigned reviewer cannot decide the old item. (partial: O-18)
- [ ] **AT-11**: Scan unapproved at 24 hours, or unit with no BU Admin: EA escalation and notification; a decision retires the escalation without deleting history.
- [ ] **AT-12**: Admin removed from one unit but kept in another: session change applies within 60 seconds; the other unit stays authorised; no new signed image URLs for the removed scope. (Session part proven in Phase 1; the signed-URL clause is exercised once photos exist, under NFR-image-storage in Phase 2.)
- [ ] **AT-13**: Download of restricted or out-of-scope CSV or images: blocked by API projection, DLP and authorisation; attempts logged. (partial: O-14, audit-access pair)
- [ ] **AT-14**: Export of 1,001 rows: async file in MinIO, export_ready alert, 1-hour link, scoped download, audit history.
- [ ] **AT-15**: Outbox worker retries after an email or provider timeout: correlated intent and outcome, safe at-least-once reconciliation, no duplicate scan or review rows.
- [ ] **AT-16**: Legally held evidence reaches its retention date: purge suppressed; audit floor kept; job behaviour observable. (partial: P-2)
- [ ] **AT-17**: Attempt to reach a Client Portal or create a PortalReader: no such surface or entitlement exists; no migration or API depends on missing tables.
- [ ] **AT-18**: US hosting versus India E2E data boundary: no production client data in the India E2E database, MinIO, logs, backups or provider test payloads. **BLOCKED (P-14)**

### Release gate (derived from CONSTITUTION §6 and SPEC-PX-10)

- [ ] **GATE-G5**: Sprint 6 gate (delivery lead): all 18 release tests (AT-01 to AT-18) pass with evidence and a named owner; each security or compliance commitment has deployment evidence; security scan clean; rollback tested. (partial: environment procurement, P-13, P-14)
- [ ] **REQ-10.S6**: SPEC-PX-10 Sprint 6 slice: deployment gate that blocks on any failed or skipped check, DAST on the US VPS, rollback, backup/restore test. Detail specified at Sprint 6 G1. (partial: environment procurement)

### Decision-pending requirement pairs (competing variants preserved; neither is picked)

Each pair is a divergence between the baselined PRD and a Draft SPEC or the contracts DOC. Both variants are mapped to the same phase and BLOCKED until the owner records the decision in the root STATE.md (CONSTITUTION §0).

- [ ] **REQ-override-authority-v1**: Override of a decision (PRD matrix + open item 6): Enterprise Admin = Yes; BU Admin unresolved ("EA/admin" in one place, "as V3 policy permits" in another); Technician = No; appends a linked decision row. **BLOCKED (P-6)**
- [ ] **REQ-override-authority-v2**: Override endpoint POST /decisions/{decisionId}/override (contract 3.7): bu_admin only; EA not listed; inserts a decision with overrides_decision_id; alerts the delegated technician (decision_overridden); audit (override). **BLOCKED (P-6)**
- [ ] **REQ-invite-authority-v1**: Contract 1.8 / SPEC REQ-01.10: BU Admin invites technicians (own units only, else 403); EA invites BU Admins (units with no BU Admin only, else 409 unit-has-bu-admin); EA does not invite technicians. **BLOCKED (P-5)**
- [ ] **REQ-invite-authority-v2**: PRD open item 5 / matrix: the implementation PRD says both "EA or BU Admin" invite, giving the EA oversight only; Data Models screens show Invite BU Admin and Invite technician; BRD US-036/US-049 say the BU Admin invites; owner decision pending. **BLOCKED (P-5)**
- [ ] **REQ-audit-access-v1**: PRD matrix, BU-05, FR-6.4, journey J08: BU Admin may read and export scans and audit within their own unit. **BLOCKED (audit-access: owner decision, no PRD or O-number assigned yet)**
- [ ] **REQ-audit-access-v2**: SPEC-PX-07 REQ-07.01 and contracts 3.22 / 4.1: audit_log readable by EA only; GET /audit-log is enterprise_admin only; BU Admin may export scans of their unit but not audit_log. **BLOCKED (audit-access: owner decision, no PRD or O-number assigned yet)**
- [ ] **REQ-phone-change-codes-v1**: Contracts 1.4-1.5 / FR-1.8: the API exposes POST /me/phone-change and POST /me/phone-change/verify taking {code}, counting wrong codes and locking changes for 30 minutes. **BLOCKED (O-12)**
- [ ] **REQ-phone-change-codes-v2**: SPEC-PX-01 O-12 proposal, CONSTITUTION §2.7, ARCHITECTURE §4.2: Keycloak sends and checks activation and phone-change codes via required actions with the same OTP authenticator and lock counter; an event listener tells the API the verified value; endpoints 1.4-1.5 change accordingly; the API has no code or lockout endpoints. **BLOCKED (O-12)**

## Out of Scope (v2 / excluded)

| Item | Reason |
|------|--------|
| Client Portal, PortalReader, client login, publication projection, portal CSV (US-006, US-040 to US-043) | PRD post-V1; CONSTITUTION §0 never-build; AT-17 proves absence |
| SAML as a product flow (US-002) | Admins use email one-time code in V1; admin MFA is P-4 |
| Roles beyond EA, BU Admin, Field Technician; Reviewer; Super Admin | `is_trusted_reviewer` is a capability, not a role (O-1 settled by PRD) |
| Process picker / process selection | One hidden default process per unit |
| Editing a published location tree or equipment type; clone/deactivate; version-two type editing; location CSV import (US-035) | Publish freezes; changes need a new type; post-V1 change request |
| Batch approve / batch reject (US-032) | Batch = review assignments, never bulk approval |
| Push notifications | Bell and email only |
| Quota alerts (80/95/100 percent) and inactive-account detection (US-050, US-052) | PRD excludes; alert levels tracked in quota_usage only |
| Role change endpoint (O-16) | OPEN, no screen or V3 rule |
| BU Admin self-service retention UI (US-038), JSON export, export download history, admin action logging (US-047) | Deferred to V1.1 or later by BRD v2.1 |
| Asset master, on-device VLM inference, ERP/CMMS integration, advanced analytics | Post-V1 |
| Tier 2 SaaS, OAuth2/OIDC mobile auth, in-app billing, multi-language, full WCAG 2.1 AA audit, Helm/Kubernetes, Azure Terraform | Phase 2 of the product |
| A 32nd table or column that changes meaning | Frozen data model (CON-NN-03); written change request required |
| Tablet-native layout, password flows, provider keys on mobile, model training on PPG data, real client data outside a vetted US environment | Constitutional and NFR exclusions |

## Open Decisions Register (what each undecided item gates)

| ID | Question | Gates | Needed by | Proposed (not recorded) |
|----|----------|-------|-----------|-------------------------|
| P-1 | How the tenant and first EA are created | REQ-04.05 | S2 | Operator-only CLI (ARCHITECTURE §4.6) |
| O-11 | Active unit in user_session vs token | FR-1.6, REQ-01.08; partial REQ-01.06, NFR-access-control, MOB-02 | S2 | user_session.active_bu_id + X-Device-Id |
| O-12 | Who sends/checks activation and phone-change codes | FR-1.8, REQ-01.11b, REQ-01.12, phone-change-codes pair; partial FR-1.4, AT-03, MOB-01 | S2 | Keycloak required actions + event listener |
| O-13 | API view of Keycloak lock state | REQ-04.10; partial BU-01 | S2 | Keycloak attack-detection admin API |
| O-23 | Primary unit and multi-invite activation | REQ-01.11c; partial FR-1.4 | S2 | Accept all pending invites; primary = oldest invite's unit |
| P-10 | bu_admin_user_id vs user_unit_role | REQ-04.08, REQ-04.09; partial FR-1.3, EA-01 | S2 | user_unit_role authoritative + constraint trigger |
| P-3 | SMS provider and DLT registration | REQ-01.02b; partial FR-1.4, FR-1.5, AT-03, MOB-01 | S2 | Amzur's existing account; confirm DLT sender and OTP template |
| P-5 | Who may invite whom | REQ-01.10, invite-authority pair; partial FR-1.4, PERM-matrix, EA-01, BU-01 | S2 (before G1 for SPEC-PX-01) | none recorded |
| P-4 | Admin email code as MFA | FR-1.5 (release) | S2 decision, before release | Email code only for V1 |
| Email provider | SES vs SendGrid/SMTP | none (Mailpit locally) | Before a shared environment | SMTP adapter |
| O-5 | Location depth limit | partial FR-2.1 | S3 G1 | none |
| O-15 | AI-assist photo and cost retention | FR-3.3; partial BU-02 | S3 | none |
| O-17 | Photo upload route (API vs signed MinIO URL) | partial FR-4.2 | S3 | none |
| O-20, P-12 | Proxy refusals / ambiguous provider timeouts vs the 3-attempt budget | partial FR-4.5 | S3 | none |
| P-11 | Effective-decision rule over revision and review_decision | EA-03, BU-03, MOB-07; partial FR-5.4 | S4 | none |
| P-6 | Who may override a decision | override-authority pair; partial FR-5.4, PERM-matrix | S4 | none |
| Audit access | BU Admin read/export of audit_log | REQ-07.06, audit-access pair; partial EA-04, FR-6.4, AT-13 | S4 (before G1 for the S4 slice) | no PRD/O-number yet; owner to register |
| O-18 | Who can receive delegated batches / who sets is_trusted_reviewer | partial FR-5.6, BU-04, AT-10 | S4 | none |
| O-21 | Is the reject note required | partial FR-5.4 | S4 | none |
| P-9 / O-7 | Where the per-unit quota ceiling is stored | FR-6.5; partial BU-05, AT-01 | S5 | none |
| O-14 | Where the DLP result is stored | partial FR-6.4, NFR-export, AT-13 | S5 | none |
| O-8 | Who sets retention | partial FR-6.6 | S5 | none |
| P-2 | When the 30-day source-image clock starts; export photo links after purge | partial FR-6.6, AT-16 | S5 | none |
| P-8 | How audit-log 1-year/3-year retention is held | partial FR-6.6, NFR-compliance | S5 | none |
| P-13 | WAL-based backup for the 1-hour RPO | NFR-availability, NFR-backup; partial GATE-G5 | Before procurement | WAL archiving or equivalent |
| P-14 | OpenAI US endpoints + Zero Data Retention evidence | NFR-data-residency, AT-18; partial GATE-G5 | Before release | none |
| Environment procurement | India E2E / US VPS / AWS us-east-1 | partial NFR-encryption, REQ-10.S6, GATE-G5; real-device offline testing | S3-S4 | none |
| P-7 / P-11 note | Scan transition matrix | none blocking: ARCHITECTURE §6 adopts the contracts' "Status moves" table; PRD says the Data Models diagram is authoritative, so confirm | S3 | contracts table |

## Traceability

Every v1 requirement maps to exactly one phase. Phase names: 1 Identity, Tenancy & Isolation (S2); 2 Authoring & Capture-to-Extraction (S3); 3 Review, Delegation & Escalation (S4); 4 Exports, Quota, Retention & Data Security (S5); 5 Release Gate (S6).

| Requirement | Phase | Status |
|-------------|-------|--------|
| FR-1.1 | Phase 1 | Pending |
| FR-1.2 | Phase 1 | Pending |
| FR-1.3 | Phase 1 | Pending (partial: P-10) |
| FR-1.4 | Phase 1 | Pending (partial: P-5, O-12, O-23, P-3) |
| FR-1.5 | Phase 1 | Pending (partial: P-3, P-4) |
| FR-1.6 | Phase 1 | BLOCKED (O-11) |
| FR-1.7 | Phase 1 | Pending |
| FR-1.8 | Phase 1 | BLOCKED (O-12) |
| FR-6.1 | Phase 1 | Pending |
| FR-6.2 | Phase 1 | Pending |
| PERM-matrix | Phase 1 | Pending (partial: P-5, P-6) |
| NFR-secrets | Phase 1 | Pending |
| NFR-access-control | Phase 1 | Pending (partial: O-11) |
| NFR-delivery-pipeline | Phase 1 | Pending |
| AT-03 | Phase 1 | Pending (partial: O-12, P-3) |
| AT-12 | Phase 1 | Pending |
| AT-15 | Phase 1 | Pending |
| EA-01 | Phase 1 | Pending (partial: P-5, P-10) |
| BU-01 | Phase 1 | Pending (partial: P-5, O-13) |
| MOB-01 | Phase 1 | Pending (partial: O-12, P-3) |
| MOB-02 | Phase 1 | Pending (partial: O-11) |
| REQ-01.01 | Phase 1 | Pending |
| REQ-01.02a | Phase 1 | Pending |
| REQ-01.02b | Phase 1 | BLOCKED (P-3) |
| REQ-01.03 | Phase 1 | Pending |
| REQ-01.04 | Phase 1 | Pending |
| REQ-01.05 | Phase 1 | Pending |
| REQ-01.06 | Phase 1 | Pending (partial: O-11) |
| REQ-01.07 | Phase 1 | Pending |
| REQ-01.08 | Phase 1 | BLOCKED (O-11) |
| REQ-01.09 | Phase 1 | Pending |
| REQ-01.10 | Phase 1 | BLOCKED (P-5) |
| REQ-01.11a | Phase 1 | Pending |
| REQ-01.11b | Phase 1 | BLOCKED (O-12) |
| REQ-01.11c | Phase 1 | BLOCKED (O-23) |
| REQ-01.12 | Phase 1 | BLOCKED (O-12) |
| REQ-01.13 | Phase 1 | Pending |
| REQ-04.01 | Phase 1 | Pending |
| REQ-04.02 | Phase 1 | Pending |
| REQ-04.03 | Phase 1 | Pending |
| REQ-04.04 | Phase 1 | Pending |
| REQ-04.05 | Phase 1 | BLOCKED (P-1) |
| REQ-04.06 | Phase 1 | Pending |
| REQ-04.07 | Phase 1 | Pending |
| REQ-04.08 | Phase 1 | BLOCKED (P-10) |
| REQ-04.09 | Phase 1 | BLOCKED (P-10) |
| REQ-04.10 | Phase 1 | BLOCKED (O-13) |
| REQ-07.01 | Phase 1 | Pending |
| REQ-07.02 | Phase 1 | Pending |
| REQ-07.03 | Phase 1 | Pending |
| REQ-07.04 | Phase 1 | Pending |
| REQ-10.01 | Phase 1 | Pending |
| REQ-10.02 | Phase 1 | Pending |
| REQ-10.03 | Phase 1 | Pending |
| REQ-10.04 | Phase 1 | Pending |
| REQ-10.05 | Phase 1 | Pending |
| REQ-10.06 | Phase 1 | Pending |
| REQ-10.07 | Phase 1 | Pending |
| REQ-10.08 | Phase 1 | Pending |
| REQ-invite-authority-v1 | Phase 1 | BLOCKED (P-5) |
| REQ-invite-authority-v2 | Phase 1 | BLOCKED (P-5) |
| REQ-phone-change-codes-v1 | Phase 1 | BLOCKED (O-12) |
| REQ-phone-change-codes-v2 | Phase 1 | BLOCKED (O-12) |
| FR-2.1 | Phase 2 | Pending (partial: O-5) |
| FR-2.2 | Phase 2 | Pending |
| FR-2.3 | Phase 2 | Pending |
| FR-2.4 | Phase 2 | Pending |
| FR-2.5 | Phase 2 | Pending |
| FR-2.6 | Phase 2 | Pending |
| FR-3.1 | Phase 2 | Pending |
| FR-3.2 | Phase 2 | Pending |
| FR-3.3 | Phase 2 | BLOCKED (O-15) |
| FR-3.4 | Phase 2 | Pending |
| FR-3.5 | Phase 2 | Pending |
| FR-3.6 | Phase 2 | Pending |
| FR-3.7 | Phase 2 | Pending |
| FR-4.1 | Phase 2 | Pending |
| FR-4.2 | Phase 2 | Pending (partial: O-17) |
| FR-4.3 | Phase 2 | Pending |
| FR-4.4 | Phase 2 | Pending |
| FR-4.5 | Phase 2 | Pending (partial: O-20, P-12) |
| FR-4.6 | Phase 2 | Pending |
| FR-4.7 | Phase 2 | Pending |
| FR-4.8 | Phase 2 | Pending |
| FR-4.9 | Phase 2 | Pending |
| NFR-image-storage | Phase 2 | Pending |
| NFR-mobile-security | Phase 2 | Pending |
| NFR-mobile-platform | Phase 2 | Pending |
| NFR-ai-privacy | Phase 2 | Pending |
| AT-04 | Phase 2 | Pending |
| AT-05 | Phase 2 | Pending |
| AT-06 | Phase 2 | Pending |
| AT-07 | Phase 2 | Pending |
| EA-02 | Phase 2 | Pending |
| BU-02 | Phase 2 | Pending (partial: O-15) |
| MOB-03 | Phase 2 | Pending |
| MOB-04 | Phase 2 | Pending |
| MOB-06 | Phase 2 | Pending |
| FR-5.1 | Phase 3 | Pending |
| FR-5.2 | Phase 3 | Pending |
| FR-5.3 | Phase 3 | Pending |
| FR-5.4 | Phase 3 | Pending (partial: P-11, P-6, O-21) |
| FR-5.5 | Phase 3 | Pending |
| FR-5.6 | Phase 3 | Pending (partial: O-18) |
| FR-5.7 | Phase 3 | Pending |
| FR-5.8 | Phase 3 | Pending |
| FR-6.3 | Phase 3 | Pending |
| REQ-07.05 | Phase 3 | Pending |
| REQ-07.06 | Phase 3 | BLOCKED (audit-access) |
| AT-02 | Phase 3 | Pending |
| AT-08 | Phase 3 | Pending |
| AT-09 | Phase 3 | Pending |
| AT-10 | Phase 3 | Pending (partial: O-18) |
| AT-11 | Phase 3 | Pending |
| EA-03 | Phase 3 | BLOCKED (P-11) |
| EA-04 | Phase 3 | Pending (partial: audit-access) |
| BU-03 | Phase 3 | BLOCKED (P-11) |
| BU-04 | Phase 3 | Pending (partial: O-18) |
| MOB-05 | Phase 3 | Pending |
| MOB-07 | Phase 3 | BLOCKED (P-11) |
| REQ-override-authority-v1 | Phase 3 | BLOCKED (P-6) |
| REQ-override-authority-v2 | Phase 3 | BLOCKED (P-6) |
| REQ-audit-access-v1 | Phase 3 | BLOCKED (audit-access) |
| REQ-audit-access-v2 | Phase 3 | BLOCKED (audit-access) |
| FR-6.4 | Phase 4 | Pending (partial: O-14, audit-access) |
| FR-6.5 | Phase 4 | BLOCKED (P-9 / O-7) |
| FR-6.6 | Phase 4 | Pending (partial: O-8, P-2, P-8) |
| NFR-encryption | Phase 4 | Pending (partial: environment procurement) |
| NFR-export | Phase 4 | Pending (partial: O-14) |
| AT-01 | Phase 4 | Pending (partial: P-9 / O-7) |
| AT-13 | Phase 4 | Pending (partial: O-14, audit-access) |
| AT-14 | Phase 4 | Pending |
| AT-16 | Phase 4 | Pending (partial: P-2) |
| BU-05 | Phase 4 | Pending (partial: P-9 / O-7) |
| GATE-G5 | Phase 5 | Pending (partial: environment procurement, P-13, P-14) |
| REQ-10.S6 | Phase 5 | Pending (partial: environment procurement) |
| NFR-performance | Phase 5 | Pending |
| NFR-availability | Phase 5 | BLOCKED (P-13) |
| NFR-scale | Phase 5 | Pending |
| NFR-data-residency | Phase 5 | BLOCKED (P-14) |
| NFR-compliance | Phase 5 | Pending (partial: P-8) |
| NFR-backup | Phase 5 | BLOCKED (P-13) |
| AT-17 | Phase 5 | Pending |
| AT-18 | Phase 5 | BLOCKED (P-14) |

## Coverage

- v1 tracked entries: 144 (136 requirements + 8 competing-variant entries forming 4 decision pairs)
- Mapped to phases: 144
- Unmapped: 0
- Duplicated across phases: 0

| Phase | Entries | BLOCKED | Pending (partial) |
|-------|---------|---------|-------------------|
| Phase 1 | 63 | 16 (12 requirements + 4 variant entries) | 11 |
| Phase 2 | 35 | 1 | 4 |
| Phase 3 | 26 | 8 (4 requirements + 4 variant entries) | 5 |
| Phase 4 | 10 | 1 | 8 |
| Phase 5 | 10 | 4 | 3 |
| Total | 144 | 30 (22 requirements + 8 variant entries) | 31 |

---
*Requirements defined: 2026-10-14*
*Last updated: 2026-10-14 after roadmap creation from ingest of 10 planning docs*

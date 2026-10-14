# Constraints (synthesized intel)

Sources: specs/SPEC-PX-01.md, specs/SPEC-PX-04.md, specs/SPEC-PX-07.md, specs/SPEC-PX-10.md. All four SPECs are `Status: Draft - awaiting G1`; none is approved. SPEC-PX-02, 03, 05, 06, 08, 09, 11 are referenced by CONSTITUTION/ARCHITECTURE but are not in the ingest set.

Bracketed [TBD ...] values are copied from the source and are genuinely undecided there. BLOCKED means the spec itself marks the requirement as not buildable until the named decision is recorded in STATE.md.

---

# SPEC-PX-01 - Identity, sessions & invites

## SPEC-PX-01 header and dependent decisions
- source: specs/SPEC-PX-01.md
- type: protocol
- content: Bounded context BC-01. Grade A0 for Keycloak config, OTP authenticators, event listener, request-context middleware and client auth code; A1 for endpoints. PRD: FR-1.4 to FR-1.8, journey J02, screens MOB-01, MOB-02, EA-01, BU-01. Contracts: Slice 1, 1.1-1.11. Release tests AT-03, AT-12 (part). Sprint S2 (ends Oct 20, 2026). Status Draft. Decisions this spec depends on: O-1/O-2 settled by PRD (3 roles; admins sign in by email code, no SAML). O-11 active unit location: proposed user_session.active_bu_id keyed by X-Device-Id (V3 model), "Decide today". O-12 who sends/checks activation and phone-change codes: proposed Keycloak via required actions using the same OTP authenticator and lock counter; Keycloak event listener tells the API the verified value; endpoints 1.4-1.5 change accordingly; "Decide today". O-22 invites in S2 or S5: settled S2. O-23 multi-unit activation: proposed accepting one link accepts all pending invites for that email, is_primary = unit of the oldest invite; "Decide today". P-3 SMS provider: Amzur's existing account, confirm DLT sender + OTP template, "Confirm today". P-4 admin MFA: email code only for V1 pending owner decision; Open (not blocking S2 build). Email provider: Outbox -> SMTP adapter, Mailpit locally, provider chosen before a shared environment exists; Open (not blocking). Requirements that depend on an undecided item are marked BLOCKED and must not be built until the decision is recorded in STATE.md. Out of scope: SAML SSO, role change endpoint (O-16), trusted-reviewer flag (O-18), any password flow, notification bell (S4).

## REQ-01.01 Keycloak realm as code (A0)
- source: specs/SPEC-PX-01.md
- type: protocol
- content: Realm `pixorex` defined in keycloak/realm-pixorex.json and imported on container start. Public clients `pixorex-web` and `pixorex-mobile` use Authorization Code + PKCE; no passwords; protocol mappers emit `tenant_id` and `app_user_id` claims. GIVEN a clean Compose stack WHEN Keycloak starts THEN the realm, both clients and the mappers exist without manual steps. GIVEN a signed-in user WHEN the access token is decoded THEN it contains tenant_id and app_user_id matching the app_user row. GIVEN any client WHEN a password grant is attempted THEN Keycloak refuses it.

## REQ-01.02 Sign-in by one-time code (A0), FR-1.5
- source: specs/SPEC-PX-01.md
- type: protocol
- content: Technicians choose SMS or email; admins get email only. Codes are single-use and short-lived [TBD: TTL, e.g. 5 min]. GIVEN an active technician with a verified phone WHEN they choose SMS and enter the correct code THEN they receive tokens and land in the app. GIVEN an active technician WHEN they choose email and enter the correct code THEN they receive tokens. GIVEN an active admin WHEN the sign-in page loads THEN only the email option is offered. GIVEN a used or expired code WHEN it is entered THEN sign-in fails with an explicit expired/invalid message (MOB-01) and counts as a wrong code. GIVEN a user whose app_user.status is not active WHEN they try to sign in THEN no code is sent and sign-in fails.

## REQ-01.03 Lockout (A0), FR-1.5, AT-03
- source: specs/SPEC-PX-01.md
- type: protocol
- content: GIVEN a user WHEN the 5th wrong code is entered (counting both channels) THEN sign-in is locked for 30 minutes and the app shows the locked state with time remaining. GIVEN a locked user WHEN 30 minutes pass THEN sign-in works again with no admin action. GIVEN a lock WHEN it starts THEN one audit_log row (category sign_in, actor system) is written via the event listener. GIVEN 4 wrong codes then a correct one THEN sign-in succeeds and the counter resets.

## REQ-01.04 Code-request throttling (A0)
- source: specs/SPEC-PX-01.md
- type: protocol
- content: GIVEN a user WHEN they request more than [TBD: 5] codes in [TBD: 15 min] THEN further requests are refused without sending, for that user and that destination.

## REQ-01.05 Sign-in event listener (A0), FR-1.5
- source: specs/SPEC-PX-01.md
- type: protocol
- content: A Keycloak event listener posts LOGIN, LOGIN_ERROR and lockout events to an internal, network-restricted API endpoint (not in the public contract) authenticated by a Vault-held shared secret. GIVEN a successful sign-in WHEN the event fires THEN an audit_log row (sign_in) is written with user, tenant and device, and no code value. GIVEN the API is unreachable WHEN an event fires THEN the listener retries and does not block sign-in.

## REQ-01.06 Request context middleware (A0), FR-1.6, FR-1.7, NFR access control
- source: specs/SPEC-PX-01.md
- type: protocol
- content: Implements ARCHITECTURE §4.4. GIVEN no token, an expired token or a token for another realm WHEN any authenticated endpoint is called THEN 401. GIVEN a valid token WHEN app_user.status is removed THEN 401. GIVEN a session whose revoked_at is set WHEN a call is made THEN 401 within 60 seconds of revocation. GIVEN a valid call WHEN the transaction starts THEN app.tenant_id, app.user_id, app.bu_ids, app.is_ea are set with SET LOCAL and are absent on the next pooled connection. GIVEN /health, /ready, /invites/preview, /invites/accept WHEN called without a token THEN they work; every other path requires one. GIVEN any call WHEN it completes THEN app_user.last_active_at is updated at most once per [TBD: 5 min].

## REQ-01.07 GET /me - contract 1.1
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: GIVEN a technician in units X and Y WHEN they call /me THEN the response lists both units with role, is_primary, assigned_by_name, plus active_bu_id, last_bu_id and tenant.name. GIVEN an EA WHEN they call /me THEN units list the tenant's units with role enterprise_admin. GIVEN a user removed from unit Y WHEN they call /me THEN Y is not listed.

## REQ-01.08 PUT /me/active-unit - contract 1.2 (depends on O-11)
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: GIVEN a user with an active role in unit Y WHEN they set bu_id = Y with header X-Device-Id THEN user_session.active_bu_id for that device and app_user.last_bu_id become Y, with no new sign-in. GIVEN a unit where the user holds no active role WHEN they set it THEN 403. GIVEN two devices WHEN one switches unit THEN the other device's active unit is unchanged.

## REQ-01.09 POST /me/sign-out - contract 1.3
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: GIVEN a signed-in device WHEN sign-out is called THEN that device's user_session.revoked_at is set, an audit_log row (sign_in) is written, and 204 is returned; the other devices stay signed in.

## REQ-01.10 Create and manage invites - contracts 1.8-1.11, FR-1.4
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: GIVEN a BU Admin of unit X WHEN they invite a technician for X THEN one invite row per unit is created with the same token_hash, expires_at = now + 24h, an outbox_event for the email, and an audit_log row (users), all in one transaction. GIVEN a BU Admin WHEN they invite for a unit they do not run THEN 403. GIVEN an EA WHEN they invite a BU Admin for a unit that already has one THEN 409 unit-has-bu-admin. GIVEN a stored invite WHEN the table is read THEN only the token hash is stored, never the token. GIVEN GET /invites WHEN a BU Admin calls it THEN they see technician invites of their units only; an EA sees BU Admin invites; rows past expires_at show expired. GIVEN a pending or expired invite WHEN it is resent THEN a new token and a new 24 h window are issued and the old link stops working. GIVEN an invite WHEN it is cancelled THEN status becomes cancelled and the link stops working. GIVEN an invite that expires unused THEN an invite_expired notification is raised (notification table lands in S4; until then the outbox records the intent) [confirm with spec owner]. NOTE: who may invite whom is PRD open item 5; see requirements.md REQ-invite-authority-v1/v2.

## REQ-01.11 Invite preview and accept - contracts 1.6-1.7, FR-1.4 (part BLOCKED by O-12, O-23)
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: GIVEN a valid token in the body WHEN preview is called THEN role, email, units, inviter and expiry are returned; the token never appears in a URL or log. GIVEN an expired, used or cancelled token THEN 409 invite-expired / invite-used / invite-cancelled. GIVEN a valid token WHEN accept is called THEN app_user (status invited) and one user_unit_role per invite row are created, the Keycloak user is created with app_user_id/tenant_id attributes, the invite is marked used, and an audit_log row (users) is written in one transaction. GIVEN the user then verifies their phone (technician) or email (admin) THEN app_user.status becomes active - BLOCKED (O-12) for the verification mechanism. GIVEN a technician WHEN they accept THEN they never gain web dashboard access. Multi-invite activation and is_primary choice - BLOCKED (O-23).

## REQ-01.12 Phone change - contracts 1.4-1.5, FR-1.8 - BLOCKED (O-12)
- source: specs/SPEC-PX-01.md
- type: api-contract
- content: Target behaviour once decided: change saved only after the code sent to the new number is verified; 5 wrong codes lock phone changes for 30 minutes; success revokes every other session of the user, emails the user and writes an audit_log row (users); a number already in use -> 409 phone-in-use. NOTE: see requirements.md REQ-phone-change-codes-v1/v2.

## REQ-01.13 Client sign-in (A0 for token handling, A2 for screens)
- source: specs/SPEC-PX-01.md
- type: protocol
- content: Web: OIDC Authorization Code + PKCE against pixorex-web; tokens in memory only; silent refresh; sign-out ends the Keycloak session and calls 1.3. Mobile: system browser (AppAuth) + PKCE against pixorex-mobile; tokens in secure storage (Keychain / Keystore); X-Device-Id generated once per install and sent on every call. GIVEN a signed-in user WHEN the access token expires THEN the client refreshes without user action. GIVEN a locked account WHEN the user returns to the app THEN MOB-01 shows the locked state.

---

# SPEC-PX-04 - Tenancy, roles & RLS

## SPEC-PX-04 header and dependent decisions
- source: specs/SPEC-PX-04.md
- type: schema
- content: Bounded context BC-04. Grade A0 for RLS policies, DB grants and authorization helpers; A1 for schema migrations and bootstrap; A2 for CRUD endpoints. PRD: FR-1.1, FR-1.2, FR-1.3, data-model invariants, journey J01 (unit creation), J02 (removal), screens EA-01, BU-01. Contracts: Slice 1, 1.12-1.19. Release test AT-12. Sprint S2 (ends Oct 20, 2026). Status Draft. Decisions: P-1 creating tenant and first EA - proposed operator-only CLI (ARCHITECTURE §4.6), "Decide today". P-10 bu_admin_user_id vs user_unit_role - proposed user_unit_role authoritative, column set in the same transaction, deferred constraint trigger checks agreement, "Decide today". O-13 lock state in technician list - proposed read from Keycloak attack-detection admin API per listed user, "Decide today". O-5 location depth limit - not needed in S2, deferred to S3. Out of scope: role change (O-16), trusted-reviewer flag (O-18), location tree content (SPEC-PX-05), quota and retention screens (SPEC-PX-11).

## REQ-04.01 Domain 1 schema (A1) - frozen model
- source: specs/SPEC-PX-04.md
- type: schema
- content: Migrations create tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session exactly as in the V3 Data Models document, plus location_hierarchy_version (needed by unit creation). GIVEN the migration WHEN compared with the Data Models document THEN table and column names, types, nullability, keys and status values match; no extra tables or columns. GIVEN any tenant-owned table THEN it has tenant_id, created_at, updated_at, and every FK to another tenant-owned table includes tenant_id. GIVEN an attempt to link a row to a parent in another tenant THEN the insert fails at the database. GIVEN uniqueness rules THEN the DB enforces: email unique per tenant; phone (E.164) unique; one active BU Admin per unit (partial unique index on active bu_admin rows); one default business_process per unit.

## REQ-04.02 Database roles and grants (A0)
- source: specs/SPEC-PX-04.md
- type: schema
- content: GIVEN the API connection role WHEN it queries any tenant-owned table THEN RLS applies (role is not owner and lacks BYPASSRLS). GIVEN migrations THEN they run under a separate owner role whose credentials are only used by the migration job.

## REQ-04.03 RLS policies (A0), FR-1.2
- source: specs/SPEC-PX-04.md
- type: schema
- content: Policies per ARCHITECTURE §4.5 for every Domain 1 table and location_hierarchy_version. GIVEN users in tenants A and B WHEN a tenant-B user lists units, users, invites or sessions THEN no tenant-A row is returned, and fetching a tenant-A id returns 404. GIVEN a BU Admin of unit X WHEN they query technicians THEN unit Y's rows are invisible. GIVEN an EA WHEN they query THEN all units of their tenant are visible and none of another tenant. GIVEN no RLS context set (e.g. a code path that forgot the middleware) THEN queries return zero rows rather than all rows. An isolation test harness (tests/isolation/) seeds two tenants x two units and is reused by every later table.

## REQ-04.04 Authorization helpers (A0), FR-1.3
- source: specs/SPEC-PX-04.md
- type: api-contract
- content: A single module provides require_role(roles, bu_id) used by every router. GIVEN a caller without an active role in {buId} THEN 403 forbidden. GIVEN an EA THEN they pass for any unit in their tenant. GIVEN a technician holding an open review_assignment for a scan THEN they act as delegated_technician for that scan only (helper exists now; used in S4). Every endpoint is covered by a role-boundary test generated from its x-roles in the contract.

## REQ-04.05 Tenant bootstrap CLI (A1), P-1 (if approved)
- source: specs/SPEC-PX-04.md
- type: protocol
- content: GIVEN an operator with migration credentials WHEN they run `bootstrap_tenant.py --name ... --ea-email ...` THEN a tenant, an app_user + enterprise_admin role, the Keycloak user with claims, and default retention_config rows are created, with an audit_log row (actor system). GIVEN the tenant already exists THEN the script exits without changes. The script is not reachable over HTTP.

## REQ-04.06 Synthetic seed (A2)
- source: specs/SPEC-PX-04.md
- type: schema
- content: seed_synthetic.py creates the demo dataset: 2 tenants, 3 units, EA, BU Admins, technicians (fake names and numbers, test SMS destinations only), and one unit with no BU Admin. No real PPG data.

## REQ-04.07 List and read units - contracts 1.12, 1.14
- source: specs/SPEC-PX-04.md
- type: api-contract
- content: GIVEN an EA WHEN they call GET /business-units THEN every unit of the tenant is returned with BU Admin (or null), waiting_count, escalated_count, locations_status; ?no_bu_admin=true filters vacant units. GIVEN a BU Admin WHEN they call it THEN only the units they run are returned. Counts that depend on S3-S4 tables return 0 until those tables exist [confirm].

## REQ-04.08 Create unit - contract 1.13, FR-1.1
- source: specs/SPEC-PX-04.md
- type: api-contract
- content: GIVEN an EA WHEN they create a unit THEN business_unit, exactly one default business_process (is_default = true) and a location_hierarchy_version (not_published) are created with an audit_log row (users) in one transaction. GIVEN bu_admin.invite_email THEN an invite is created as in REQ-01.10 in the same transaction. GIVEN bu_admin.user_id of an existing BU Admin THEN the role row and bu_admin_user_id are set (P-10 rule). GIVEN a duplicate unit name in the tenant THEN 409 duplicate-name. GIVEN a non-EA caller THEN 403.

## REQ-04.09 BU Admin management - contracts 1.15-1.17, FR-1.3
- source: specs/SPEC-PX-04.md
- type: api-contract
- content: GIVEN an EA WHEN they list BU Admins THEN name, email, units, status and last_active_at are returned. GIVEN an EA WHEN they assign a unit already run by someone else THEN 409 unit-has-bu-admin; assigning a unit with a pending BU Admin invite cancels that invite. GIVEN an EA WHEN they remove a BU Admin from units THEN user_unit_role.removed_at is set, those units get bu_admin_user_id = null, the account and history stay, and an audit_log row (users) is written; removal from all units revokes every session at once. GIVEN replacement_invite_email THEN an invite is created for those units. GIVEN the removed admin's next call scoped to a removed unit THEN 403 within 60 seconds; their other units still work (AT-12).

## REQ-04.10 Technician management - contracts 1.18-1.19
- source: specs/SPEC-PX-04.md
- type: api-contract
- content: GIVEN a BU Admin of unit X WHEN they list technicians THEN each row shows name, email, status, units, last_active_at and sign_in_locked_until (O-13); scans_this_month and active_batch_no are 0/null until S3-S4. GIVEN a BU Admin WHEN they remove a technician from X THEN user_unit_role.removed_at is set, the technician's access to X ends within 60 seconds, open review_assignment rows would close with user_removed (S4 table; no-op until then), and an audit_log row (users) is written. GIVEN a BU Admin WHEN they try to remove a technician from a unit they do not run THEN 403.

---

# SPEC-PX-07 - Audit, outbox & notifications

## SPEC-PX-07 header
- source: specs/SPEC-PX-07.md
- type: schema
- content: Bounded context BC-07. Grade A1 (audit write path, grants and partitioning human-reviewed). PRD: FR-6.1, FR-6.2, FR-6.3. Contracts 3.19-3.22 (S4). Release test AT-15. Sprint: S2 REQ-07.01 to 07.04 (foundation); S4 REQ-07.05 to 07.06. Status Draft. Sprint 2 needs only the foundation: every Slice 1 write must audit, and invite emails go through the outbox.

## REQ-07.01 audit_log table (A1), FR-6.1
- source: specs/SPEC-PX-07.md
- type: schema
- content: Created per the Data Models document, partitioned by month, with categories sign_in, users, locations, equipment_types, review, override, escalation, export, retention and actor type user or system. GIVEN the API role WHEN it tries UPDATE or DELETE on audit_log THEN the database refuses (no grant). GIVEN a write in a month with no partition THEN it succeeds (partitions created ahead by migration or job). RLS: tenant-scoped; readable by EA only (enforced at the API in S4, by policy now). NOTE: "readable by EA only" diverges from PRD; see requirements.md REQ-audit-access-v1/v2.

## REQ-07.02 Audit writer (A1)
- source: specs/SPEC-PX-07.md
- type: protocol
- content: One service function audit.record(category, action, object_type, object_id, details) that uses the current transaction and request context. GIVEN a service write marked Audit WHEN the transaction commits THEN exactly one audit row exists for it. GIVEN the business write fails and rolls back THEN no audit row exists. GIVEN details THEN it never contains tokens, codes, secrets or invite tokens (test with a denylist).

## REQ-07.03 outbox_event + enqueue (A1), FR-6.2
- source: specs/SPEC-PX-07.md
- type: protocol
- content: GIVEN a service that needs an external effect WHEN it calls outbox.enqueue(kind, payload, correlation_id) THEN the row is written in the same transaction as the change and its audit row. GIVEN a rollback THEN no outbox row exists and nothing is sent.

## REQ-07.04 Outbox worker + email adapter (A2), FR-6.2, AT-15
- source: specs/SPEC-PX-07.md
- type: protocol
- content: GIVEN a pending event WHEN the worker runs THEN it claims it with FOR UPDATE SKIP LOCKED, executes it and records success with the correlation id. GIVEN a transient failure (e.g. SMTP timeout) THEN it retries with exponential backoff up to [TBD: 8] times, then marks the event failed and logs it. GIVEN two workers THEN no event is executed twice concurrently; handlers are idempotent on the event id. GIVEN an invite_email event locally THEN the email arrives in Mailpit with the magic link.

## REQ-07.05 Notifications (S4), FR-6.3, contracts 3.19-3.21
- source: specs/SPEC-PX-07.md
- type: api-contract
- content: 17 kinds, bell panel + email, no push. Specified at S4 G1 (detail absent).

## REQ-07.06 Audit log read (S4), contract 3.22
- source: specs/SPEC-PX-07.md
- type: api-contract
- content: Specified at S4 G1 (detail absent).

---

# SPEC-PX-10 - DevSecOps & resilience (Sprint 2 slice)

## SPEC-PX-10 header
- source: specs/SPEC-PX-10.md
- type: nfr
- content: Bounded context BC-10 (+ BC-09 for Vault loading). Grade A1 (DevOps signs off every gate change); A0 for Vault secret loading. PRD: Delivery pipeline NFR (US-062 to US-067), Secrets NFR (US-055, US-064). Contracts 4.3 /health, 4.4 /ready. Sprint: S2 REQ-10.01 to 10.08; S6 deployment gate, DAST, rollback, backup/restore. Status Draft.

## REQ-10.01 Local stack
- source: specs/SPEC-PX-10.md
- type: nfr
- content: GIVEN a clean checkout WHEN `docker compose up` runs THEN api, worker, keycloak (realm imported), postgres 16, minio, vault (dev) and mailpit start healthy, migrations apply and /ready returns ready. GIVEN `make seed` THEN the synthetic dataset (REQ-04.06) loads. GIVEN the README THEN a new engineer gets from clone to a signed-in demo user in under 30 minutes.

## REQ-10.02 API skeleton and probes - contracts 4.3, 4.4
- source: specs/SPEC-PX-10.md
- type: api-contract
- content: FastAPI app with the layering, problem+json error handler, JSON logging with correlation_id, config validation at startup. GIVEN /health THEN {status: "ok"} without a token. GIVEN any dependency down WHEN /ready is called THEN 503 with per-dependency ok/fail, and no versions or secrets. This is the G2 baseline PR for the API; architects review it personally.

## REQ-10.03 Secrets from Vault (A0, BC-09)
- source: specs/SPEC-PX-10.md
- type: nfr
- content: GIVEN the api, worker and keycloak containers WHEN they start THEN DB, Keycloak admin, SMS, SMTP and listener secrets are read from Vault, not from env vars or files (local dev Vault seeded by a script with synthetic values). GIVEN Vault unreachable at start THEN the container fails fast with a clear error.

## REQ-10.04 CI: tests and coverage
- source: specs/SPEC-PX-10.md
- type: nfr
- content: GIVEN a PR THEN path-filtered workflows run: api (ruff, mypy, pytest against the Compose services, isolation suite), web (lint, typecheck, unit tests, build), mobile (analyze, tests), keycloak (build SPI, realm import smoke test). A change under contracts/ triggers all. GIVEN changed lines below 80% coverage THEN the check fails.

## REQ-10.05 CI: security gates
- source: specs/SPEC-PX-10.md
- type: nfr
- content: Secret scan (e.g. gitleaks) on every push and PR, blocking. SAST (e.g. Semgrep + Bandit) and dependency scan (e.g. pip-audit, npm audit, osv-scanner), blocking on high/critical. Container image scan (e.g. Trivy) on Dockerfiles, blocking on critical. GIVEN any gate skipped or errored THEN the PR cannot merge.

## REQ-10.06 CI: contract and PR rules
- source: specs/SPEC-PX-10.md
- type: nfr
- content: Spectral lint on contracts/ with the repo's .spectral.yaml. PR size check: diff > 300 lines fails (generated files and lockfiles excluded by list). PR title must start with a task ID matching `PX-\d{2}-T\d{2}`.

## REQ-10.07 Branch protection and ownership
- source: specs/SPEC-PX-10.md
- type: nfr
- content: main: no direct pushes, 2 approvals, CODEOWNERS review required, all checks required, linear history. CODEOWNERS as in ARCHITECTURE §11.

## REQ-10.08 AI review job (may slip to S3)
- source: specs/SPEC-PX-10.md
- type: nfr
- content: GIVEN a PR THEN a job runs .claude/ai-review-prompt.md with the pinned review model against the diff, the linked spec and the constitution, and posts a PASS / WARN / FAIL report as a PR comment. FAIL blocks merge.

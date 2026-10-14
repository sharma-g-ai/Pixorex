# Roadmap: Pixorex V1

## Overview

Pixorex V1 delivers AI-powered nameplate digitization for PPG Industries as five vertical slices, one per sprint (Sprint 1 was design and is complete). Phase 1 (Sprint 2) lays the identity, tenancy and isolation foundation so a signed-in user lands in their own unit, sees only what their role allows, and isolation is proven by tests. Phase 2 (Sprint 3) lets admins publish locations and equipment types and lets a technician capture a nameplate and get an AI extraction. Phase 3 (Sprint 4) closes the human loop: field verification, separate-person approval, delegation and 24-hour escalation. Phase 4 (Sprint 5) adds scoped CSV export, quota and retention. Phase 5 (Sprint 6) is the release gate: all 18 release tests (AT-01 to AT-18) pass with evidence, plus the measurable NFRs. Everything runs on the local Docker Compose stack with synthetic data until a vetted US environment exists. Requirements gated by open decisions are mapped to their phase and marked BLOCKED in `.planning/REQUIREMENTS.md`; per CONSTITUTION §0 they are not built until the decision is recorded in the root STATE.md.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Identity, Tenancy & Isolation** - Sprint 2, ends Tue Oct 20, 2026: a signed-in user lands in their own unit, sees only what their role allows, isolation proven by tests
- [ ] **Phase 2: Authoring & Capture-to-Extraction** - Sprint 3, ends Tue Nov 03, 2026: locations and equipment types published; technician captures and gets AI extraction
- [ ] **Phase 3: Review, Delegation & Escalation** - Sprint 4, ends Tue Nov 17, 2026: technician verification, separate-person approval, delegation, escalation, notifications, audit view
- [ ] **Phase 4: Exports, Quota, Retention & Data Security** - Sprint 5, ends Tue Dec 01, 2026: scoped CSV export, monthly quota, retention enforcement, encryption controls
- [ ] **Phase 5: Release Gate** - Sprint 6, ends Tue Dec 15, 2026: all 18 release tests with evidence, measurable NFRs, residency, backup/DR, deployment gate

## Phase Details

### Phase 1: Identity, Tenancy & Isolation
**Goal**: A signed-in user lands in their own unit, sees only what their role allows, and the isolation is proven by tests (Sprint 2, ends Tue Oct 20, 2026; contract Slice 1 "Auth + RBAC", endpoints 1.1-1.19, 4.3-4.4; G1 pending for SPEC-PX-01, 04, 07, 10).
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: FR-1.1, FR-1.2, FR-1.3, FR-1.4, FR-1.5, FR-1.6, FR-1.7, FR-1.8, FR-6.1, FR-6.2, PERM-matrix, NFR-secrets, NFR-access-control, NFR-delivery-pipeline, AT-03, AT-12, AT-15, EA-01, BU-01, MOB-01, MOB-02, REQ-01.01, REQ-01.02a, REQ-01.02b, REQ-01.03, REQ-01.04, REQ-01.05, REQ-01.06, REQ-01.07, REQ-01.08, REQ-01.09, REQ-01.10, REQ-01.11a, REQ-01.11b, REQ-01.11c, REQ-01.12, REQ-01.13, REQ-04.01, REQ-04.02, REQ-04.03, REQ-04.04, REQ-04.05, REQ-04.06, REQ-04.07, REQ-04.08, REQ-04.09, REQ-04.10, REQ-07.01, REQ-07.02, REQ-07.03, REQ-07.04, REQ-10.01, REQ-10.02, REQ-10.03, REQ-10.04, REQ-10.05, REQ-10.06, REQ-10.07, REQ-10.08, REQ-invite-authority-v1, REQ-invite-authority-v2, REQ-phone-change-codes-v1, REQ-phone-change-codes-v2
**Blocked (do not build until the decision is recorded)**: FR-1.6 and REQ-01.08 (O-11); FR-1.8 and REQ-01.12 and phone-change-codes pair (O-12); REQ-01.11b (O-12); REQ-01.11c (O-23); REQ-01.02b (P-3); REQ-04.05 (P-1); REQ-04.08, REQ-04.09 (P-10); REQ-04.10 (O-13); REQ-01.10 and invite-authority pair (P-5). Not on the root STATE.md "Decisions needed today" list: P-5.
**Success Criteria** (what must be TRUE):
  1. An Enterprise Admin signs in with an emailed one-time code, sees every unit of their tenant, creates a unit (a default business process is seeded, no process picker) and invites its BU Admin; the BU Admin accepts, signs in the same way and sees only the unit(s) they run (FR-1.1, FR-1.3, FR-1.4, EA-01, BU-01).
  2. A technician accepts an invite on the phone, signs in by SMS code (and once by email code), lands on Home in their unit, switches between assigned units without signing in again, and is refused (403) for any unit where they hold no active role (FR-1.4, FR-1.5, FR-1.6, MOB-01, MOB-02).
  3. Isolation is proven by tests: the isolation suite (2 tenants x 2 units) passes in CI, showing a tenant-B user cannot read tenant-A rows (404), a BU Admin of unit X cannot see unit Y, an EA sees all units of only their own tenant, and a query with no RLS context returns zero rows (FR-1.2, REQ-04.03, NFR-access-control).
  4. Five wrong codes lock sign-in for 30 minutes with an explicit locked state and automatic unlock, writing one sign_in audit row; and an admin removed from one unit is refused for that unit within 60 seconds while their other unit stays authorised (FR-1.5, FR-1.7, AT-03, AT-12).
  5. A new engineer runs `docker compose up` on a clean checkout and gets a healthy stack (secrets read from Vault, migrations applied, `make seed` loading synthetic data); every Slice 1 write commits its audit row in the same transaction; an invite email reaches Mailpit through the outbox worker and survives a retry without duplicating; CI blocks merge on failed or skipped secret-scan, SAST, dependency, container, coverage, contract-lint and PR-rule gates (FR-6.1, FR-6.2, NFR-secrets, NFR-delivery-pipeline, AT-15).
**Plans**: TBD
**UI hint**: yes

### Phase 2: Authoring & Capture-to-Extraction
**Goal**: Admins publish a unit's locations and equipment types, and a technician captures a nameplate (1-4 photos, offline-safe) that is acknowledged immediately and extracted by the AI Inference Proxy in the background (Sprint 3, ends Tue Nov 03, 2026; contract Slice 2 "AI layer + schema", endpoints 2.1-2.27; SPEC-PX-02, 03, 05, 06 to be written and passed at G1).
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: FR-2.1, FR-2.2, FR-2.3, FR-2.4, FR-2.5, FR-2.6, FR-3.1, FR-3.2, FR-3.3, FR-3.4, FR-3.5, FR-3.6, FR-3.7, FR-4.1, FR-4.2, FR-4.3, FR-4.4, FR-4.5, FR-4.6, FR-4.7, FR-4.8, FR-4.9, NFR-image-storage, NFR-mobile-security, NFR-mobile-platform, NFR-ai-privacy, AT-04, AT-05, AT-06, AT-07, EA-02, BU-02, MOB-03, MOB-04, MOB-06
**Blocked (do not build until the decision is recorded)**: FR-3.3 AI-assisted type drafting (O-15). Partially gated: FR-2.1 depth limit (O-5), FR-4.2 upload route (O-17), FR-4.5 proxy refusals and ambiguous timeouts vs the attempt budget (O-20, P-12), BU-02 AI-assist panel (O-15).
**Success Criteria** (what must be TRUE):
  1. The EA defines a unit's levels and builds the node tree, sees a preview and an irreversible-change warning, and publishes; afterwards the server refuses any rename, move, add or delete, and the frozen tree_snapshot is what the phone caches (FR-2.1 to FR-2.5, EA-02, AT-04).
  2. A BU Admin builds an equipment type from blank or a copy, configures typed fields (dropdown needs 2+ choices), and publishes it; afterwards edits and renames are refused, a copy can be created and published separately, and publishing creates an extraction contract bound to one prompt version (FR-3.1, FR-3.2, FR-3.4, FR-3.5, BU-02, AT-05).
  3. A technician picks a published type and a location (tenant name shown as a read-only Customer header), takes 1-4 photos with a quality retake-or-confirm preview, and nothing is transmitted before confirmation; an offline capture sits in the encrypted queue with a visible count and syncs oldest-first, and a repeated upload with the same client_capture_id returns the same scan (FR-2.4, FR-2.6, FR-3.6, FR-4.1 to FR-4.3, MOB-03, MOB-04).
  4. Upload is acknowledged in under 500 ms and extraction runs in the background (target under 15 s at p95) through the AI Inference Proxy with no provider key on the phone; results store one AI value per field, and a missing confidence, an invalid dropdown value or a missing mandatory field is flagged explicitly and never silently passed (FR-4.4 to FR-4.7, FR-4.9, FR-3.7, NFR-ai-privacy, AT-06).
  5. A type mismatch shows the detected label and a suggested type and re-extracts only after the technician approves; retries and re-extracts share a budget of 3 attempts, the 4th is blocked, and a physical retake creates a new linked scan; photos are reachable only through private MinIO 15-minute signed URLs (FR-4.8, MOB-06, NFR-image-storage, AT-07).
**Plans**: TBD
**UI hint**: yes

### Phase 3: Review, Delegation & Escalation
**Goal**: A technician verifies every extracted field and submits an immutable revision, and a different person approves or rejects that exact revision, with delegation to a trusted technician, 24-hour escalation to the EA, notifications and an audit view (Sprint 4, ends Tue Nov 17, 2026; contract Slice 3 "Workflow + review", endpoints 3.1-3.22; SPEC-PX-08 and the SPEC-PX-07 S4 part to be written and passed at G1).
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: FR-5.1, FR-5.2, FR-5.3, FR-5.4, FR-5.5, FR-5.6, FR-5.7, FR-5.8, FR-6.3, REQ-07.05, REQ-07.06, AT-02, AT-08, AT-09, AT-10, AT-11, EA-03, EA-04, BU-03, BU-04, MOB-05, MOB-07, REQ-override-authority-v1, REQ-override-authority-v2, REQ-audit-access-v1, REQ-audit-access-v2
**Blocked (do not build until the decision is recorded)**: EA-03, BU-03, MOB-07 decision screens (P-11 effective-decision rule); override-authority pair (P-6); REQ-07.06 and audit-access pair (owner decision, no PRD or O-number yet). Partially gated: FR-5.4 (P-11, P-6, O-21), FR-5.6, BU-04 and AT-10 (O-18), EA-04 (audit-access).
**Success Criteria** (what must be TRUE):
  1. A technician opens My Scans (Needs action / In progress / Approved), marks each field accepted, corrected, unreadable (with reason) or left empty, and submits; the revision is immutable, unknown confidence is never shown as high, and Submit Anyway lists the empty required fields, cannot be approved, and can be rejected for rework (FR-5.1 to FR-5.3, MOB-05, AT-08).
  2. A BU Admin, EA or assigned trusted technician approves or rejects another person's exact revision; a decision on one's own scan is refused; when two reviewers act at once exactly one decision is current and the other gets 409; a rejection returns the scan with its category and the fix is a new rejection_fix revision (FR-5.4, FR-5.5, BU-03, MOB-07, AT-09).
  3. A BU Admin or EA delegates a batch of 1-50 scans to one trusted technician with that technician's own captures excluded, and can remind, reassign or take back; a reassigned reviewer can no longer decide the old item (FR-5.6, FR-5.7, BU-04, AT-10).
  4. A scan unapproved after 24 hours, or in a unit with no BU Admin, escalates to the EA, who can send a reminder; the first decision retires the escalation without deleting history; the bell panel and email carry the 17 notification kinds with no push (FR-5.8, FR-6.3, EA-03, EA-04, AT-11).
  5. On real devices, a capture made offline stays in the encrypted queue when the user or unit changes before sync and cannot sync into the wrong context without explicit reauthorisation or repair (AT-02).
**Plans**: TBD
**UI hint**: yes

### Phase 4: Exports, Quota, Retention & Data Security
**Goal**: Admins export scoped CSVs safely, usage is counted per unit per month, retention is enforced daily, and encryption controls are in place (Sprint 5, ends Tue Dec 01, 2026; contract Slice 4 export endpoints 4.1-4.2 plus quota and retention config; SPEC-PX-11 and the SPEC-PX-09 hardening part to be written and passed at G1; the contract slice title "Portal + integration" is stale, there is no portal in V1).
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: FR-6.4, FR-6.5, FR-6.6, NFR-encryption, NFR-export, AT-01, AT-13, AT-14, AT-16, BU-05
**Blocked (do not build until the decision is recorded)**: FR-6.5 quota ceiling and HTTP 402 refusal (P-9 / O-7). Partially gated: FR-6.4, NFR-export and AT-13 (O-14 DLP result storage; audit_log export kind follows the audit-access pair), FR-6.6 (O-8, P-2, P-8), AT-16 (P-2), BU-05 (P-9 / O-7), AT-01 (P-9 / O-7), NFR-encryption (environment procurement).
**Success Criteria** (what must be TRUE):
  1. An EA or BU Admin exports scans (and the EA audit_log, subject to the audit-access decision) as CSV limited to their authorised units: up to 1,000 rows return immediately; a 1,001-row export is queued, written to MinIO, announced by an export_ready alert, downloadable for 1 hour only by the requester, and audited (FR-6.4, NFR-export, AT-14).
  2. A download of restricted or out-of-scope CSV rows or images is blocked by API projection, DLP scan and authorisation, and the attempt is logged (AT-13).
  3. A duplicate upload, including a timeout after a successful commit, yields one scan, one counted scan and the same acknowledgement on retry; a BU Admin sees monthly unit usage; at the limit the server refuses with HTTP 402 and an actionable message (FR-6.5, BU-05, AT-01).
  4. Retention is set per data class with a tenant default; a value below the floor is rejected with HTTP 400; the daily job purges per class, suppresses purge for legally held evidence, keeps the audit floor, and audits every purge (FR-6.6, AT-16).
  5. Data is AES-256 encrypted at rest in PostgreSQL and MinIO with Vault-managed MinIO keys, and transport is TLS 1.3 only with HSTS of at least one year, with evidence recorded (NFR-encryption).
**Plans**: TBD
**UI hint**: yes

### Phase 5: Release Gate
**Goal**: V1 is accepted: all 18 release tests pass with evidence and a named owner, measurable NFRs are met, residency and backup/DR commitments have deployment evidence, and the deployment gate and rollback are tested (Sprint 6, ends Tue Dec 15, 2026; gate G5, delivery lead).
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: GATE-G5, REQ-10.S6, NFR-performance, NFR-availability, NFR-scale, NFR-data-residency, NFR-compliance, NFR-backup, AT-17, AT-18
**Blocked (do not build until the decision is recorded)**: NFR-availability and NFR-backup (P-13 WAL-based backup for the 1-hour RPO); NFR-data-residency and AT-18 (P-14 OpenAI US endpoints + Zero Data Retention evidence). Partially gated: GATE-G5 and REQ-10.S6 (environment procurement, P-13, P-14), NFR-compliance (P-8).
**Success Criteria** (what must be TRUE):
  1. All 18 release tests AT-01 to AT-18 pass in representative environments, each with evidence and a named owner, and the security scan is clean (GATE-G5).
  2. Measured performance meets the targets: upload acknowledgement under 500 ms, background extraction under 15 s at p95, API responses within 20 s at p95 excluding extraction, mobile launch under 3 s on a mid-range Android, at the stated scale of 10 units, 10-20 users per unit and 1,000 scans per day per unit (NFR-performance, NFR-scale).
  3. No Client Portal surface, PortalReader entitlement or dependent migration exists, and no production client data appears in the India E2E database, MinIO, logs, backups or provider test payloads, with OpenAI US endpoints and Zero Data Retention evidenced (AT-17, AT-18, NFR-data-residency).
  4. The deployment gate blocks on any failed or skipped check, DAST has run on the US VPS, rollback is tested, and a restore test meets RTO of 4 hours or less and RPO of 1 hour or less using WAL-based or equivalent backup (REQ-10.S6, NFR-availability, NFR-backup, NFR-compliance).
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 (decimal insertions run between their integers)

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Identity, Tenancy & Isolation | 0/TBD | Not started | - |
| 2. Authoring & Capture-to-Extraction | 0/TBD | Not started | - |
| 3. Review, Delegation & Escalation | 0/TBD | Not started | - |
| 4. Exports, Quota, Retention & Data Security | 0/TBD | Not started | - |
| 5. Release Gate | 0/TBD | Not started | - |

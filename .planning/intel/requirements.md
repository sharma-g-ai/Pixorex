# Requirements (synthesized intel)

Source: docs/PRD.md (Pixorex PRD V3 - V1 Baselined, Oct 13, 2026). PRD declares its own internal precedence: 13 Oct addendum > V3 Data Models > V2.1 BRD body. Every FR below is declared "V1 must-have" by the PRD.

Field notes: `acceptance` is `absent` where the PRD gives no per-requirement acceptance statement; release tests AT-01 to AT-18 are listed separately below with their expected outcomes and are NOT mapped to FR ids here because the PRD does not map them. Spec-level GIVEN/WHEN/THEN criteria live in constraints.md.

Competing variants (PRD vs SPEC/contract) are at the end of this file under separate IDs; see INGEST-CONFLICTS.md warnings.

---

# 1. Tenancy, users and sign-in

## REQ-FR-1.1
- source: docs/PRD.md (Functional requirements 1)
- description: A tenant owns business units. Creating a unit seeds exactly one default business process (is_default = true); the UI has no process picker. Tables: tenant, business_unit, business_process. BRD trace: US-024, A.
- acceptance: absent
- scope: tenancy, business units

## REQ-FR-1.2
- source: docs/PRD.md (Functional requirements 1)
- description: Every tenant-owned row carries tenant_id; composite foreign keys keep rows inside one tenant. PostgreSQL RLS restricts rows to the tenant, then to the user's authorised unit, as defense in depth alongside API authorization. Tables: all tenant-owned tables. BRD trace: US-024, US-026, US-028.
- acceptance: absent
- scope: tenancy, RLS

## REQ-FR-1.3
- source: docs/PRD.md (Functional requirements 1)
- description: A user's role in a unit is one user_unit_role row: enterprise_admin (bu_id null), bu_admin or field_technician. One active BU Admin per unit; business_unit.bu_admin_user_id null means "No BU Admin". BRD trace: US-027, A.
- acceptance: absent
- scope: roles

## REQ-FR-1.4
- source: docs/PRD.md (Functional requirements 1)
- description: Invitations are single-use magic links that expire 24 hours after sending; only a token hash is stored. A multi-unit invite is one row per unit with the same hash. A technician confirms name and mobile number and verifies the number by texted code; a BU Admin verifies email by code. An expired invite raises an invite_expired notification. Tables: invite, app_user, notification. BRD trace: US-036, US-049, A.
- acceptance: absent
- scope: invites, activation

## REQ-FR-1.5
- source: docs/PRD.md (Functional requirements 1)
- description: Sign-in is by one-time code: technicians choose SMS or email, admins use email. Keycloak counts wrong codes per account across both channels; the 5th locks sign-in for 30 minutes with automatic unlock and an audit_log row (sign_in). Tables: Keycloak, audit_log. BRD trace: US-001, A.
- acceptance: absent
- scope: sign-in, lockout

## REQ-FR-1.6
- source: docs/PRD.md (Functional requirements 1)
- description: Each device session records the unit in use. Switching units needs no new sign-in and updates app_user.last_bu_id, which opens at next sign-in. Tables: user_session, app_user. BRD trace: US-004, US-030.
- acceptance: absent
- scope: sessions, unit switching

## REQ-FR-1.7
- source: docs/PRD.md (Functional requirements 1)
- description: Removing a user revokes all their sessions; changing a phone revokes the other devices. The API denies a revoked session within 60 seconds. Table: user_session. BRD trace: US-051, US-027.
- acceptance: absent
- scope: session revocation

## REQ-FR-1.8
- source: docs/PRD.md (Functional requirements 1)
- description: A phone number changes only after the code sent to the new number is verified. Five wrong codes lock changes for 30 minutes. The change signs out other devices, writes a users audit row and emails the user. Tables: app_user, user_session, audit_log. BRD trace: A.
- acceptance: absent
- scope: phone change

# 2. Locations

## REQ-FR-2.1
- source: docs/PRD.md (Functional requirements 2)
- description: The EA defines a unit's levels (for example Facility, Building, Shop, Bin, Sub-bin) as location_level_rule rows: name, order (1 = top) and required, optional or off. The top level is always required. BRD trace: US-025b, A.
- acceptance: absent
- scope: locations, level rules

## REQ-FR-2.2
- source: docs/PRD.md (Functional requirements 2)
- description: The EA builds the node tree: each location_node has a parent, a materialised path and a level; names are unique among siblings. Until publish the EA can add, rename, move or delete any node. BRD trace: US-034, A.
- acceptance: absent
- scope: locations, node tree

## REQ-FR-2.3
- source: docs/PRD.md (Functional requirements 2)
- description: Publishing sets location_hierarchy_version to published (version_no 1) and freezes the full tree as tree_snapshot. Afterwards levels and nodes are locked by trigger; post-publish edits are not V1. The publish screen first shows a preview and an irreversible-change warning. BRD trace: US-025, A.
- acceptance: absent
- scope: locations, publish freeze

## REQ-FR-2.4
- source: docs/PRD.md (Functional requirements 2)
- description: The mobile picker shows tenant.name as a read-only Customer header above the levels. Customer is not a level and not a selectable node. BRD trace: US-014, A.
- acceptance: absent
- scope: mobile location picker

## REQ-FR-2.5
- source: docs/PRD.md (Functional requirements 2)
- description: The phone caches tree_snapshot, shows only levels that are not off, enforces required levels, and offers the last-used location for one-tap confirm. A location that is no longer valid or authorised needs manual repair and is never silently replaced. BRD trace: US-014, US-015.
- acceptance: absent
- scope: mobile, offline cache

## REQ-FR-2.6
- source: docs/PRD.md (Functional requirements 2)
- description: Each scan stores its location_node_id and a location_path_snapshot taken at capture time, so its place is preserved as it was. Table: scan. BRD trace: US-014, US-025.
- acceptance: absent
- scope: scan location

# 3. Equipment types and extraction contracts

## REQ-FR-3.1
- source: docs/PRD.md (Functional requirements 3)
- description: A BU Admin creates an equipment type for their unit from blank, as a copy, or as an AI-assisted draft (created_via). Names are unique per unit. Only a not_published type can be renamed, edited or deleted. BRD trace: US-033, A.
- acceptance: absent
- scope: equipment types

## REQ-FR-3.2
- source: docs/PRD.md (Functional requirements 3)
- description: Until publish the BU Admin adds, edits, reorders and deletes fields: key, label, order, data type (text, number, date, dropdown, boolean), required and critical flags, format rule, unique-in-unit flag, and a review threshold that defaults to 0.85. A dropdown needs 2 or more choices. Table: field_definition. BRD trace: US-033, US-023.
- acceptance: absent
- scope: field definitions

## REQ-FR-3.3
- source: docs/PRD.md (Functional requirements 3)
- description: AI assistance proposes fields from reference images and marks them ai_suggested. A person reviews and edits them; AI never publishes a type. BRD trace: US-033b, A.
- acceptance: absent
- scope: AI-assisted type drafting

## REQ-FR-3.4
- source: docs/PRD.md (Functional requirements 3)
- description: Publishing freezes the type's single version (version_no 1, with publisher and time) and its fields, and creates an active extraction contract binding that version to one prompt version. A published type cannot be renamed, changed or deleted; something different needs a new type. BRD trace: US-033, US-018, A.
- acceptance: absent
- scope: type publish, extraction_contract

## REQ-FR-3.5
- source: docs/PRD.md (Functional requirements 3)
- description: Prompt versions are platform-owned, global and managed by Amzur; they are never edited after use and never hold client data. A new prompt version adds a new contract rather than silently changing an old one. A blocked contract stops new attempts. BRD trace: US-018, US-022.
- acceptance: absent
- scope: prompt_version

## REQ-FR-3.6
- source: docs/PRD.md (Functional requirements 3)
- description: The mobile type picker lists only published types of the active unit's default process. BRD trace: US-009.
- acceptance: absent
- scope: mobile type picker

## REQ-FR-3.7
- source: docs/PRD.md (Functional requirements 3)
- description: A dropdown extraction must match one of the choices or the field is flagged format_failed. A boolean is stored as true or false in values_json. Unique-in-unit compares a value with the unit's other scans of that type. BRD trace: US-022.
- acceptance: absent
- scope: field validation

# 4. Scans, photos and extraction

## REQ-FR-4.1
- source: docs/PRD.md (Functional requirements 4)
- description: The phone generates client_capture_id offline. It is unique per tenant, and a repeated upload, including a retry after a lost response, returns the existing scan. scan.bu_id is the unit active at capture. BRD trace: US-010, US-013, A.
- acceptance: absent
- scope: scan identity, idempotency

## REQ-FR-4.2
- source: docs/PRD.md (Functional requirements 4)
- description: A scan has 1-4 photos, numbered and unique per scan. Image bytes live in private MinIO at /{tenant}/{bu}/{scan}/{photo_no}; the database stores only the key and a SHA-256. Image-quality numbers stay on the phone. BRD trace: US-010, US-029.
- acceptance: absent
- scope: photos, MinIO

## REQ-FR-4.3
- source: docs/PRD.md (Functional requirements 4)
- description: An offline capture is held in the AES-256 encrypted local queue under its client_capture_id and syncs oldest-first when connectivity and the OS allow. Foreground reconciliation on app resume is the mandatory fallback. Failed or blocked items stay visible and are never silently deleted. BRD trace: US-016, US-017.
- acceptance: absent
- scope: offline queue

## REQ-FR-4.4
- source: docs/PRD.md (Functional requirements 4)
- description: A scan pins one extraction contract at creation. The pin changes only on a re-extract; a newer publish never upgrades it silently. BRD trace: US-018, US-022.
- acceptance: absent
- scope: extraction contract pinning

## REQ-FR-4.5
- source: docs/PRD.md (Functional requirements 4)
- description: Every AI call through the AI Inference Proxy is an extraction_attempt: attempt_no 1-3 per scan across all types, trigger first, retry or re-extract, status queued, running, succeeded, failed or timed out, with the contract used and tokens and cost for billing. After 3, only a retake is possible. BRD trace: US-018, US-018b, A.
- acceptance: absent
- scope: extraction attempts, attempt budget

## REQ-FR-4.6
- source: docs/PRD.md (Functional requirements 4)
- description: The mobile app holds no provider key. The Proxy builds the outbound request, strips PII and operational metadata, applies prompt-injection defenses and per-tenant rate limits, and reads secrets from Vault. BRD trace: US-018 to US-021, US-055.
- acceptance: absent
- scope: AI Inference Proxy

## REQ-FR-4.7
- source: docs/PRD.md (Functional requirements 4)
- description: AI answers are stored insert-only, one ai_field_value per field. Confidence is NULL when the model gives no score. Flag reasons are low_confidence, format_failed, no_confidence, missing_required and critical_not_found. BRD trace: US-022, US-023, A.
- acceptance: absent
- scope: ai_field_value

## REQ-FR-4.8
- source: docs/PRD.md (Functional requirements 4)
- description: An attempt records detected_label, suggested_type_id and suggestion_confidence. The app shows the Type mismatch screen, and a re-extract with another type happens only after the technician approves it. BRD trace: A.
- acceptance: absent
- scope: type mismatch

## REQ-FR-4.9
- source: docs/PRD.md (Functional requirements 4)
- description: Extraction targets under 15 seconds at p95 in the background. The technician receives an immediate acknowledgement and is never blocked waiting for extraction. BRD trace: US-011.
- acceptance: absent
- scope: extraction latency

# 5. Review, delegation and escalation

## REQ-FR-5.1
- source: docs/PRD.md (Functional requirements 5)
- description: Submit for Review creates an immutable revision holding the final values by field key. Only the scan's own technician can create one. Origin is technician_review or rejection_fix. BRD trace: US-012, US-012c, US-013.
- acceptance: absent
- scope: revisions

## REQ-FR-5.2
- source: docs/PRD.md (Functional requirements 5)
- description: The technician's verdict on each field is a revision_field: accepted, corrected, unreadable or left empty. Unreadable carries a reason (label worn, not on nameplate, covered or unreachable, other, plus a note). Each verdict links to the untouched AI value. BRD trace: US-012c.
- acceptance: absent
- scope: field verdicts

## REQ-FR-5.3
- source: docs/PRD.md (Functional requirements 5)
- description: Submit Anyway sends a revision with required fields still empty and lists them in empty_required_fields for the reviewer. In V1 such a revision cannot be approved; unresolved mandatory data must be rejected for rework, with no automatic or exception approval. BRD trace: US-031, A.
- acceptance: absent
- scope: Submit Anyway

## REQ-FR-5.4
- source: docs/PRD.md (Functional requirements 5)
- description: A decision approves or rejects one exact revision, as bu_admin, enterprise_admin or delegated_technician. The decider can never be the scan's technician (trigger). The first valid decision is current; an override inserts a new row linked to the one it overrides. A reject carries a category: image unclear, data correction needed, wrong equipment type or other. BRD trace: US-031, A.
- acceptance: absent
- scope: review decisions, override

## REQ-FR-5.5
- source: docs/PRD.md (Functional requirements 5)
- description: A rejected scan returns to its technician with the category shown. The fix is a new rejection_fix revision sent to the named reviewer; the rejected revision is preserved. BRD trace: US-013, US-012b.
- acceptance: absent
- scope: rejection rework

## REQ-FR-5.6
- source: docs/PRD.md (Functional requirements 5)
- description: A BU Admin or EA creates a review batch of 1-50 scans for one trusted technician. Scans that technician captured are left out. A batch is a set of review assignments, never bulk approval. BRD trace: US-032, A.
- acceptance: absent
- scope: delegation batches

## REQ-FR-5.7
- source: docs/PRD.md (Functional requirements 5)
- description: Reassign changes the assignee, closes the old assignment rows and writes an audit row. Take back may carry a message. Send reminder sets reminded_at. Alert timestamps stop repeat alerts. BRD trace: A.
- acceptance: absent
- scope: reassign, take back, remind

## REQ-FR-5.8
- source: docs/PRD.md (Functional requirements 5)
- description: A scheduled job creates an escalation (not_approved_24h or no_bu_admin) once a scan has waited 24 hours. The EA can send a reminder. The first decision resolves it; the BU Admin still sees the scan. BRD trace: A.
- acceptance: absent
- scope: escalation

# 6. Audit, notifications, exports, quota and retention

## REQ-FR-6.1
- source: docs/PRD.md (Functional requirements 6)
- description: The audit log is append-only and partitioned by month, with actor type user or system and categories sign_in, users, locations, equipment_types, review, override, escalation, export and retention. It is kept 1 year online and 3 years archived; this floor cannot be lowered. BRD trace: US-044, US-045, US-046.
- acceptance: absent
- scope: audit_log

## REQ-FR-6.2
- source: docs/PRD.md (Functional requirements 6)
- description: Work that must follow a commit (emails, texts, AI proxy calls, export builds) is written to outbox_event in the same transaction as the change and its audit row. A worker runs it with retry and backoff. BRD trace: US-044.
- acceptance: absent
- scope: outbox

## REQ-FR-6.3
- source: docs/PRD.md (Functional requirements 6)
- description: Notifications appear in the bell panel and by email, with no push. There are 17 kinds, listed in Domain 6 of the Data Models document. BRD trace: A.
- acceptance: absent
- scope: notifications

## REQ-FR-6.4
- source: docs/PRD.md (Functional requirements 6)
- description: A CSV export is a job for scans or audit_log, limited to the requester's authorised units. Up to 1,000 rows return in the request; above that the job is queued, the file is stored in MinIO, the link is valid for 1 hour and an export_ready alert is sent. Every job writes an audit row and passes a DLP scan before delivery. BRD trace: US-039, US-057.
- acceptance: absent
- scope: CSV export

## REQ-FR-6.5
- source: docs/PRD.md (Functional requirements 6)
- description: Quota usage is one row per unit per month and counts unique scans, separate from provider attempt cost. A scan is counted when the server accepts it, so a retry of the same capture never counts twice. At the limit the server refuses with HTTP 402 and an actionable message. Where the ceiling is stored is open item 9. The 80, 95 and 100 percent alert levels are tracked to avoid duplicates; the alert experience is post-V1. BRD trace: US-021, US-037, A.
- acceptance: absent
- scope: quota

## REQ-FR-6.6
- source: docs/PRD.md (Functional requirements 6)
- description: Retention is set per data class, with a tenant default (bu_id null) and a hard floor; the API rejects a value below the floor with HTTP 400. Defaults at provisioning: source images 30 days, AI attempts 90 days, approved records 7 years, revision history 7 years, user accounts 90 days after deactivation. A daily enforcement job applies these in V1, skips legally held records and audits every purge. BRD trace: US-046b.
- acceptance: absent
- scope: retention

---

# Permissions matrix (PRD)

## REQ-permissions-matrix
- source: docs/PRD.md (Permissions matrix)
- description: The server decides every operation from the user's role in the active unit. Operation: EA / BU Admin / Technician / Constraint. (a) Create unit, assign BU Admin: Yes / No / No / tenant scope, one active BU Admin per unit. (b) Build and publish location tree: Yes / No / No / EA only, before publish. (c) Create and publish equipment type: No unless separately authorised in the unit / Yes / No / BU Admin owns types. (d) Invite or disable a technician: Oversight only (open item 5) / Yes, own unit / No / no cross-unit revocation. (e) Capture, verify and submit own scan: only if assigned as technician / only if assigned as technician / Yes / revisions are creator-only; admin rights do not create capture ownership. (f) Decide own scan: No / No / No / no self-approval, enforced by trigger. (g) Decide another person's exact revision: Yes / Yes, own unit / only if trusted and assigned / current submission, resolved mandatory fields, first-decision guard. (h) Delegate a batch: Yes / Yes, own unit / No / 1-50 scans authored by others. (i) Override a decision: Yes / Unresolved (open item 6) / No / appends a linked decision row. (j) Read or export scans and audit: Yes within authority / Yes, own unit / No / DLP, strict row scope, audit event.
- acceptance: absent
- scope: authorization

---

# Non-functional requirements and system obligations (PRD)

All carry over from BRD v2.1; they need implementation evidence before they count as met.

## REQ-NFR-performance
- source: docs/PRD.md (NFRs)
- description: API responses within 20 s at p95 excluding AI extraction. Acknowledgement of a submitted scan under 500 ms. Background extraction under 15 s at p95. Mobile launch under 3 s on a mid-range Android. (BRD: NFR, US-011)
- acceptance: absent
- scope: performance

## REQ-NFR-availability
- source: docs/PRD.md (NFRs)
- description: 99.9% uptime, planned maintenance off-peak only. RTO 4 hours or less, RPO 1 hour or less. (BRD: NFR, US-061)
- acceptance: absent
- scope: availability

## REQ-NFR-scale
- source: docs/PRD.md (NFRs)
- description: 10 units per client, 10-20 users per unit, 1,000 scans per day per unit.
- acceptance: absent
- scope: scale

## REQ-NFR-encryption
- source: docs/PRD.md (NFRs)
- description: AES-256 at rest in PostgreSQL and MinIO, with Vault-managed keys for MinIO. TLS 1.3 only in transit, HSTS of at least 1 year. (US-053, US-054)
- acceptance: absent
- scope: encryption

## REQ-NFR-secrets
- source: docs/PRD.md (NFRs)
- description: All secrets loaded from HashiCorp Vault at container start, never from environment variables or config files. Secret-scan gates block any commit containing credentials. (US-055, US-064)
- acceptance: absent
- scope: secrets

## REQ-NFR-image-storage
- source: docs/PRD.md (NFRs)
- description: MinIO is private. Images are served only by object-specific presigned URLs valid 15 minutes, issued after a current authorization check; none is issued after revocation. (US-029, US-056)
- acceptance: absent
- scope: image access

## REQ-NFR-access-control
- source: docs/PRD.md (NFRs)
- description: Every API call validates the Keycloak token, session freshness, action permission, tenant and unit scope. A role or scope change or a removal takes effect within 60 seconds. (US-004, US-028, US-051)
- acceptance: absent
- scope: access control

## REQ-NFR-mobile-security
- source: docs/PRD.md (NFRs)
- description: Root and jailbreak detection blocks the scan workflow. TLS certificate pinning. All local data encrypted with AES-256 using a hardware-backed key. (US-007, US-008, US-017)
- acceptance: absent
- scope: mobile security

## REQ-NFR-mobile-platform
- source: docs/PRD.md (NFRs)
- description: iOS 16+ and Android 10+ (API 29+). Offline-first capture; background sync where the OS permits, with foreground reconciliation as the mandatory fallback. Human verification and submission are never automated. No tablet-native layout. (NFR, US-016, US-017b-d)
- acceptance: absent
- scope: mobile platform

## REQ-NFR-data-residency
- source: docs/PRD.md (NFRs)
- description: All real client data stays on US infrastructure. The India E2E environment holds synthetic data only. OpenAI calls use US endpoints with Zero Data Retention; this needs deployment evidence (open item 14). (NFR, US-059)
- acceptance: absent
- scope: residency

## REQ-NFR-ai-privacy
- source: docs/PRD.md (NFRs)
- description: PII and operational metadata are stripped before any image is sent to the provider, and logs record only which categories were stripped. (US-019)
- acceptance: absent
- scope: AI privacy

## REQ-NFR-compliance
- source: docs/PRD.md (NFRs)
- description: Audit log kept 1 year online and 3 years archived. Breach notification to designated PPG contacts within 24 hours. SOC 2 readiness documents available for review. (US-046, US-048, NFR)
- acceptance: absent
- scope: compliance

## REQ-NFR-export
- source: docs/PRD.md (NFRs)
- description: CSV only. Exports up to 1,000 records are immediate; larger exports are background jobs with a 1-hour download link. All exports pass a DLP scan. (US-039, US-057)
- acceptance: absent
- scope: export

## REQ-NFR-backup
- source: docs/PRD.md (NFRs)
- description: Daily encrypted PostgreSQL snapshots retained 7 days. MinIO object versioning on all buckets. Monthly restore test against the 4-hour RTO (should have). Daily snapshots alone cannot meet the 1-hour RPO; a WAL-based or equivalent design is needed (open item 13). (US-058, US-060, US-061)
- acceptance: absent
- scope: backup, DR

## REQ-NFR-delivery-pipeline
- source: docs/PRD.md (NFRs)
- description: Two reviewer approvals per PR, SAST and dependency scanning, container scanning, DAST on the US VPS, and a deployment gate that blocks on any failed or skipped check. (US-062 to US-067)
- acceptance: absent
- scope: CI/CD

---

# Release tests (PRD) - acceptance criteria for V1 acceptance

V1 is accepted when all 18 tests pass in representative environments and each security or compliance commitment has deployment evidence and a named owner.

## REQ-release-test-AT-01
- source: docs/PRD.md (Release tests)
- description: Duplicate uploads, including a timeout after a successful commit.
- acceptance: One scan per tenant and client_capture_id, one counted scan, same ACK on retry.
- scope: idempotency, quota

## REQ-release-test-AT-02
- source: docs/PRD.md (Release tests)
- description: Capture offline, then switch user or unit before sync.
- acceptance: Encrypted queue stays isolated and cannot sync into the wrong context; explicit reauthorisation or repair.
- scope: offline queue

## REQ-release-test-AT-03
- source: docs/PRD.md (Release tests)
- description: Unverified phone, or 5 wrong codes.
- acceptance: Activation blocked; 30-minute lock, then automatic unlock.
- scope: sign-in, lockout

## REQ-release-test-AT-04
- source: docs/PRD.md (Release tests)
- description: Publish locations, then try to rename, move or add.
- acceptance: Server refuses; the frozen snapshot stays.
- scope: locations freeze

## REQ-release-test-AT-05
- source: docs/PRD.md (Release tests)
- description: Publish a type, then try to edit or rename a field.
- acceptance: Server refuses; a copy can be created and published separately.
- scope: equipment type freeze

## REQ-release-test-AT-06
- source: docs/PRD.md (Release tests)
- description: No provider confidence, invalid dropdown value, missing mandatory field.
- acceptance: NULL confidence, explicit format and required flags, no silent pass.
- scope: extraction flags

## REQ-release-test-AT-07
- source: docs/PRD.md (Release tests)
- description: Mismatch plus two failures use all 3 attempts.
- acceptance: Attempt 4 blocked; retake creates a linked new scan; no hidden scan on retry.
- scope: attempt budget

## REQ-release-test-AT-08
- source: docs/PRD.md (Release tests)
- description: Submit Anyway with a mandatory field empty.
- acceptance: Revision accepted for review with the gap shown; approval blocked; reject and rework available.
- scope: Submit Anyway

## REQ-release-test-AT-09
- source: docs/PRD.md (Release tests)
- description: Two reviewers act on one revision at once.
- acceptance: Exactly one current decision; the other gets 409; override is a separate action.
- scope: first-decision race

## REQ-release-test-AT-10
- source: docs/PRD.md (Release tests)
- description: Batch assigned to a trusted technician who captured some of the scans.
- acceptance: Own scans excluded, up to 50 others assigned; a reassigned reviewer cannot decide the old item.
- scope: delegation

## REQ-release-test-AT-11
- source: docs/PRD.md (Release tests)
- description: Scan unapproved at 24 hours, or unit with no BU Admin.
- acceptance: EA escalation and notification; a decision retires the escalation without deleting history.
- scope: escalation

## REQ-release-test-AT-12
- source: docs/PRD.md (Release tests)
- description: Admin removed from one unit but kept in another.
- acceptance: Session change applies within 60 seconds; the other unit stays authorised; no new signed image URLs for the removed scope.
- scope: access removal

## REQ-release-test-AT-13
- source: docs/PRD.md (Release tests)
- description: Download of restricted or out-of-scope CSV or images.
- acceptance: Blocked by API projection, DLP and authorisation; attempts logged.
- scope: export security

## REQ-release-test-AT-14
- source: docs/PRD.md (Release tests)
- description: Export of 1,001 rows.
- acceptance: Async file in MinIO, export_ready alert, 1-hour link, scoped download, audit history.
- scope: async export

## REQ-release-test-AT-15
- source: docs/PRD.md (Release tests)
- description: Outbox worker retries after an email or provider timeout.
- acceptance: Correlated intent and outcome, safe at-least-once reconciliation, no duplicate scan or review rows.
- scope: outbox

## REQ-release-test-AT-16
- source: docs/PRD.md (Release tests)
- description: Legally held evidence reaches its retention date.
- acceptance: Purge suppressed; audit floor kept; job behaviour observable.
- scope: retention

## REQ-release-test-AT-17
- source: docs/PRD.md (Release tests)
- description: Attempt to reach a Client Portal or create a PortalReader.
- acceptance: No such surface or entitlement exists; no migration or API depends on missing tables.
- scope: out-of-V1 portal

## REQ-release-test-AT-18
- source: docs/PRD.md (Release tests)
- description: US hosting versus India E2E data boundary.
- acceptance: No production client data in India E2E database, MinIO, logs, backups or provider test payloads.
- scope: data residency

---

# Screens (PRD) - 16 screens, no portal route, no process selector

## REQ-screen-EA-01
- source: docs/PRD.md (Screens)
- description: Units overview, create, edit. Unit name and status, BU Admin or vacant, user and scan counts, recent escalation; create unit, assign or revoke admin.
- acceptance: Critical constraint: no cross-tenant assignment; warn on vacancy; other unit roles stay intact.
- scope: Enterprise Admin dashboard

## REQ-screen-EA-02
- source: docs/PRD.md (Screens)
- description: Locations setup. Customer read-only header, level rules, nodes, hierarchy preview, publish confirmation.
- acceptance: Critical constraint: no reopening after publish (read-only snapshot); block invalid parent, cycle and duplicate sibling.
- scope: Enterprise Admin dashboard

## REQ-screen-EA-03
- source: docs/PRD.md (Screens)
- description: Scans and escalations. Authorised units only, 24-hour and no-admin escalations, scan detail, remind, decide.
- acceptance: Critical constraint: decided or expired escalation not actionable; losing a first-decision race returns a conflict.
- scope: Enterprise Admin dashboard

## REQ-screen-EA-04
- source: docs/PRD.md (Screens)
- description: Audit, export, alerts. Category, time and unit filters, append-only event view, CSV export, notification bell.
- acceptance: Critical constraint: exports recheck scope and DLP; no portal access.
- scope: Enterprise Admin dashboard

## REQ-screen-BU-01
- source: docs/PRD.md (Screens)
- description: Staff and invites. Users, unit role, verified phone, status, pending and expired invites, primary and trusted flags.
- acceptance: Critical constraint: one active BU Admin; no revoking another unit; expired invite must be recreated.
- scope: BU Admin dashboard

## REQ-screen-BU-02
- source: docs/PRD.md (Screens)
- description: Equipment type builder. Type list, create blank, copy or AI assist, fields, required and critical flags, dropdown options, preview, publish.
- acceptance: Critical constraint: AI draft needs human validation; no edit of a published type or its fields.
- scope: BU Admin dashboard

## REQ-screen-BU-03
- source: docs/PRD.md (Screens)
- description: Review queue and decision. Submitted revision, photos, raw AI value, technician verdict, flags, missing fields, approve or reject.
- acceptance: Critical constraint: own scan cannot be approved; missing mandatory field blocks approval; a race shows 409 and current state.
- scope: BU Admin dashboard

## REQ-screen-BU-04
- source: docs/PRD.md (Screens)
- description: Delegation console. Trusted reviewer, eligible scans, batch of 1-50, progress, remind, reassign, take back.
- acceptance: Critical constraint: excludes the reviewer's own captures; stale assignments cannot decide.
- scope: BU Admin dashboard

## REQ-screen-BU-05
- source: docs/PRD.md (Screens)
- description: Usage and CSV. Monthly BU scan usage, scans and audit filters, exports.
- acceptance: Critical constraint: no process selector; no quota push notifications.
- scope: BU Admin dashboard

## REQ-screen-MOB-01
- source: docs/PRD.md (Screens)
- description: Activate and sign in. SMS or email choice for technicians, code challenge, phone verification, retry timer.
- acceptance: Critical constraint: expired, invalid and locked states explicit; no unlock approval.
- scope: Mobile app

## REQ-screen-MOB-02
- source: docs/PRD.md (Screens)
- description: Home and context. Unit switch, type list, last location, offline queue count, My Scans.
- acceptance: Critical constraint: no unassigned unit; no process picker.
- scope: Mobile app

## REQ-screen-MOB-03
- source: docs/PRD.md (Screens)
- description: Capture and preview. Camera with 1-4 photo count, quality retake or confirm, location breadcrumb.
- acceptance: Critical constraint: never transmit before confirmation; a retry creates no duplicate capture.
- scope: Mobile app

## REQ-screen-MOB-04
- source: docs/PRD.md (Screens)
- description: Offline queue. Queued count, upload and extraction status, retry, repair or discard where permitted.
- acceptance: Critical constraint: no silent deletion on retry exhaustion or age; local-only evidence may be lost after key loss.
- scope: Mobile app

## REQ-screen-MOB-05
- source: docs/PRD.md (Screens)
- description: My Scans and fields. Needs action, In progress and Approved tabs; photos with flagged fields; accepted, corrected, unreadable, left empty.
- acceptance: Critical constraint: unknown confidence never scored as high; submit needs an explicit action.
- scope: Mobile app

## REQ-screen-MOB-06
- source: docs/PRD.md (Screens)
- description: Type mismatch and retake. Detected label, suggested permitted type, remaining attempt budget, explicit re-extract or new retake.
- acceptance: Critical constraint: fourth attempt blocked; a physical retake creates a new linked scan.
- scope: Mobile app

## REQ-screen-MOB-07
- source: docs/PRD.md (Screens)
- description: Delegated review. Only the trusted reviewer's currently assigned reviews; raw value, result and revision; approve or reject.
- acceptance: Critical constraint: no own scan; stale assignment returns 409; approval rules still enforced.
- scope: Mobile app

---

# Competing variants (PRD vs SPEC / contract) - preserved, not merged

Each pair below is a divergence between the baselined PRD and a Draft SPEC or the API-contracts DOC. Neither variant is picked. See INGEST-CONFLICTS.md (WARNINGS) for resolution actions. Per CONSTITUTION §0, anything marked OPEN is not built until recorded in STATE.md.

## REQ-override-authority-v1
- source: docs/PRD.md (Permissions matrix row "Override a decision"; PRD open item 6)
- description: Override of a review decision: Enterprise Admin = Yes; BU Admin = unresolved (open item 6; implementation PRD allows "EA/admin" in one place and BU Admin "as V3 policy permits" in another); Technician = No. Appends a linked decision row.
- acceptance: absent
- scope: override authorization

## REQ-override-authority-v2
- source: docs/api-contracts.md (contract 3.7 POST /decisions/{decisionId}/override)
- description: Override endpoint "Who" = bu_admin only. Inserts a new decision with overrides_decision_id; the old one stops being current. Screens show only approval -> rejection. Alerts the delegated technician (decision_overridden). Audit (override). Enterprise Admin is not listed.
- acceptance: absent
- scope: override authorization

## REQ-invite-authority-v1
- source: docs/api-contracts.md (contract 1.8) and specs/SPEC-PX-01.md (REQ-01.10); also BRD US-036/US-049 as cited in PRD open item 5
- description: BU Admin invites technicians (only for units they run, else 403). Enterprise Admin invites BU Admins (only for units with no BU Admin, else 409 unit-has-bu-admin). The EA does not invite technicians.
- acceptance: SPEC-PX-01 REQ-01.10: GIVEN a BU Admin of unit X WHEN they invite a technician for X THEN one invite row per unit with same token_hash, expires_at = now + 24h, an outbox_event and an audit_log row (users) in one transaction; GIVEN a BU Admin WHEN they invite for a unit they do not run THEN 403; GIVEN an EA WHEN they invite a BU Admin for a unit that already has one THEN 409 unit-has-bu-admin.
- scope: invite authorization

## REQ-invite-authority-v2
- source: docs/PRD.md (PRD open item 5; Permissions matrix row "Invite or disable a technician")
- description: Open item 5 records that the Data Models screens show Invite BU Admin and Invite technician, BRD US-036/US-049 say the BU Admin invites, and the implementation PRD says both "EA or BU Admin" invite, giving the EA only oversight. The permissions matrix shows the EA cell for inviting or disabling a technician as "Oversight only (open item 5)". Owner decision pending.
- acceptance: absent
- scope: invite authorization

## REQ-audit-access-v1
- source: docs/PRD.md (Permissions matrix row "Read or export scans and audit"; REQ-screen-BU-05; FR-6.4; journey J08)
- description: BU Admin may read or export scans and audit within their own unit (matrix: Yes, own unit; BU-05 lists "scans and audit filters, exports"; FR-6.4 export_job for scans or audit_log limited to the requester's authorised units; J08 actors EA and BU Admin filter scans and audit within authorised scope).
- acceptance: absent
- scope: audit log read and export

## REQ-audit-access-v2
- source: specs/SPEC-PX-07.md (REQ-07.01) and docs/api-contracts.md (contracts 3.22 and 4.1)
- description: audit_log readable by EA only ("RLS: tenant-scoped; readable by EA only (enforced at the API in S4, by policy now)"); GET /audit-log Who = enterprise_admin only; POST /exports Who = bu_admin for scans of their unit and enterprise_admin for scans and audit_log (BU Admin cannot export audit_log).
- acceptance: absent
- scope: audit log read and export

## REQ-phone-change-codes-v1
- source: docs/api-contracts.md (contracts 1.4 and 1.5) and PRD FR-1.8
- description: Phone change is performed through API endpoints POST /me/phone-change ({new_phone_number}, 202 {expires_at}) and POST /me/phone-change/verify ({code}). On success: saves phone_number and phone_verified_at, revokes every other user_session, emails the user; 5 wrong codes lock phone changes 30 min; number already used -> 409 phone-in-use; Audit (users). Who sends and checks the code is OPEN O-12.
- acceptance: absent
- scope: phone change, code verification

## REQ-phone-change-codes-v2
- source: specs/SPEC-PX-01.md (decision O-12 proposed answer; REQ-01.12) and CONSTITUTION.md §2.7 / ARCHITECTURE.md §4.2
- description: Activation and phone-change codes are sent and checked by Keycloak via required actions using the same OTP authenticator and lock counter; a Keycloak event listener tells the API the verified value; "Endpoints 1.4-1.5 change accordingly". CONSTITUTION: the API has no sign-in, code or lockout endpoints. REQ-01.12 target behaviour: change saved only after the code sent to the new number is verified; 5 wrong codes lock phone changes for 30 minutes; success revokes every other session, emails the user, writes audit_log (users); number in use -> 409 phone-in-use. Status BLOCKED (O-12).
- acceptance: absent
- scope: phone change, code verification

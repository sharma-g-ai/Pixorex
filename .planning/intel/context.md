# Context (synthesized intel)

Running notes keyed by topic, with source attribution. DOC sources: docs/api-contracts.md, docs/design/README.md, contracts/README.md. Section "PRD supporting context" holds PRD content that is not a requirement entry (scope, roles, lifecycle, journeys, post-V1, open items).

Condensation note: docs/api-contracts.md is long; the endpoint catalog below keeps method, path, actor, and the rules text as written but drops the request/response column detail. Consult the source for full schemas.

---

# Topic: API contracts overview (docs/api-contracts.md)

- source: docs/api-contracts.md
- Title: "Pixorex V1 - API Contracts (Slices = Sprints 2-5)", Oct 13, 2026, @vishnu. 76 endpoints in 4 slices following Release Plan v2 Sprints 2 to 5. Sprint 1 (setup) and Sprint 6 (E2E gate) add no endpoints.
- Slices: Slice 1 Sprint 2 ends 20 Oct 2026 (Auth + RBAC: who you are, your units, invites, users); Slice 2 Sprint 3 ends 3 Nov 2026 (AI layer + schema: locations, equipment types, scan upload, extraction); Slice 3 Sprint 4 ends 17 Nov 2026 (Workflow + review: My Scans, self-review, decisions, delegation, escalation, alerts, audit); Slice 4 Sprint 5 ends 1 Dec 2026 (titled "Portal + integration": CSV export; Client Portal items are OPEN, see conflicts report).
- Sources in order: (1) Pixorex V3 data model (31 tables, 13 Oct); (2) UI screens of 13 Oct - Enterprise Admin (EA 01-73), BU Admin (BU 01-35), Technician app (T 01-80); (3) Release Plan v2 (only to place an endpoint in a sprint).
- Anything marked OPEN O-n is listed in its slice but must not be built until decided.
- OpenAPI 3.1 files (not present in repo): common.yaml, slice-s2-auth-rbac.yaml, slice-s3-capture-extraction.yaml, slice-s4-workflow-review.yaml, slice-s5-portal-export.yaml, README.md, .spectral.yaml. Each operation's description starts with "Contract ref n.n".

## Conventions (docs/api-contracts.md)
- source: docs/api-contracts.md
- Doc states "The team has no API conventions yet, so the rows below are standard defaults; change any row and the endpoints follow."
- Base URL https://<host>/api/v1. Paths kebab-case, path params camelCase (/business-units/{buId}/scans). JSON UTF-8, snake_case fields; AI-assist image uses multipart/form-data; photos are raw image/jpeg.
- Sign-in: apps sign in with Keycloak directly (manager decision, option 1); this API has no sign-in, code or lockout endpoints.
- Auth: Authorization: Bearer <Keycloak access token>; missing or expired -> 401. Only unauthenticated calls: invite-link calls 1.6-1.7 and /health, /ready.
- Tenant from the token, never URL or body; another tenant's row -> 404.
- Roles (x-roles): enterprise_admin, bu_admin, field_technician, or public. A technician with an active review assignment acts as delegated_technician for that scan only.
- Unit in the path as {buId}; caller must hold an active role in that unit else 403; EA passes for every unit of the tenant.
- Active unit: app sends X-Device-Id; API reads/writes user_session.active_bu_id for user + device. Release Plan puts it in the token (OPEN O-11).
- IDs UUID; display numbers record_no (REC-90141), batch_no (B-15). Dates UTC RFC 3339; date-only filters YYYY-MM-DD.
- Lists: ?limit= (default 25, max 100) and ?cursor=; response {"items": [...], "page": {"next_cursor": "..." or null}}.
- Errors: RFC 9457 application/problem+json {"type": "/problems/locked-after-publish", "title", "status", "detail", "correlation_id"}.
- Repeat-safe create: Idempotency-Key; same key + same body -> first result; same key + different body -> 409 idempotency-conflict; for scans key = client_capture_id.
- Concurrency: no If-Match/ETag (V3 tables have no row_version); wrong state -> 409.
- Status changes always actions (POST .../decisions, .../publish), never PATCH status.
- Changing a published location tree or equipment type -> 409 locked-after-publish.
- Every write marked Audit writes its audit_log row in the same transaction.
- Photos in MinIO; responses carry signed URLs valid 15 minutes; export link valid 1 hour.
- Per-endpoint labels: x-roles, x-brd (17 V3-only features have [none]), x-sprint, x-decision-pending (O-n); checked by .spectral.yaml.

## Endpoint catalog - Slice 1, Sprint 2: Auth + RBAC (19 endpoints)
- source: docs/api-contracts.md
- 1.1 GET /me (all roles): returns user, tenant {name}, units [{bu_id, name, role, is_primary, assigned_by_name}], active_bu_id, last_bu_id. Sets app_user.last_active_at. tenant.name is the read-only Customer header in the mobile picker.
- 1.2 PUT /me/active-unit (all roles) {bu_id}: caller must hold an active role in bu_id (403). Updates user_session.active_bu_id and app_user.last_bu_id. No new sign-in.
- 1.3 POST /me/sign-out (all roles) -> 204: sets user_session.revoked_at for this device; app also ends the Keycloak session. Audit (sign_in).
- 1.4 POST /me/phone-change (field_technician) {new_phone_number E.164} -> 202 {expires_at}: who sends/checks the code OPEN O-12; number in use -> 409 phone-in-use.
- 1.5 POST /me/phone-change/verify (field_technician) {code}: OPEN O-12. On success saves phone_number, phone_verified_at; revokes every other user_session; emails user; 5 wrong codes lock phone changes 30 min. Audit (users).
- 1.6 POST /invites/preview (holder of link) {token in body}: returns role, email, units, invited_by_name, expires_at. Expired/used/cancelled -> 409 invite-expired / invite-used / invite-cancelled.
- 1.7 POST /invites/accept (holder of link) {token, full_name, phone_number for technicians}: -> 201 {user_id, next_step: verify_phone | verify_email}. Single use. Creates or re-activates app_user and one user_unit_role per invite row. Primary unit / multi-invite: OPEN O-23. Code: OPEN O-12. Technicians never get dashboard access. Audit (users).
- 1.8 POST /invites (bu_admin for role field_technician; enterprise_admin for role bu_admin) {role, email, bu_ids[]}: one invite row per unit, same token_hash, expires_at = now + 24 h. BU Admin: only units they run (403). EA: only units with no BU Admin, else 409 unit-has-bu-admin. Email via outbox_event. Audit (users).
- 1.9 GET /invites (bu_admin, enterprise_admin): BU Admin sees technician invites of their units; EA sees BU Admin invites; rows past expires_at show expired.
- 1.10 POST /invites/{inviteId}/resend: pending or expired only; new token, new 24 h; old link stops. Audit (users).
- 1.11 POST /invites/{inviteId}/cancel -> 204: status cancelled; "Remove" on an expired invite uses this too. Audit (users).
- 1.12 GET /business-units (enterprise_admin, bu_admin) ?no_bu_admin=true: EA every unit; BU Admin only units they run.
- 1.13 POST /business-units (enterprise_admin) {name, facility_name, bu_admin: {invite_email} or {user_id}}: creates business_unit, default business_process (is_default = true), location_hierarchy_version (not_published). user_id must be an existing BU Admin; invite_email runs 1.8. Audit (users).
- 1.14 GET /business-units/{buId} (enterprise_admin).
- 1.15 GET /bu-admins (enterprise_admin).
- 1.16 PUT /bu-admins/{userId}/business-units (enterprise_admin) {bu_ids[]}: unit run by someone else -> 409 unit-has-bu-admin; adding a unit with a pending BU Admin invite cancels that invite; sets business_unit.bu_admin_user_id. Audit (users).
- 1.17 POST /bu-admins/{userId}/remove (enterprise_admin) {bu_ids[], replacement_invite_email optional} -> 204: sets user_unit_role.removed_at; units get bu_admin_user_id = null; account and history kept; all units removed -> every session revoked. Audit (users).
- 1.18 GET /business-units/{buId}/technicians (bu_admin): includes sign_in_locked_until; lock state lives in Keycloak (OPEN O-13).
- 1.19 POST /business-units/{buId}/technicians/{userId}/remove (bu_admin) -> 204: sets removed_at; revokes sessions for that unit (within 60 s, US-051); open review_assignment rows removed with user_removed. Audit (users).
- Release Plan items in Sprint 2 not covered by V3 or screens: 6 roles (O-1), SAML login and MFA for admins (O-2), role change endpoint (O-16), who sets is_trusted_reviewer (O-18). Session timeout and JWT lifetime are Keycloak settings.

## Endpoint catalog - Slice 2, Sprint 3: AI layer + schema (27 endpoints)
- source: docs/api-contracts.md
- 2.1 GET /business-units/{buId}/locations (enterprise_admin).
- 2.2 PUT /business-units/{buId}/locations/levels {levels[]}: replaces whole list; order = position; top level always required (400); published -> 409 locked-after-publish. Audit (locations).
- 2.3 POST /business-units/{buId}/locations/skeleton: one placeholder node per level; tree not empty -> 409. Audit (locations).
- 2.4 POST /business-units/{buId}/locations/nodes {parent_id, level_id, names[] 1-50}: duplicate sibling name -> 409 duplicate-name; published -> 409. Audit (locations).
- 2.5 PATCH /location-nodes/{nodeId} {name} or {parent_id}: move only to a parent at the same level as the old parent (400 wrong-level); published -> 409. Audit (locations).
- 2.6 DELETE /location-nodes/{nodeId} -> 204: deletes node and everything inside; published -> 409; Restore on deleted rows OPEN O-19. Audit (locations).
- 2.7 GET /business-units/{buId}/locations/publish-check.
- 2.8 POST /business-units/{buId}/locations/publish: 409 publish-checks-failed while placeholders are left; saves tree_snapshot, published_by, published_at; already published -> 409. Audit (locations).
- 2.9 GET /business-units/{buId}/locations/published (technician of unit, admins): phone caches it; not published -> 404 locations-not-published.
- 2.10 GET /business-units/{buId}/equipment-types (bu_admin; technician gets published only).
- 2.11 POST /business-units/{buId}/equipment-types {name, created_via blank|copy|ai_assist, copied_from_type_id, fields[]}: creates equipment_type (not_published) and equipment_type_version (version_no 1); duplicate name -> 409. Audit (equipment_types).
- 2.12 GET /equipment-types/{typeId}.
- 2.13 PATCH /equipment-types/{typeId} {name}: published -> 409 locked-after-publish. Audit (equipment_types).
- 2.14 DELETE /equipment-types/{typeId}: published -> 409. Audit (equipment_types).
- 2.15 POST /equipment-types/{typeId}/fields: field_key made by server from label; dropdown needs 2+ options (400); flag_below_confidence 0-1 default 0.85; published -> 409. Audit (equipment_types).
- 2.16 PATCH /equipment-types/{typeId}/fields/{fieldId}.
- 2.17 DELETE /equipment-types/{typeId}/fields/{fieldId}: published -> 409. Audit.
- 2.18 PUT /equipment-types/{typeId}/field-order: must list every field once (400); published -> 409.
- 2.19 POST /equipment-types/{typeId}/publish: needs 1+ field (409 no-fields); creates extraction_contract with current prompt_version. Audit (equipment_types).
- 2.20 POST /business-units/{buId}/equipment-types/ai-suggest (multipart image, name): calls AI proxy; nothing saved; photo/cost retention OPEN O-15.
- 2.21 POST /business-units/{buId}/scans (field_technician) {client_capture_id, equipment_type_id, location_node_id, photo_count 1-4, captured_at, retake_of_scan_id}: Idempotency-Key = client_capture_id; 201 {scan_id, record_no, processing_status: uploading}; same id again -> 200 same scan. Pins the type's active contract; saves location_path_snapshot; retake original must be caller's and becomes closed.
- 2.22 PUT /scans/{scanId}/photos/{photoNo} (own scan): image/jpeg, Content-Digest SHA-256 (RFC 9530); over 2 MB (Release Plan S2), digest mismatch or not JPEG -> 400. Upload route OPEN O-17.
- 2.23 POST /scans/{scanId}/upload-complete -> 202 {processing_status: extracting}: all photos present else 409 photos-missing; creates attempt 1 (trigger first) and an outbox_event; answers within 500 ms.
- 2.24 GET /scans/{scanId} (own technician, unit admins, assigned reviewer): photos with 15-min URLs, attempts_used, latest_attempt, fields with ai_value, confidence, flag_reasons.
- 2.25 POST /scans/{scanId}/retry-extraction: only when failed; 3 attempts used -> 409 scan-attempts-used.
- 2.26 POST /scans/{scanId}/re-extract {equipment_type_id}: type mismatch path; 3 attempts used -> 409; trigger re_extract.
- 2.27 POST /scans/{scanId}/discard -> 204: only before submit for review (409 otherwise); review_status = discarded.
- Release Plan items in Sprint 3 not covered: location depth 1-6 (O-5), editing a published type, clone and deactivate (O-4), effect of proxy refusals (injection 400, quota 402, rate limit 429) on the 3 attempts (O-20).

## Endpoint catalog - Slice 3, Sprint 4: Workflow + review (26 endpoints; 3.27 is a job, not an endpoint)
- source: docs/api-contracts.md
- 3.1 GET /me/scans (field_technician): tabs Needs action = ready_to_review, rejected, failed, retake_required; In progress = uploading, extracting, waiting_for_approval; Approved = approved. Phone-only offline queue is not in this list.
- 3.2 POST /scans/{scanId}/revisions (own technician) {fields[{field_key, verification_state accepted|corrected|unreadable|left_empty, value, unreadable_reason, note}], submit_anyway}: scan must be ready_to_review (draft) or rejected; every flagged field needs a verdict else 409 flags-not-reviewed; required field empty without submit_anyway -> 409 required-fields-empty; after a rejection origin = rejection_fix, resubmit_to_user_id = rejecter. Audit (review).
- 3.3 GET /business-units/{buId}/review-queue (bu_admin, enterprise_admin): counts waiting, over_1d, over_1w, delegated, decided_by_technicians.
- 3.4 GET /scans/{scanId}/review (bu_admin, enterprise_admin, assigned technician): scan's own technician gets 403.
- 3.5 POST /scans/{scanId}/decisions (bu_admin, enterprise_admin, assigned technician) {decision approved|rejected, reject_category, note}: own scan -> 403 own-scan (also DB trigger); already decided -> 409 already-decided; reject needs reject_category (image_unclear, data_correction_needed, wrong_equipment_type, other); whether reject note is required OPEN O-21; resolves an open escalation; admin deciding a delegated scan removes its assignment (admin_decided) and alerts technician (scan_removed_from_batch); alerts technician (scan_approved / scan_rejected). Audit (review).
- 3.6 GET /business-units/{buId}/technician-decisions (bu_admin).
- 3.7 POST /decisions/{decisionId}/override (bu_admin only per this doc) {decision, reject_category, note}: inserts a new decision with overrides_decision_id; screens show only approval -> rejection; alerts delegated technician (decision_overridden). Audit (override). (See conflicts report: PRD lists EA = Yes.)
- 3.8 GET /business-units/{buId}/delegates (bu_admin, enterprise_admin): who may be picked (is_trusted_reviewer) OPEN O-18.
- 3.9 POST /business-units/{buId}/review-batches {assigned_to, scan_ids[] 1-50}: scans must wait for approval and have no open assignment (409 already-assigned); technician's own scans excluded (reason own_scan); alerts batch_delegated; EA delegating also alerts BU Admin (ea_delegated_in_unit). Audit (review).
- 3.10 GET /business-units/{buId}/review-batches ?status=active|completed|taken_back.
- 3.11 GET /review-batches/{batchId}.
- 3.12 POST /review-batches/{batchId}/reassign {assigned_to}: closes open assignments (reassigned), opens new; alerts batch_reassigned. Audit (review).
- 3.13 POST /review-batches/{batchId}/take-back {message optional} -> 204: open assignments removed (taken_back); saves take_back_message; alerts batch_taken_back. Audit (review).
- 3.14 POST /review-batches/{batchId}/remind: sets reminded_at; alerts batch_reminder.
- 3.15 GET /me/review-batches (field_technician).
- Batches with no progress after 1 day or 1 week alert the creator (batch_no_progress) from a scheduled job (alert_1d_at, alert_1w_at); no endpoint.
- 3.16 GET /escalations (enterprise_admin): scheduled job creates escalations at 24 h; no create endpoint.
- 3.17 POST /business-units/{buId}/escalations/remind (enterprise_admin): sets reminded_at, alerts BU Admin (escalation_reminder); unit has no BU Admin -> 409 no-bu-admin. Audit (escalation).
- 3.18 GET /scans (enterprise_admin): all units of the tenant.
- 3.19 GET /me/notifications (all roles): 17 kinds (V3); bell panel and email; no push.
- 3.20 POST /me/notifications/{notificationId}/read -> 204. 3.21 POST /me/notifications/read-all -> 204.
- 3.22 GET /audit-log (enterprise_admin only per this doc): read only; categories sign_in, users, locations, equipment_types, review, override, escalation, export, retention. (See conflicts report: PRD lists BU Admin own-unit read.)
- 3.23 GET /business-units/{buId}/quota and 3.24 PUT /business-units/{buId}/quota (bu_admin, enterprise_admin; OPEN O-7): V3 stores scans_used per unit per month but has no limit column. Screens: none.
- 3.25 GET /retention-config and 3.26 PUT /retention-config (enterprise_admin; OPEN O-8): below the floor -> 400 below-retention-floor; Release Plan says Super Admin only. Audit (retention). Screens: none.
- 3.27 Quota alerts at 80, 95, 100% (system scheduled job; alert_level_sent stops repeats; depends on O-7). (See conflicts report: PRD says quota alerts are not part of V1.)
- Release Plan items in Sprint 4 not covered: status names (O-3), reviewer editing values (O-9), technician My Scans on the web dashboard (O-10).

## Endpoint catalog - Slice 4, Sprint 5: Portal + integration (4 endpoints)
- source: docs/api-contracts.md
- 4.1 POST /exports (bu_admin: scans of their unit; enterprise_admin: scans and audit_log) {export_kind scans|audit_log, filters, options}: up to 1,000 rows -> 200 text/csv; over 1,000 -> 202 {export_id, status: queued}; large exports build in background, file to MinIO, requester gets export_ready; every export writes an Audit row (export); DLP scan before file/link is given OPEN O-14.
- 4.2 GET /exports/{exportId} (requester): download_url valid 1 hour; after that 409 link-expired.
- 4.3 GET /health (public) -> {status: "ok"}. 4.4 GET /ready (public) -> {status ready|not_ready, checks {database, keycloak, minio, vault}}; 503 when not ready; no secrets or versions shown.
- Export download history UI is deferred to V1.1, so there is no list endpoint.
- Release Plan Sprint 5 items: Client Portal (approved records, search, filter, record detail, portal-only hidden fields, magic link + SAML login) not in V3 or screens, and the plan says the portal reads the database directly and bypasses the API - OPEN O-6; invite with magic link 24 h covered by 1.8-1.11 (Done in Slice 1 -> O-22); role change that invalidates the token - OPEN O-16; deactivate user with sessions ended within 1 min - covered by 1.17 and 1.19; CSV export - covered by 4.1-4.2; DLP scan on every export - OPEN O-14; breach notification pipeline - process and alerting, not an endpoint.

## Open decisions O-1 to O-23 (docs/api-contracts.md)
- source: docs/api-contracts.md
- Items 1-10 are Release Plan vs V3; 11-23 came up while writing endpoints. Format: question | one side | other side | endpoints | who decides.
- O-1 How many roles? Release Plan 6 roles (incl. Reviewer, Super Admin, portal user) vs V3 + screens 3 roles. All role checks. Manager / TA.
- O-2 How do admins log in? Release Plan SAML SSO + MFA vs screens email code, no password. None in API (Keycloak). Manager / TA.
- O-3 Scan status names. Release Plan: captured, extracting, ready_to_submit, in_review, approved, rejected vs V3: processing_status + review_status. 2.21-2.27, 3.1-3.5. Manager / TA.
- O-4 Can a published type change? Release Plan: edit makes new version; clone; deactivate vs V3 + screens: locked; copy only. 2.11-2.19. Manager / TA.
- O-5 Limit on location levels? Release Plan depth 1-6 vs V3 + screens no limit stated. 2.2. Manager / TA.
- O-6 Client Portal. Release Plan Sprint 5 portal, hidden fields, reads DB directly vs not in V3 or screens. Manager / TA.
- O-7 Scan quota limit. Release Plan limit per BU and per process, BU Admin screen vs V3 usage only, no limit column, no screen. 3.23-3.24, 3.27. Manager / TA, then data model.
- O-8 Who sets retention? Release Plan Super Admin at setup vs V3 table only, no role, no screen. 3.25-3.26. Manager / TA.
- O-9 Can the reviewer edit values? Release Plan yes vs V3 + screens approve or reject only. 3.5. Manager / TA.
- O-10 Technician My Scans on the web? Release Plan dashboard view too vs screens mobile only. 3.1. Manager / TA.
- O-11 Where does the active unit live? Release Plan in the token vs V3 user_session.active_bu_id. 1.2, every unit check. Manager / TA.
- O-12 Who sends and checks codes at activation and phone change? Option 1 Keycloak does sign-in codes vs V3 activation/phone change verify a code, 5 wrong = 30-min lock. 1.4-1.5, 1.7. Manager / TA.
- O-13 How does the API learn about Keycloak locks? Screens show "Sign-in locked" in list and audit row per lock vs V3 stores no lock state. 1.18, audit. Manager / TA.
- O-14 DLP scan on exports. Release Plan scan before link vs V3 export_job has no DLP result. 4.1-4.2. Manager / TA, then data model.
- O-15 AI-assist photo and cost. Screens suggest fields from a photo vs V3 no table for photo or AI cost. 2.20. Manager / TA.
- O-16 Role change. Release Plan role change ends token vs no screen, no V3 rule. New endpoint. Manager / TA.
- O-17 Photo upload route. This doc: through the API vs Release Plan signed MinIO URLs (15 min). 2.22. FSD-1 + TA.
- O-18 Who can receive delegated batches? V3 is_trusted_reviewer flag vs screens any technician of the unit; no screen sets the flag. 3.8-3.9. Manager / TA.
- O-19 Restore a deleted location. Screens Restore before publish vs V3 delete removes row. 2.6. Amrutha + you.
- O-20 Do proxy refusals use an attempt? Release Plan injection 400, quota 402, rate limit 429 vs V3 3 attempts per scan. 2.23, 2.25-2.26. Manager / TA.
- O-21 Is the reject note required? Screens a note box vs not stated. 3.5, 3.7. Amrutha + you.
- O-22 Invites in Sprint 2 or 5? Release Plan provisioning APIs in Sprint 5 vs Release Plan Sprint 2 FSD-2 user table uses them. 1.8-1.11. Manager / TA. (SPEC-PX-01 records this as settled: S2.)
- O-23 Activation with invites from 2 units. Screen T 03 lists Plant 04 and Plant 07 vs V3 one hash per invite; is_primary one per user, rule not stated. 1.7. You + Amrutha.

## Error codes (docs/api-contracts.md)
- source: docs/api-contracts.md
- 400 validation (all); wrong-level (2.4-2.5); digest-mismatch, photo-too-large (2.22); below-retention-floor (3.26). 401 Unauthorized (no/expired token, revoked session). 402 QuotaExceeded (2.21). 403 forbidden (all); own-scan (3.4-3.5). 404 not-found (all); locations-not-published (2.9). 409 idempotency-conflict; locked-after-publish (2.2-2.6, 2.8, 2.13-2.19); duplicate-name (1.13, 2.4-2.5, 2.11, 2.13, 2.15-2.16); tree-not-empty (2.3); publish-checks-failed (2.8); no-fields (2.19); type-not-published, location-not-published (2.21, 2.26); photos-missing (2.23); scan-attempts-used (2.25-2.26); flags-not-reviewed, required-fields-empty (3.2); already-decided (3.5); already-assigned (3.9); unit-has-bu-admin, not-a-bu-admin, no-bu-admin (1.8, 1.13, 1.16, 3.17); phone-in-use, code-invalid, phone-change-locked (1.4-1.5, 1.7); invite-expired, invite-used, invite-cancelled (1.6-1.7); link-expired (4.2); invalid-state (1.10-1.11, 2.21-2.27, 3.2, 3.5, 3.7, 3.12-3.14). 429 TooManyRequests: 100 requests per minute per tenant (2.20-2.21).

## Status moves the API allows (docs/api-contracts.md)
- source: docs/api-contracts.md
- processing_status: (phone) queued_on_phone -> uploading [2.21]; uploading -> extracting [2.23]; extracting -> ready_to_review or failed [AI proxy job]; failed -> extracting [2.25, attempts left]; failed (3 attempts used) -> retake_required [AI proxy job]; ready_to_review -> extracting [2.26, attempts left].
- review_status: draft -> waiting_for_approval [3.2]; draft -> discarded [2.27]; waiting_for_approval -> approved or rejected [3.5]; approved -> rejected [3.7 override]; rejected -> waiting_for_approval [3.2 fix and resubmit]; rejected, or draft with retake_required -> closed [2.21 with retake_of_scan_id].

---

# Topic: Design canvases (docs/design/README.md)

- source: docs/design/README.md
- Declared "Source of truth for screens and UI behaviour (CONSTITUTION §0)". Screen numbers in specs and contracts (EA nn, BU nn, T nn) refer to these canvases.
- Links: Enterprise Admin prototype https://claude.ai/artifact/UhadGWCbeurJSfb5RNSv3b ; BU Admin prototype https://claude.ai/artifact/JytmkLLCrDZsPg6a5DAunb ; Field Technician app prototype https://claude.ai/artifact/FQdpCPvPzp4sGhuAi1H8dt ; Full design canvas (all screens) https://claude.ai/artifact/4VGjxk93z3Q6wKifeJYj2B
- PRD screen IDs: EA-01-04, BU-01-05, MOB-01-07 (docs/PRD.md, Screens). Mapping between canvas numbering (EA 01-73, BU 01-35, T 01-80) and PRD IDs is not given in any source.

# Topic: Contracts folder (contracts/README.md)

- source: contracts/README.md
- "Action needed: drop the contract files here before the first API PR": common.yaml, slice-s2-auth-rbac.yaml, slice-s3-capture-extraction.yaml, slice-s4-workflow-review.yaml, slice-s5-portal-export.yaml, .spectral.yaml. None are present in the repo at ingest time.
- Readable version is docs/api-contracts.md. Each operation's description starts with "Contract ref n.n", which specs and tasks cite.
- Rules: changing an endpoint means changing the contract in the same PR. Spectral lint runs on every PR that touches this folder. Nothing marked x-decision-pending is built until its decision is in STATE.md.

---

# PRD supporting context (docs/PRD.md)

## Topic: PRD precedence and exclusions
- source: docs/PRD.md (Purpose and precedence)
- Pixorex PRD V3 - V1 Baselined, Oct 13, 2026. Derived from the frozen V3 logical data model (31 tables, 6 domains) and the owner's 13 Oct 2026 addendum to the BRD. Source documents: Pixorex_BRD_v2.1 (incl. "V3 V1 Owner-Approved Scope and Model Alignment Addendum", 13 Oct 2026) at https://docs.google.com/document/d/1W4UGpmCxTGTQSGMOeX30qY6RALwT_4k4XZ07pPp1fnE/edit ; Pixorex V3 - Data Models (13 Oct 2026, @vishnu) at https://docs.google.com/document/d/1lRZFwczFVEezkif5LOlWW4xI3-7onePz2EX9l339J4o/edit ; implementation PRD Pixorex_PRD_V3_V1_Baselined.docx merged later on 13 Oct.
- Order of precedence when sources disagree: (1) the 13 Oct addendum (overrides incompatible V2.1 user-story text); (2) the V3 Data Models document for tables, columns, keys, triggers, status values; (3) the V2.1 BRD body for everything else (security, residency, NFRs, DevSecOps).
- This PRD does not: change the data model or add a 32nd table; certify readiness; restate columns; carry story-point estimates (V2.1 total 245 SP predates the addendum and must be rebaselined).

## Topic: V1 scope
- source: docs/PRD.md (V1 scope)
- In V1: three primary roles (EA, BU Admin, Field Technician; is_trusted_reviewer is a delegated capability, not a fourth role); Keycloak one-time-code sign-in (technicians SMS or email, admins email; no passwords); one hidden default Business Process per BU, no process picker; locations (EA defines levels and node tree per BU; publish freezes both); equipment types (BU Admin builds from blank, copy or AI-assisted draft; publish freezes single version and binds to a prompt version in an extraction contract); mobile capture of 1-4 photos, offline-first, phone-generated client_capture_id; AI extraction via the AI Inference Proxy, max 3 attempts per scan; technician verification recorded as immutable revisions incl. Submit Anyway; review (approve or reject one exact revision, delegated review batches of 1-50, override, 24-hour escalation to the EA); monthly unique-scan quota per BU, bell and email notifications, scoped CSV export of scans and audit log; non-schema obligations (append-only audit, outbox, retention floors, private MinIO, security controls, US residency).
- "Approved" means: an approved scan, its exact revision and its effective review decision together are the reviewed record. No separate GovernedRecord, Publication or Client Portal projection.

## Topic: Users and roles; account and session rules
- source: docs/PRD.md (Users and roles)
- Enterprise Admin (enterprise_admin, whole tenant, bu_id null): creates units, defines location levels and builds node tree, publishes a unit's locations, handles escalated scans, reads scans and audit log, exports CSV; limits: edits no unit's locations after publish, no aggregate cross-BU reporting.
- BU Admin (bu_admin, one unit, one active BU Admin per unit): creates and publishes equipment types, manages the unit's technicians, approves or rejects scans, delegates review batches to trusted technicians, reassigns, reminds, takes back batches; cannot edit a published equipment type.
- Field Technician (field_technician, one or more units): captures scans, verifies each field, submits revisions, reworks rejected scans; cannot decide own scans.
- Delegated reviewer (technician with is_trusted_reviewer): decides scans in a review batch assigned to them; only another person's exact submitted revision; scans they captured are left out.
- Account and session rules: app_user.status is invited, active or removed; email unique per tenant; technician must verify an E.164 phone number (unique) before activation, admins have none; each user has one is_primary unit; user_session.active_bu_id records the unit per device; removing a user or changing a technician's phone sets user_session.revoked_at and the API must deny a revoked session within 60 seconds; sign-in codes, wrong-code counting and lockout live in Keycloak; the 5th wrong code locks sign-in for 30 minutes, unlocks automatically, no one approves it; every lock writes an audit_log row (sign_in).

## Topic: Frozen data model and invariants
- source: docs/PRD.md (Frozen data model)
- 31 PostgreSQL tables in 6 domains (V3 logical model published 13 Oct 2026). Domains: 1 Tenancy, users and sign-in (7); 2 Locations (3); 3 Equipment types and extraction contracts (5); 4 Scans, photos and extraction (4); 5 Review, delegation and escalation (6); 6 Audit, notifications, exports, quota, retention (6). Table lists match ARCHITECTURE.md §5 (see decisions.md ARCH-10).
- Invariants: tenant_id/created_at/updated_at on every tenant-owned table; composite tenant FKs (tenant and global prompt_version are exceptions); insert-only ai_field_value, revision, audit_log (audit log partitioned by month, no UPDATE/DELETE role); triggers: location_node accepts no INSERT/UPDATE/DELETE once its unit is published, field_definition read-only once its type is published, review_decision.decided_by can never be the scan's technician; uniqueness: client_capture_id per tenant; (scan_id, attempt_no) with attempt_no 1-3; (scan_id, photo_no) with photo_no 1-4; one current review_decision per revision; one assigned review_assignment per scan; one active BU Admin per unit; one default business_process per unit; one extraction contract per (type_version_id, prompt_version_id); one quota_usage row per (bu_id, period_month); two independent scan statuses (a move not in the lifecycle is refused with HTTP 409); location_hierarchy_version and equipment_type_version hold version 1 only in V1.
- Proposed change control: no table added/removed/renamed and no column changes meaning for V1; indexes, partitions, seed data and DDL implementing the rules need no change request; anything else goes to the owner and the Technical Architect as a written change request before engineering starts.

## Topic: Lifecycles and end-to-end workflow
- source: docs/PRD.md (Lifecycles and core workflows)
- scan.processing_status values: queued_on_phone (phone only), uploading, extracting, ready_to_review, failed, retake_required. scan.review_status: draft, waiting_for_approval, approved, rejected, closed (replaced by a retake), discarded. My Scans tabs: Needs action = ready_to_review, rejected, failed, retake_required; In progress = queued_on_phone, uploading, extracting, waiting_for_approval; Approved = approved.
- Workflow: (1) Setup - units, locations, equipment types configured and published before first scan; users join by single-use magic-link invite (24 hours) and activate by verifying phone or email. (2) Capture - technician picks type and location, takes 1-4 photos, confirms quality preview; phone creates client_capture_id and queues locally; repeated upload returns the existing scan; scan records location node, location path snapshot, pinned contract. (3) Extraction - Proxy runs pinned contract, writes extraction_attempt plus one ai_field_value per field; at most 3 attempts in total; type mismatch may suggest another permitted type (technician approves explicitly); when exhausted scan is retake_required and needs a new linked physical retake which closes the original. (4) Verification - per-field verdict; Submit for Review creates an immutable revision; Submit Anyway sends it with required fields empty and lists them. (5) Review - BU Admin, EA or delegated trusted reviewer approves or rejects another person's exact revision; first valid decision wins; override appends a linked decision row; rejection carries a category and returns the scan to the technician; the fix is a new rejection_fix revision resubmitted to the named reviewer. (6) Delegation - BU Admin or EA assigns a review batch of 1-50 scans to one trusted technician; batch = set of review assignments, not bulk approval; reassign, remind, take back are rows and audit entries. (7) Escalation - scheduled job escalates a scan to the EA after 24 hours; reason no_bu_admin when its unit has no BU Admin, else not_approved_24h; first decision resolves it; BU Admin still sees the scan.
- The full transition diagram is in the Data Models document and is authoritative for which moves are legal (diagram not in the ingest set).

## Topic: Operational journeys J01-J08
- source: docs/PRD.md (Operational journeys)
- J01 Configure a BU (EA): create unit (default process seeded, BU Admin may be vacant); choose location levels, build nodes, preview, publish. Rule: publish screen shows explicit irreversible warning; mobile then fetches and caches the frozen tree.
- J02 Invite, sign in, switch unit (EA, BU Admin, technician): single-use hashed invite (24 h); technician verifies phone then signs in by SMS or email code; admin by email code; Home opens last authorised unit; switching changes active_bu_id without new login. Rule: five wrong codes lock sign-in for 30 minutes; access removal revokes sessions; a verified phone change signs out other devices.
- J03 Create and publish an equipment type (BU Admin): blank, copy, or reference image (AI suggests a draft only); configure fields, validate prompt and field policy, preview, publish. Rule: publish freezes version 1 and binds the prompt in extraction_contract; to change fields create a new type and select it deliberately.
- J04 Capture and offline acceptance (Technician): pick unit, published type and published location; 1-4 photos, retake or confirm; persist client_capture_id, checksums, location snapshot and contract together on the device. Rule: nothing transmitted before image confirmation; offline shows queued_on_phone with a count; on reconnect same identity retried and server returns an ACK without waiting for AI.
- J05 AI attempt, mismatch, retry, retake (Technician, system): attempt 1 runs the scan's contract; results become immutable ai_field_value rows; confidence NULL if unsupported; mismatch suggests another permitted type. Rule: retries and re-extracts share a budget of 3; when spent a new linked physical retake is the only path.
- J06 Technician review and submit: open stored photos and each AI field; mark accepted, corrected, unreadable (with reason) or left empty; submit writes a revision and revision_field rows. Rule: Submit Anyway lists missing required fields and never auto-approves; a rejected revision is kept, rework is a new revision.
- J07 Review, delegation, escalation (BU Admin, EA, trusted technician): reviewer sees exact revision, machine value and technician verdict; admin delegates a batch of 1-50 (own captures excluded); reassign and take back close old assignments; after 24 hours a scan escalates to the EA. Rule: first valid decision wins; override appends a linked decision row; mandatory fields must be resolved before approval, otherwise reject for rework.
- J08 Search, export, audit, retention (EA, BU Admin): filter scans and audit within authorised scope; CSV up to 1,000 rows immediate, above queued with 1-hour private link; daily retention job. Rule: every export DLP-checked and audited; audit row and outbox intent commit in the same transaction; signed image access separately authorised, 15-minute TTL.

## Topic: Build sequence and definition of done (PRD)
- source: docs/PRD.md (Release tests and build sequence)
- Build sequence: (1) Security and data foundation - identity and unit grants, session freshness, Keycloak codes, RLS and tenant-safe FKs, audit and outbox, private object storage. (2) Pre-capture authoring - EA location publish, BU Admin type and contract publish, all pre-publish warnings. (3) Mobile capture to result - image preview, offline reconciliation, stable scan identity, async AI, flags, mismatch, attempt cap. (4) Human decision loop - revisions and field verdicts, Submit Anyway, approval and rework, delegation, escalation, override. (5) Operational controls and release - scoped exports, notifications, retention, quota, audit and security gates, US residency, backup and WAL-based RPO, real-device testing.
- Definition of done: authenticated authorisation, bounded sync, immutable evidence, error recovery and real-device verification must work. Physical DDL, indexes, status preconditions and APIs are implementation deliverables constrained by the frozen model. The PRD is a product baseline: it does not claim code is built, RTO/RPO met, provider data retention verified or a production database audited. A feature needing a 32nd table, portal entitlement, a new reviewer role, a mutable published tree or version-two type editing is a post-V1 change request.

## Topic: Post-V1 items (nothing here is built or promised in V1)
- source: docs/PRD.md (Post-V1 items)
- Named by the 13 Oct addendum: Client Portal, PortalReader persona, client login, publication projection and portal CSV (UX-006, US-006, EP-06 incl. US-040 to US-043); Enterprise SAML as a product flow (US-002); additional dashboard roles beyond three, and process selection; post-publish changes to locations and equipment types, and location CSV import (US-035); batch approve and reject (US-032); asset master, on-device VLM inference, ERP or CMMS integration, advanced analytics; automated inactive-account detection and quota-alert experience (US-050, US-052).
- Already deferred in BRD v2.1: BU Admin self-service retention UI (US-038), JSON export, export download history, admin action logging (US-047). Phase 2: Tier 2 SaaS, OAuth 2.0 or OIDC mobile auth, in-app billing engine, multi-language support, full WCAG 2.1 AA audit, Helm and Kubernetes packaging, Azure Terraform modules.

## Topic: PRD open items 1-14 (fourteen open; none changes the frozen model; each needs an answer before the related requirement can be built)
- source: docs/PRD.md (Open items and decisions needed)
- 1 How a tenant and its first Enterprise Admin are created (invite covers BU Admins and technicians only; BRD mentions a Super Admin). FR-1.4 cannot start with an empty tenant. Decide: Owner, Technical Architect.
- 2 When the 30-day source-image clock starts, and what happens to export photo links after images are purged. Decide: Owner.
- 3 SMS provider for technician sign-in and phone verification (FR-1.4, FR-1.5, FR-1.8 depend on it; US residency and Vault storage apply). Decide: Technical Architect.
- 4 Whether admin email code satisfies the MFA requirement (US-003). Decide: Owner, Engineering.
- 5 Who may invite whom (Data Models screens show Invite BU Admin and Invite technician; BRD US-036/US-049 say BU Admin invites; implementation PRD says "EA or BU Admin" invites with EA oversight only). Determines the invite permission check and the EA cell in the permissions matrix. Decide: Owner.
- 6 Who may override a decision ("EA/admin" in one place, BU Admin "as V3 policy permits" in another). Decide: Owner.
- 7 The legal scan-transition matrix (exists only as a diagram in the Data Models document; API must refuse any other move with 409). Decide: Technical Architect.
- 8 How audit-log retention is held (1 year online / 3 years archived fixed by partition and archival, not by a retention_config row?). Decide: Technical Architect.
- 9 Where the per-unit monthly quota ceiling is stored (FR-6.5 needs a limit; BU-05 needs one to display). Decide: Technical Architect.
- 10 business_unit.bu_admin_user_id vs the bu_admin row in user_unit_role. Decide: Technical Architect.
- 11 A single rule for a scan's effective decision over revision and review_decision. Needed before BU-03, EA-03, MOB-07. Decide: Technical Architect.
- 12 Handling of ambiguous provider outcomes (timeout after call sent): retries and external idempotency key. Decide: Technical Architect.
- 13 Daily snapshots alone cannot meet the 1-hour RPO; WAL-based or equivalent DR needed. Decide: Technical Architect, DevOps.
- 14 Evidence for OpenAI US endpoints and Zero Data Retention (AT-18). Decide: Owner, Security.
- Settled by the implementation PRD: the daily retention enforcement job runs in V1 (FR-6.6, J08), overriding the V1.1 label on US-046c; quota alerts are not part of V1 (BU-05 has no quota push notifications; reaching the limit returns a policy error per FR-6.5; alert levels in quota_usage stay for later).
- ARCHITECTURE.md uses the labels P-n for these PRD items (P-1 = item 1, etc.).

## Topic: BRD v2.1 story disposition and term mapping
- source: docs/PRD.md (Appendix)
- Disposition (PRD's own reading, "should be confirmed with the owner"). EP-D Design: kept UX-001, UX-003, UX-005, UX-007, UX-008; changed UX-002, UX-004; out UX-006. EP-01 Authentication: kept US-004, US-005, US-007, US-008; changed US-001 (SMS or email code), US-003 (open item 4); out US-002 (SAML), US-006. EP-02 Mobile capture: kept US-012b, US-015, US-016, US-017, US-017b-d; changed US-009, US-010, US-011, US-012, US-012c, US-013, US-014. EP-03 AI Inference Proxy: kept US-018b, US-018c, US-019, US-020; changed US-018, US-021, US-022, US-023. EP-04 Tenancy and locations: kept US-024, US-028, US-029; changed US-025, US-025b, US-026, US-027. EP-05 Admin dashboard: kept US-037; changed US-030, US-031, US-033, US-033b, US-034, US-036, US-039; deferred (V1.1 or later) US-032, US-035, US-038. EP-06 Client Portal: out US-040 to US-043. EP-07 Audit and retention: kept US-044, US-046, US-046b, US-048; changed US-045, US-046c (runs in V1); deferred US-047. EP-08 Account management: kept US-049, US-051; deferred US-050, US-052. EP-09 Data security: kept US-053 to US-057. EP-10 Backup and resilience: kept US-058 to US-061. EP-11 DevSecOps: kept US-062 to US-067.
- Term mapping V2.1 -> V3: Capture/logical scan -> scan; ExtractionAttempt/ExtractionJob -> extraction_attempt; MachineResult/MachineFieldValue -> ai_field_value; SchemaVersion -> equipment_type_version; ExtractionContractVersion -> extraction_contract; LocationNode/LocationHierarchyVersion -> location_node/location_hierarchy_version; CaptureLocationSnapshot -> scan.location_path_snapshot; Revision/ReviewDecision -> revision/review_decision; TenantMembership with ScopeGrants -> user_unit_role (three roles, one unit each); GovernedRecord/Publication -> none in V1; last_login_at (US-050) -> app_user.last_active_at.

# Pixorex V1 API contracts (V3)

OpenAPI 3.1 contracts written **slice-wise**, one file per sprint outcome in **Release Plan v2**. The backend is a modular monolith (FastAPI); slices link to each other only by ID.

**Sources:** Pixorex V3 Data Models (31 tables, 13 Oct 2026), UI screens of 13 Oct 2026 (Enterprise Admin EA 01–73, BU Admin BU 01–35, Technician app T 01–80), Release Plan v2. The readable version with every rule is the doc **Pixorex V1 — API Contracts (Slices = Sprints 2–5)**; each operation's description gives its number there (for example "Contract ref 2.21").

Every endpoint carries `x-roles` (V3 roles), `x-brd` (stories) and `x-sprint`. Open points are marked `x-decision-pending` with their number (O-1 to O-23), not guessed.

## Files

| File | Sprint outcome (Release Plan v2) | Endpoints |
|---|---|---|
| `common.yaml` | Shared: auth, RFC 9457 errors, paging, Idempotency-Key, 3 roles; `/health` and `/ready` | 2 |
| `slice-s2-auth-rbac.yaml` | S2: me, unit switching, phone change, invites, business units, BU Admins, technicians | 19 |
| `slice-s3-capture-extraction.yaml` | S3: locations (set up, publish, lock), equipment types and fields, AI-assist, scan upload, extraction, re-extract | 27 |
| `slice-s4-workflow-review.yaml` | S4: My Scans, self-review, decisions, override, delegation batches, escalation, alerts, audit log, quota, retention | 26 |
| `slice-s5-portal-export.yaml` | S5: CSV export (Client Portal is open, O-6) | 2 |
| **Total** | | **76** |

S1 delivers these contracts. S6 is the E2E gate, so it adds no endpoints.

## End-to-end flow

1. **S2** `GET /me` → `PUT /me/active-unit`
2. **S3** `GET /business-units/{buId}/locations/published` + `GET /business-units/{buId}/equipment-types?status=published&include=fields` → `POST /business-units/{buId}/scans` → `PUT /scans/{scanId}/photos/{photoNo}` → `POST /scans/{scanId}/upload-complete` → `GET /scans/{scanId}`
3. **S4** `POST /scans/{scanId}/revisions` → `POST /scans/{scanId}/decisions` (reject → fix → resubmit, or retake as a new scan); optional `POST /business-units/{buId}/review-batches` to delegate
4. **S5** `POST /exports`

## Rules

1. Base path `/api/v1`. UUIDs, UTC times.
2. Sign-in is Keycloak, called by the apps directly (manager decision, option 1). No sign-in endpoints here.
3. Tenant from the token; unit from path or body, checked against `user_unit_role`.
4. Errors: RFC 9457 `application/problem+json`; the `type` URI is the error code (`/problems/locked-after-publish`).
5. Retries are safe: `Idempotency-Key` on creates. For scans it equals `client_capture_id`; same body returns the same scan, a different body returns 409.
6. No `If-Match` / ETag: V3 has no `row_version` column. Concurrency is handled by state checks (409). Adding `row_version` is a decision.
7. Published location trees and equipment types are locked: changes return 409.
8. Machine results (`extraction_attempt`, `ai_field_value`), revisions and decisions are insert-only.
9. Status changes are actions (`POST .../decisions`, `.../publish`), never `PATCH status`.
10. A scan gets at most 3 extraction attempts in total (first, retries, re-extracts).

## Tools

```bash
npx @stoplight/spectral-cli lint common.yaml slice-*.yaml             # style + x-roles / x-brd / problem+json
npx @stoplight/prism-cli mock slice-s3-capture-extraction.yaml        # mock server on :4010
npx @redocly/cli bundle slice-s3-capture-extraction.yaml -o s3.yaml   # one file for Postman / Swagger
```

Checked on 13 Oct 2026: Spectral 0 errors (only "unused component" warnings in `common.yaml`, as before); every file passes the OpenAPI 3.1 validator with cross-file `$ref`s resolved.

## BRD story mapping

`x-brd` reuses the story IDs from the earlier contract set wherever the same feature exists. The BRD itself was not re-read for this version.

17 operations exist only because of V3 and the 13 Oct screens and have `x-brd: [none]` plus `x-brd-note`. Please confirm or add their story IDs:

| Area | Operations |
|---|---|
| Session | `signOut`, `startPhoneChange`, `verifyPhoneChange` |
| Scans | `reExtract`, `discardScan` |
| Review | `listTechnicianDecisions`, `overrideDecision` |
| Delegation | `listDelegates`, `createReviewBatch`, `listReviewBatches`, `getReviewBatch`, `reassignReviewBatch`, `takeBackReviewBatch`, `remindReviewBatch`, `listMyReviewBatches` |
| Escalation | `listEscalations`, `remindBuAdmin` |

## Coverage: data model tables (31)

| Domain | Table | Endpoint slice |
|---|---|---|
| 1 | tenant | From the token (`tenant_name` in `GET /me`) |
| 1 | business_unit, business_process | S2 (default process created with the unit; no process endpoints in V3) |
| 1 | app_user, user_unit_role, invite, user_session | S2 |
| 2 | location_hierarchy_version, location_level_rule, location_node | S3 |
| 3 | equipment_type, equipment_type_version, field_definition | S3 |
| 3 | extraction_contract | S3 (created on publish, pinned by scans) |
| 3 | prompt_version | No API: Amzur-managed, internal |
| 4 | scan, scan_photo, extraction_attempt, ai_field_value | S3 |
| 5 | revision, revision_field, review_decision | S4 |
| 5 | review_batch, review_assignment, escalation | S4 |
| 6 | notification, audit_log (read), quota_usage, retention_config | S4 |
| 6 | export_job | S5 |
| 6 | outbox_event | No API: internal worker |

## Decision-pending

| # | Point | Where |
|---|---|---|
| O-1 | 6 roles (Release Plan) vs 3 (V3) | `x-roles` everywhere |
| O-2 | SAML + MFA for admins vs email code | Keycloak only |
| O-3 | Status names (Release Plan vs V3) | S3 `ProcessingStatus`, S4 `listMyScans` |
| O-4 | Edit / clone / deactivate a published type | S3 `createEquipmentType` |
| O-5 | Location depth limit 1–6 | S3 `setLocationLevels` |
| O-6 | Client Portal | S5 (no endpoints yet) |
| O-7 | Quota limit storage, per business process, screen | S4 `getQuota`, `setQuota` |
| O-8 | Who sets retention (Super Admin not in V3) | S4 `getRetentionConfig`, `setRetentionConfig` |
| O-9 | Reviewer editing values | S4 `decideScan` |
| O-10 | My Scans on the web dashboard | S4 `listMyScans` |
| O-11 | Active unit in the token or in `user_session` | S2 `setActiveUnit` |
| O-12 | Who sends and checks activation and phone-change codes | S2 `startPhoneChange`, `verifyPhoneChange`, `acceptInvite` |
| O-13 | How the API learns Keycloak lock state | S2 `listTechnicians` |
| O-14 | DLP result on exports | S5 `createExport` |
| O-15 | AI-assist photo and cost storage | S3 `suggestFields` |
| O-16 | Role change endpoint | Not written |
| O-17 | Photo upload through the API or signed URLs | S3 `uploadPhoto` |
| O-18 | Who can receive delegated batches (`is_trusted_reviewer`) | S4 `listDelegates` |
| O-19 | Restore a deleted location | S3 `deleteLocationNode` |
| O-20 | Do proxy refusals use one of the 3 attempts | S3 `retryExtraction` |
| O-21 | Is the reject / override note required | S4 `decideScan`, `overrideDecision` |
| O-22 | Invites in Sprint 2 or Sprint 5 | Put in S2 |
| O-23 | Primary unit and other pending invites at activation | S2 `acceptInvite` |

## Changes from the previous contract set (0.2.0)

| Area | 0.2.0 | This version (0.3.0) |
|---|---|---|
| Source | BRD v2.1 + Reconciled Data Model (Oct 7) | V3 Data Model (Oct 13) + 13 Oct screens |
| Roles | 6 grant codes, BU/Process scope grants | 3 roles in `user_unit_role` |
| Processes | Process endpoints and process assignments | One default process per unit, no endpoints |
| Equipment types | Draft versions, retire, process assignment | Not published → published (locked), copy, AI-assist |
| Locations | Draft changes, versions, 6 canonical levels | One tree per unit, edit until publish, then locked |
| Records | `governed_record`, withdraw, location repair | Removed (not in V3); review works on the scan |
| Added | — | Phone change, BU Admins, technicians, delegation batches, override, escalation |
| Concurrency | `If-Match` / ETag | Not used (no `row_version` in V3) |
| Removed | Legal hold, portal records, export download redirect | Not in V3 (portal = O-6) |

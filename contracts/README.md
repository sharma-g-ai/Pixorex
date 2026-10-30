# SeaStock MVP API contracts (PIX-58)

OpenAPI 3.1 contracts for **receiving, inventory and transactions**, the scope of Jira
**PIX-58** (SeaStock Sprint 3). Written in the same shape as the Pixorex V1 contracts.

**Sources:** BRD v1.3 (21 Oct 2026), SeaStock Data Models (18 tables, 30 Oct 2026), PIX-58.
The 8-screen web portal (`web/`) is the screen reference; tablet screens are named as in the
data model.

Every endpoint carries `x-roles`, `x-brd` (BRD v1.3 requirement IDs), `x-ticket` and `x-sprint`.
Open points are marked `x-decision-pending` (SD-1 to SD-10 below), not guessed.

## Files

| File | Covers | Endpoints |
|---|---|---|
| `common.yaml` | Shared: auth (portal users and tablets), RFC 9457 errors, paging, Idempotency-Key, shared types; `/health` | 1 |
| `tablet-sync.yaml` | Tablet upload: sync session, events (delivery note, consumption, baseline, adjustment), complete | 3 |
| `receiving.yaml` | Portal: delivery notes and their tally | 2 |
| `inventory.yaml` | Portal: stock roll-ups and one vessel's stock; tablet: own stock | 3 |
| `transactions.yaml` | Portal: history, consumption roll-up, stock adjustment, unrecognised scans, held sync events; tablet: own transactions | 9 |
| **Total** | | **18** |

## End-to-end flow (receive, use, sync, see it on the portal)

1. Tablet, offline: crew confirms a delivery note, scans cans out, makes corrections.
2. Tablet, online: `POST /tablet/sync-sessions` → `POST /tablet/sync-sessions/{id}/events`
   (one or more) → `POST /tablet/sync-sessions/{id}/complete`.
3. Server: each event is applied (posts ledger rows; unknown article numbers are held as
   unrecognised scans), duplicate, quarantined (held for an admin) or rejected. A succeeded
   session moves the vessel's last sync.
4. Portal: `GET /stock?group_by=…`, `GET /vessels/{id}/stock`, `GET /consumption`,
   `GET /transactions`, `GET /delivery-notes`; review with `GET /unrecognised-scans` →
   `POST /unrecognised-scans/{id}/match`, and `GET /quarantined-events` →
   `POST /quarantined-events/{id}/close`.
5. Tablet: `GET /tablet/stock` and `GET /tablet/transactions` refresh its offline copy.

## Rules

1. Base path `/api/v1`. UUIDs, UTC times, dates `YYYY-MM-DD`.
2. Two callers: portal users (`ppg_admin` sees every customer; `customer_admin` sees one
   customer) and tablets (`seastock_tablet`, bound to one vessel through its active assignment).
   Crew have no personal accounts; tablet rows name the tablet, never a person.
3. Scope comes from the caller, never the request. Another customer's vessel is 404; asking
   for another customer in a filter is 403.
4. Errors: RFC 9457 `application/problem+json`; the `type` URI is the error code.
5. Retries are safe: `Idempotency-Key` on portal creates; client-made IDs on every tablet
   upload (`client_sync_id`, `client_event_id`, `client_dn_id`, `client_txn_id`).
6. The stock ledger, delivery notes and their lines are insert-only. Corrections are new
   adjustments. Liters are a snapshot at posting.
7. Negative stock is allowed and surfaced (`GET /stock?group_by=vessel_article&negative_only=true`),
   never blocked.
8. Unknown article numbers are held as unrecognised scans, never rejected; only a PPG Admin
   matches them, onto an active article. No product-and-shade guessing (FR-02, deferred).
9. No region: roll-ups are vessel, customer and PPG level (BRD v1.3).
10. CSV export: list and roll-up endpoints return `text/csv` when asked with `Accept: text/csv`.

## Example payloads and mocks

Each endpoint has example requests and responses in the files. For a mock server so the
Flutter and portal work can start before the backend (PIX-58 AC11), the same tools as Pixorex
work on these files:

```bash
npx @stoplight/prism-cli mock contracts/tablet-sync.yaml     # mock server on :4010
npx @stoplight/spectral-cli lint contracts/*.yaml            # style checks
python contracts/check.py                                    # refs, labels, path params (no install)
```

`check.py` passes on all five files (30 Oct 2026). Prism and Spectral were not run here (not
installed); run them once before review.

## Coverage: data model tables (18)

| Domain | Table | Where |
|---|---|---|
| 1 | customer, vessel | Read through `VesselRef` / `CustomerRef`; maintenance is another story |
| 1 | app_user | Caller of portal endpoints; `recorded_by`, `matched_by`, `resolved_by` |
| 1 | invite | Not in PIX-58 (user administration) |
| 2 | device, vessel_device_assignment | Caller of tablet endpoints; `device` on rows; `active_device` on a vessel |
| 2 | device_enrolment_code | Not in PIX-58 (enrolment story) |
| 2 | sync_session | `tablet-sync.yaml` |
| 2 | quarantined_event | `tablet-sync.yaml` (outcome), `transactions.yaml` (review) |
| 3 | article | Read through `ArticleRef`; maintenance and bulk import (PIX-70) are other stories |
| 3 | label_schema_version, label_schema_field | Not in PIX-58 (label rules story) |
| 4 | delivery_note, delivery_note_line | `tablet-sync.yaml` (upload), `receiving.yaml` (read) |
| 5 | inventory_transaction | `tablet-sync.yaml` (upload), `transactions.yaml` |
| 5 | vessel_stock | `inventory.yaml` |
| 5 | unrecognised_scan | `tablet-sync.yaml` (held), `transactions.yaml` (review, match) |
| 6 | audit_log | Written by match, close and portal adjustment; reading it is another story |

## Not in PIX-58 (other stories)

Sign-in and tokens (SS-FND-US02); tablet enrolment and the device list; customers, vessels,
users and invites; master item list, label schema and the tablet's first-sync download; bulk
import of master items (PIX-70); reading the audit log. Nothing from Phase 2 (forecasting,
thresholds, ERP, stock-take).

## Decision-pending

| # | Point | Where |
|---|---|---|
| SD-1 | Tablet credential format and whether requests are also signed (SS-FND-US02); whether the vessel password stays | `common.yaml` `tabletBearer` |
| SD-2 | Who may adjust stock from the portal (data model allows PPG Admin and the vessel's Customer Admin) | `createPortalAdjustment` |
| SD-3 | Who closes held sync events (contract: PPG Admin only) | `closeQuarantinedEvent` |
| SD-4 | Baseline lock: are receipts and consumption before the baseline blocked or only warned | `uploadSyncEvents` |
| SD-5 | Sync endpoints here, or in their own story | `tablet-sync.yaml` |
| SD-6 | CSV through `Accept: text/csv`, or a separate export story | list and roll-up endpoints |
| SD-7 | Events per upload call (200 proposed) | `uploadSyncEvents` |
| SD-8 | Article number exactly 6 digits, to confirm against the PPG Excel (D-02) | `common.yaml` `ArticleNumber` |
| SD-9 | PPG Admin scope: all customers (delivery plan, data model) vs "customer specific" (BRD FR-22) | every portal endpoint |
| SD-10 | Customer Admins can see (not act on) their review items | `listUnrecognisedScans`, `listQuarantinedEvents` |

## Review

PIX-58 needs the contracts reviewed and agreed by the Backend Lead, the Flutter developers and
the portal developers before dependent work starts.

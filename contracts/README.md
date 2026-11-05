# SeaStock MVP API contracts

OpenAPI 3.1 contracts for the whole MVP: the tablet, and every screen of the web portal. The
first 18 endpoints were written for Jira **PIX-58**; the rest cover what the portal also needs, so
a backend can be built from these files alone. Written in the same shape as the Pixorex V1 contracts.

**Sources:** BRD v1.3 (21 Oct 2026), SeaStock Data Models V2 (16 tables, with the review of
2 Nov 2026), PIX-58. Where the BRD and V2 differ, V2 is followed.
The 8-screen web portal (`web/`) is the screen reference; tablet screens are named as in the
data model.

Every endpoint carries `x-roles`, `x-brd` (BRD v1.3 requirement IDs), `x-ticket` and `x-sprint`.
Open points are marked `x-decision-pending` (SD-1 to SD-20 below), not guessed. `x-sprint: To confirm`
means the sprint is not known yet.

## Files

| File | Covers | Endpoints |
|---|---|---|
| `common.yaml` | Shared: auth (portal users and tablets), RFC 9457 errors, paging, Idempotency-Key, imports, shared types; `/health` | 1 |
| `tablet-sync.yaml` | Tablet upload: sync session, events (delivery note, consumption, baseline, adjustment), complete | 3 |
| `receiving.yaml` | Portal: delivery notes and their tally | 2 |
| `inventory.yaml` | Portal: stock roll-ups and one vessel's stock; tablet: own stock | 3 |
| `transactions.yaml` | Portal: history, consumption roll-up, stock adjustment, unrecognised scans, held sync events; tablet: own transactions | 9 |
| `identity.yaml` | Portal: the signed-in user, users and invites | 6 |
| `customers-vessels.yaml` | Portal: customers, vessels, Excel imports, vessel password reset | 10 |
| `devices.yaml` | Portal: tablet list, enrolment codes, prepare to retire, retire now, revoke; tablet: enrolment | 8 |
| `articles.yaml` | Portal: master item list and bulk load; tablet: download | 4 |
| `audit.yaml` | Portal: audit log | 1 |
| **Total** | | **47** |

## End-to-end flow (receive, use, sync, see it on the portal)

0. Setup: an admin issues an enrolment code (`POST /vessels/{id}/enrolment-codes`); the tablet checks
   it (`POST /tablet/enrolment/check`), the crew confirms the vessel, and it enrols
   (`POST /tablet/enrolment`), then downloads the master list (`GET /tablet/articles`).
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
   matches them, onto any article in the master list. No product-and-shade guessing (FR-02, deferred).
9. No region: roll-ups are vessel, customer and PPG level (BRD v1.3).
10. CSV export: list and roll-up endpoints return `text/csv` when asked with `Accept: text/csv`.
11. The master list only grows: articles are never retired or deleted. The label schema is
    deferred past the pilot, so it has no endpoints.
12. A vessel has one active tablet, and a tablet is enrolled once. A new tablet enrols only after
    the old one has retired or been revoked; there is no replacing at enrolment.
13. Customer and vessel imports are all-or-nothing. A vessel's IMO and customer cannot change.
14. An enrolment code is shown once, when issued; only its hash is stored.

## Example payloads and mocks

Each endpoint has example requests and responses in the files. For a mock server so the
Flutter and portal work can start before the backend (PIX-58 AC11), the same tools as Pixorex
work on these files:

```bash
npx @stoplight/prism-cli mock contracts/tablet-sync.yaml     # mock server on :4010
npx @stoplight/spectral-cli lint contracts/*.yaml            # style checks
python contracts/check.py                                    # refs, labels, path params (needs PyYAML)
```

On 5 Nov 2026 `check.py` passed on all ten files, Spectral (`spectral:oas`) gave 0 errors, and Prism
mock servers answered 25 requests as expected, including refusing a change to a vessel's customer or
IMO. Spectral's "unused component" warnings are about parts of `common.yaml` used from other files.
The import columns are provisional until the PPG Excel files are in hand (SD-8).

## Coverage: data model tables (16)

| Domain | Table | Where |
|---|---|---|
| 1 | customer, vessel | `customers-vessels.yaml` |
| 1 | app_user, invite | `identity.yaml` |
| 2 | device, device_enrolment_code, vessel_device_assignment | `devices.yaml` |
| 2 | sync_session | `tablet-sync.yaml` |
| 2 | quarantined_event | `tablet-sync.yaml` (outcome), `transactions.yaml` (review) |
| 3 | article | `articles.yaml` |
| 4 | delivery_note, delivery_note_line | `tablet-sync.yaml` (upload), `receiving.yaml` (read) |
| 5 | inventory_transaction | `tablet-sync.yaml` (upload), `transactions.yaml` |
| 5 | vessel_stock | `inventory.yaml` |
| 5 | unrecognised_scan | `tablet-sync.yaml` (held), `transactions.yaml` (review, match) |
| 6 | audit_log | `audit.yaml` (read); written by the other endpoints |

## Not covered

Signing in itself (the identity provider does that). Nothing from Phase 2 (forecasting, thresholds,
ERP, stock-take). Waiting for an answer, so left out: SD-11, SD-12 and SD-13.

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
| SD-11 | Accepting an invite and setting a password: Keycloak's screen or our own. Not in the contracts yet | `identity.yaml` |
| SD-12 | Importing users from Excel: the delivery plan expects it, the data model has none. Not in the contracts yet | `identity.yaml` |
| SD-13 | Editing an article, and which fields. Not in the contracts yet | `articles.yaml` |
| SD-14 | Invite period (7 days proposed) | `inviteUser` |
| SD-15 | Vessel password rule (12 characters proposed) and who hands it to the crew | `recordVesselPasswordReset` |
| SD-16 | Master item import: load the good rows or refuse the file; whether an existing article is updated | `importArticles` |
| SD-17 | What a Customer Admin may do in user admin and see in the audit log | `inviteUser`, `listAuditLog` |
| SD-18 | Whether a tablet retired at once may still upload if it comes online later (today it is refused) | `retireDevice` |
| SD-19 | A wrong IMO on a delivery note: accepted and flagged today; the review proposed stopping it | `listDeliveryNotes` |
| SD-20 | An unlisted tablet model: warn or block | `enrolDevice` |

## Review

The contracts need to be reviewed and agreed by the Backend Lead, the Flutter developers and
the portal developers before dependent work starts.

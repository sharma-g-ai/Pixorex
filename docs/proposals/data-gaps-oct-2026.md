# Dashboard data gaps: changes to the data model and API contracts

16 Oct 2026 · Vishnu

The EA and BU Admin dashboards (built from the 13 Oct canvas) showed 7 things the API contracts did not return. Four were already in the V3 data model and only needed the contracts. Three needed a data model change first. This note lists every change and every place it was made.

## Summary

| # | What the screen shows | Data model | API contract | Screens |
|---|---|---|---|---|
| 1 | Escalated scan: equipment type and "Captured by" | Already there (scan) | 3.16 `equipment_type_name`, `captured_by_name` | EA 04, 25, 29–31 |
| 2 | Scans: "Reviewed by", batch, why it is with the EA | Already there (review_decision, review_assignment, escalation) | 3.18 `reviewed_by`, `assignment`, `escalation_reason` | EA 20, 38–50 |
| 3 | Scans: search box | Already there (scan, field values) | 3.18 `q` filter | EA 20 |
| 4 | BU Home: "approved this week" | Already there (review_decision.decided_at) | 3.3 `counts.approved_this_week` | BU 03 |
| 5 | Audit log: "What happened" as a sentence | **New column** `audit_log.summary` | 3.22 `summary` | EA 22, 51–66 |
| 6 | Notification: second line, and "also emailed" only when it was | **New column** `notification.body`; `emailed_at` already there | 3.19 `body`, `emailed_at` | EA 24, BU 04 |
| 7 | Export: the "Include" choices | Allowed keys of `export_job.options_json.columns` defined | 4.1 `options.columns` enum | EA 21, BU 12 |

Items 1–4 are contract S4 v0.3.1. Items 5–6 are S4 v0.3.2; item 7 is S5 v0.3.1.

## Changes 5–7 in detail

### 5. Audit log summary

- **Data model:** `audit_log.summary text NOT NULL`. The API writes one readable sentence when it inserts the row, for example "Removed S. Alvi from Plant 07 (still runs Plant 09)". It is frozen like the rest of the row, so a later rename does not change history. `action` stays as the machine code, `details` as the JSON.
- **Contract 3.22:** each entry gains `summary` (string, required).
- **Export:** audit CSVs include `summary`.
- **Screen:** "What happened" shows `summary` instead of the raw `action`.

### 6. Notification body and email flag

- **Data model:** `notification.body text` (nullable), the grey second line, for example "Plant 07 · 12, Plant 11 · 9 · review or delegate". The API writes it with the title. `emailed_at` already exists.
- **Contract 3.19:** each notification gains `body` (string or null) and `emailed_at` (time or null).
- **Screen:** the bell panel shows `body` under the title and "also emailed" only when `emailed_at` is set (before this, it was shown on every alert).

### 7. Export column keys

- **Data model:** `export_job.options_json.columns` holds keys from this list; no table change.
- **Contract 4.1:** `options.columns` items are an enum. Scans exports always include record number, unit, location, equipment type, captured by, captured at and review status; the keys add:
  - `field_values`: one column per field with the value sent for approval.
  - `ai_vs_technician`: the AI value and its confidence next to each field value.
  - `review_decision`: decision, reject category, decided by, decided at.
  - Photo links stay the separate `include_photo_links` flag (links valid 1 hour).
- Audit log exports ignore `columns` and always contain when, who, unit, category, summary, action and object.
- **Screen:** the Export dialog sends these keys, now typed from the contract instead of placeholders.

## Places changed

| Place | Items |
|---|---|
| Google Doc "Pixorex V3 — Data Models", Domain 6 table | 5, 6, 7 |
| `api/migrations/baseline/06_domain6_audit_ops.sql` and `verify_baseline.sql` | 5, 6 |
| Google Doc "Pixorex V1 — API Contracts" | 1–7 |
| `docs/api-contracts.md` (repo copy of the contract doc) | 1–7 |
| `contracts/slice-s4-workflow-review.yaml` (v0.3.2) | 1–6 |
| `contracts/slice-s5-portal-export.yaml` (v0.3.1) | 7 |
| `contracts/README.md` change list | 1–7 |
| `web/src/api/generated/*` (regenerated) and the dashboard screens and tests | 1–7 |

## Not changed

- The Domain 6 diagram (an image) in the data model doc still shows the old columns. It needs redrawing by hand.
- `action` codes and the shape of `details` per action are still not listed anywhere; `summary` makes them unnecessary for the screens.

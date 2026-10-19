# API contracts (OpenAPI 3.1), v0.3.0 (S5 at v0.3.1; S2, S4 at v0.3.2)

The interface between `web/`, `mobile/` and `api/`. The readable version is `docs/api-contracts.md`; each operation's description starts with "Contract ref n.n", which specs and tasks cite.

| File | Slice / sprint | Endpoints |
|---|---|---|
| `common.yaml` | Shared: auth, RFC 9457 errors, paging, Idempotency-Key, roles; `/health`, `/ready` | 2 |
| `slice-s2-auth-rbac.yaml` | S2: me, unit switching, phone change, invites, business units, BU Admins, technicians | 19 |
| `slice-s3-capture-extraction.yaml` | S3: locations, equipment types and fields, AI-assist, scan upload, extraction | 27 |
| `slice-s4-workflow-review.yaml` | S4: My Scans, self-review, decisions, override, delegation, escalation, alerts, audit, quota, retention | 26 |
| `slice-s5-portal-export.yaml` | S5: CSV export | 2 |
| `.spectral.yaml` | Lint rules: `x-roles`, `x-brd`, `x-sprint`, problem+json | — |

Sources: Pixorex V3 Data Models (13 Oct 2026), UI screens of 13 Oct 2026 (EA 01–73, BU 01–35, T 01–80), Release Plan v2.

## Rules

- Changing an endpoint means changing the contract in the same PR.
- Spectral lint runs on every PR that touches this folder. Baseline: 0 errors; the 14 `oas3-unused-component` warnings in `common.yaml` are known.
- Nothing marked `x-decision-pending` is built until its decision is in `STATE.md` → *Decisions*.

## Tools

```bash
npx @stoplight/spectral-cli lint common.yaml slice-*.yaml           # lint
npx @stoplight/prism-cli mock slice-s2-auth-rbac.yaml               # mock server on :4010
npx @redocly/cli bundle slice-s2-auth-rbac.yaml -o s2.yaml          # one file for Postman / Swagger
```

## Changes

- **S4 v0.3.1 (16 Oct 2026):** fields the V3 data model already holds, needed by the dashboards. 3.3 `counts.approved_this_week`; 3.16 `equipment_type_name`, `captured_by_name`; 3.18 `q` filter and `reviewed_by`, `assignment`, `escalation_reason`. Same change in the Google Doc and `docs/api-contracts.md`.
- **S4 v0.3.2, S5 v0.3.1 (16 Oct 2026):** after a data model change (new columns `audit_log.summary`, `notification.body`). 3.19 `body`, `emailed_at`; 3.22 `summary`; 4.1 `options.columns` limited to `field_values`, `ai_vs_technician`, `review_decision`. Full list: `docs/proposals/data-gaps-oct-2026.md`.
- **S2 v0.3.1 (16 Oct 2026):** decisions D-08, D-09, D-11 (`docs/proposals/decisions-o12-o23.md`). 1.4–1.5 deprecated (Keycloak checks codes); 1.6 token in the URL fragment; 1.7 accepts all pending invites for the email and role, Keycloak sends the code.
- **S2 v0.3.2 (19 Oct 2026):** values the EA screens show (EA 03 unit cards, EA 25–28 unit page), additions only. `BusinessUnit` gains `technician_count`, `scans_this_month`, `vacant_since`, `previous_bu_admin`. Same change in `docs/api-contracts.md`.

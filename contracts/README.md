# API contracts (OpenAPI 3.1), v0.3.0

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

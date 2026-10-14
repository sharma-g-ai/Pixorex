# API contracts (OpenAPI 3.1)

**Action needed:** drop the contract files here before the first API PR:

- `common.yaml`
- `slice-s2-auth-rbac.yaml`
- `slice-s3-capture-extraction.yaml`
- `slice-s4-workflow-review.yaml`
- `slice-s5-portal-export.yaml`
- `.spectral.yaml`

The readable version is `docs/api-contracts.md`. Each operation's description starts with "Contract ref n.n", which specs and tasks cite.

Rules: changing an endpoint means changing the contract in the same PR. Spectral lint runs on every PR that touches this folder. Nothing marked `x-decision-pending` is built until its decision is in `STATE.md`.

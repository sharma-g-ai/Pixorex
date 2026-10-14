# Pixorex V1

AI-powered industrial asset digitization for PPG Industries. Monorepo: `api/` (FastAPI), `web/` (React + TS), `mobile/` (Flutter), `keycloak/`, `contracts/`.

**Read first, in this order:** `CONSTITUTION.md` → `ARCHITECTURE.md` → `STATE.md` → your spec in `specs/`.

## Quick start (local, synthetic data only)

```bash
git clone <repo-url> && cd pixorex
make up          # postgres, keycloak, minio, vault (dev), mailpit
make ps          # all services healthy?
```

| Service | URL |
|---|---|
| Keycloak admin | http://localhost:8080 (local-only admin credentials in docker-compose.yml) |
| MinIO console | http://localhost:9001 |
| Vault (dev) | http://localhost:8200 |
| Mailpit inbox | http://localhost:8025 |
| PostgreSQL | localhost:5432, db `pixorex` |

The API, worker, realm import and seed data arrive with the Sprint 2 tasks in `STATE.md` (PX-10-T01/T02, PX-01-T01, PX-04-T06).

## How we work

1. Pick your next task from `STATE.md` (your lane only).
2. Branch: `git switch -c PX-04-T01-domain1-schema`
3. Start a fresh agent session for that one task:
   ```bash
   OPERATOR=FSD-A ./start-session.sh PX-04-T01 "api/migrations/0001_domain1.sql api/tests/isolation/test_domain1.py" "Data model"
   ```
4. Tests first. ≤ 5 files, ≤ 200 lines changed.
5. Open a PR titled `PX-04-T01: …` using the template. Two approvals, never your own; architects for A0/A1.
6. Update `STATE.md` in the same PR.

## Rules you cannot skip

- **Synthetic data only.** No real PPG data on laptops, CI or logs.
- **No secrets in the repo.** The secret scan blocks the merge. The credentials in `docker-compose.yml` are local-only placeholders for throwaway containers.
- **Nothing marked OPEN or BLOCKED gets built** until the decision is recorded in `STATE.md`.
- **The data model is frozen.** No new tables or columns without a written change request.

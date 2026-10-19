# Pixorex V1

AI-powered industrial asset digitization for PPG Industries. Monorepo: `api/` (FastAPI), `web/` (React + TS), `mobile/` (Flutter), `keycloak/`, `contracts/`.

**Read first, in this order:** `CONSTITUTION.md` → `ARCHITECTURE.md` → `STATE.md` → your spec in `specs/`.

**Team status, who does what next, and open decisions:** [docs/handover.md](docs/handover.md). Mobile app developers: [docs/mobile-api.md](docs/mobile-api.md).

## Quick start (local, synthetic data only)

Full guide with checks and fixes: [docs/local-setup.md](docs/local-setup.md).

**You need:** Docker Desktop (running) and Node 24.

**First time** (PowerShell, a few minutes):

1. `git clone <repo-url>` and `cd pixorex`
2. `.\scripts\setup-local.ps1`
3. `cd web` then `npm run dev`
4. Open http://localhost:5173 and sign in as `ea@demo.local` (Enterprise Admin) or `buadmin.p04@demo.local` (BU Admin).
5. Get the 6-digit code from Mailpit: http://localhost:8025

**Every day after that:**

1. `docker compose up -d` (in the repo folder)
2. `cd web` then `npm run dev`

**Stop:** `Ctrl+C` in the web window, then `docker compose down` (data is kept).

**Something wrong?** `docker compose ps` shows each service; `docker compose logs api` shows API errors. Running `.\scripts\setup-local.ps1` again is safe.

**Real email (optional):** put the `PIXOREX_SMTP_*` values in `.env` (see `.env.example`), then run the setup script again. Codes and invites then go to real inboxes instead of Mailpit.

| Service | URL |
|---|---|
| Web app | http://localhost:5173 |
| API | http://localhost:8000/api/v1/ready |
| Mailpit inbox | http://localhost:8025 |
| Keycloak admin | http://localhost:8080/admin (`admin` / `local-only`) |
| MinIO console | http://localhost:9001 |
| PostgreSQL (app) | localhost:5433, db `pixorex`, user `postgres` / `local-only` |

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

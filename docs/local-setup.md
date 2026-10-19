# Local setup guide

Run Pixorex (backend, sign-in and web app) on a Windows laptop. Synthetic data only.

## What you need

1. **Docker Desktop**, installed and running.
2. **Node 24** (`node --version` shows v24).
3. The repo cloned, e.g. `C:\atg\pexorex`.

## First time (about 10 minutes)

Run each command in PowerShell from the repo folder.

1. **Set everything up:**
   ```powershell
   .\scripts\setup-local.ps1
   ```
   It ends with `Done. Start the web app:`. If it stops earlier, see "Fixes" below.
2. **Start the web app:**
   ```powershell
   cd web
   npm run dev
   ```
   Wait for `Local: http://localhost:5173/`.
3. **Open** http://localhost:5173.
4. **Sign in** as one of the demo users:
   | Email | Who |
   |---|---|
   | `ea@demo.local` | Enterprise Admin (sees every unit) |
   | `buadmin.p04@demo.local` | BU Admin of Plant 04 |
5. **Get the 6-digit code** from Mailpit: http://localhost:8025

## Every day

1. Start Docker Desktop.
2. In the repo folder: `docker compose up -d`
3. In `web`: `npm run dev`
4. Open http://localhost:5173

## Stop

1. `Ctrl+C` in the web window.
2. In the repo folder: `docker compose down` (your data is kept).

## Check it's working

| Check | Good result |
|---|---|
| `docker compose ps` | Every service `Up`; `migrate` shows `Exited (0)`, which is normal |
| `docker compose logs worker` | `worker_started`; then `jobs_done` / `outbox_done` lines when it has work |
| http://localhost:8000/api/v1/ready | `"status":"ready"` (wait about 1 minute after starting: Keycloak is slow to start) |
| http://localhost:5173 | The sign-in page |

## Addresses

| What | Address |
|---|---|
| Web app | http://localhost:5173 |
| API health | http://localhost:8000/api/v1/ready |
| Mailpit (local mail) | http://localhost:8025 |
| Keycloak admin | http://localhost:8080/admin (`admin` / `local-only`) |
| Database | `localhost:5433`, db `pixorex`, user `postgres` / `local-only` |

## Real email (optional)

Full details and fixes: [email-setup.md](email-setup.md).

1. Add the `PIXOREX_SMTP_*` lines to `.env` (names in `.env.example`; get the values privately, never in chat).
2. Run `.\scripts\setup-local.ps1` again.
3. Sign in with a **real** email that was invited. `@demo.local` addresses get no code once real email is on.

## Fixes

| You see | Fix |
|---|---|
| `Docker is not running` | Start Docker Desktop, wait until it says running, run the command again |
| `port is already allocated` / `5173 is in use` | Something else uses the port. Close the other app (or old `npm run dev` window) and retry |
| `/ready` shows `keycloak: fail` right after starting | Wait 1 minute and refresh |
| Sign-in page: "We could not send your code" | Real email is on and the provider refused it. Check: `docker compose logs keycloak \| Select-String "Failed to send"`. `Maximum credits exceeded` = the SendGrid account is out of credits (ask its owner); `535` = wrong key |
| No code in Mailpit for a demo user | Real email is on (see above), or you typed the email wrong |
| A screen says "couldn't load" | The API refused or failed: `docker compose logs api` shows why. If you just pulled new code: `docker compose up -d --build api` |
| You changed API code but see no change | `docker compose up -d --build api` |
| Anything else | Run `.\scripts\setup-local.ps1` again (safe), then `docker compose logs api` |

## Start completely fresh (deletes local data)

1. `docker compose down -v`
2. `.\scripts\setup-local.ps1`

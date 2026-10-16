# Pixorex web: EA + BU Admin dashboards

React + TypeScript (strict) + Vite, Tailwind. Node 24 (`.nvmrc`). Stack: decision D-01 in `STATE.md`.

## Run

**Real API + Keycloak (Phase E — preferred):**

```bash
# terminal 1 — FastAPI (see api/README.md); Postgres on host :5433, Keycloak up
cd ../api && .\.venv\Scripts\Activate.ps1 && uvicorn app.main:app --reload --port 8000

# terminal 2 — web
npm install
# .env.local: VITE_OIDC_AUTHORITY + VITE_OIDC_CLIENT_ID (see .env.example)
npm run dev        # http://localhost:5173 — /api/v1 proxies to :8000
```

**Prism mock (no FastAPI):** set `VITE_API_PROXY_TARGET=http://127.0.0.1:4010` in `.env.local`, then `npm run api:mock` and `npm run dev`.

## Sign-in (D-11)

Keycloak, OIDC Authorization Code + PKCE (`oidc-client-ts`). Settings in `.env.example` / `.env.local`:

- **With Keycloak + real API:** set `VITE_OIDC_AUTHORITY` and `VITE_OIDC_CLIENT_ID`. Proxy defaults to FastAPI `:8000`.
- **Development without Keycloak:** leave OIDC vars empty (mock auth). Still need Prism or FastAPI for `/me`.
- **Production builds** without OIDC settings refuse to run.
- Keycloak client `pixorex-web`: redirect `<origin>/auth/callback`, post-logout `<origin>/signed-out`, web origin `<origin>`, PKCE S256.

Public routes: `/auth/callback`, `/signed-out`, `/activate` (invite links, token in the `#` fragment). Everything else needs a session. Tokens stay in `sessionStorage`.

## Scripts

| Script                      | Does                                                                                                                |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `dev` / `build` / `preview` | Vite dev server, production build, preview the build                                                                |
| `typecheck`                 | TypeScript, strict                                                                                                  |
| `lint`                      | ESLint                                                                                                              |
| `format` / `format:check`   | Prettier                                                                                                            |
| `test` / `test:watch`       | Vitest + Testing Library                                                                                            |
| `api:types`                 | Regenerate `src/api/generated/` from `../contracts` (run after any contract change)                                 |
| `api:mock`                  | Dev-only Prism mock of every contract slice (`scripts/mock-api.mjs`); delete with the script once the real API runs |

## Layout

| Folder            | For                                                                                   |
| ----------------- | ------------------------------------------------------------------------------------- |
| `src/app/`        | App shell, routes, role-based navigation                                              |
| `src/api/`        | The one API client (`client.ts`) and generated types; never edit `generated/` by hand |
| `src/auth/`       | Sign-in and tokens (architect review, CODEOWNERS); added in PX-01-T12                 |
| `src/features/`   | One folder per dashboard area (units, staff, review, ...)                             |
| `src/components/` | Shared UI components: reuse or extend before adding new ones                          |
| `src/lib/`        | Shared helpers                                                                        |
| `src/styles/`     | Tailwind and design tokens: no hardcoded colours or fonts                             |

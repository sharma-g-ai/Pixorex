# Pixorex web: EA + BU Admin dashboards

React + TypeScript (strict) + Vite, Tailwind. Node 24 (`.nvmrc`). Stack: decision D-01 in `STATE.md`.

## Run

```bash
npm install
npm run api:mock   # terminal 1: mock API from the contracts on :4010
npm run dev        # terminal 2: app on http://localhost:5173 (/api/v1 goes to the mock)
```

## Sign-in (D-11)

Keycloak, OIDC Authorization Code + PKCE (`oidc-client-ts`). Settings in `.env.example`:

- **Development without Keycloak:** leave `VITE_OIDC_AUTHORITY` empty. The app skips sign-in and the dev proxy sends a placeholder token to the mock.
- **With Keycloak:** set `VITE_OIDC_AUTHORITY` and `VITE_OIDC_CLIENT_ID` in `.env.local` (git-ignored) or the build environment. The `pixorex-web` client needs redirect URI `<origin>/auth/callback`, post-logout URI `<origin>/signed-out`, web origin `<origin>`, PKCE S256 required, refresh tokens on.
- **Production builds** without these settings refuse to run.

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

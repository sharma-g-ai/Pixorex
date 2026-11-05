# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PPG SeaStock: inventory and consumption tracking for paint and thinners on board vessels. This
is the `ppg-seastock` branch of `sharma-g-ai/Pixorex`. Our part is the **compact** web portal
(8 screens, `web/`) and the MVP API contracts (`contracts/`). `web/` is static screens over sample
data, and nothing connects it to `contracts/` yet. The rest of the branch came from the team and
nothing in `web/` uses it: the Flutter mobile app (`frontend/`), a Python backend (`backend/`), a
static portal POC (`client_portal_poc/`), Supabase setup and the delivery note handoff
(`ppg_handoff/`).

A 17-screen version lives in `C:\atg\ppg-seastock` (port 5180). It is reference only; the team is
comparing the two.

The BRD (now v1.3) and SeaStock Data Models V2 are not in the repo. `web/` and `contracts/` both follow V2. Their IDs are used
throughout the code and docs: `FR-nn` requirements, `A-nn` assumptions, `D-nn` decisions, and `SD-n`
contract decisions pending. `docs/screens.md` maps screens to the BRD and lists the open questions
for PPG.

## Commands

Run these from `web/`. Node 24 or later is required.

```
npm install
npm run dev              # http://localhost:5181
npm run build            # tsc -b, then vite build
npm run typecheck
npm run lint
npm test                 # vitest run, all tests

npx vitest run src/data/store.test.ts            # one file
npx vitest run src/app/App.test.tsx -t "sign-in" # tests matching a name
```

`npm test` includes `src/app/App.test.tsx`, which renders every path for several sample users.

Current baseline: lint gives 0 errors and 8 `react-refresh` warnings. `npm run format:check` fails
on 38 files, including data-heavy code such as `src/data/store.ts`, which is written on long lines.
Do not run `npm run format` across the repo; it would rewrite unrelated files. Format only what you
touched, and leave those dense data lines as they are.

Contracts, from the repo root (needs PyYAML):

```
python contracts/check.py                                  # refs, labels, path params, unique operationIds
npx @stoplight/spectral-cli lint contracts/*.yaml          # style
npx @stoplight/prism-cli mock contracts/tablet-sync.yaml   # mock server on :4010
```

Other builds:

- Help docs: see `docs/help/README.md`. `take.mjs` drives local Chrome against the dev server.
- Role demos: see `docs/role-demos/README.md`. These use `VITE_DEMO_USER=<id>` (starts signed in) or
  `VITE_STANDALONE` (single shareable file). Both switch to `MemoryRouter`. The commands use POSIX
  env syntax, so run them in Bash, not PowerShell.

## Web architecture

`src/app` holds the shell (routes, sign-in session, navigation), `src/features/<area>` the screens,
`src/components` the shared UI, and `src/data` everything about data. Pages import from `data/`
directly; there is no API layer yet.

**Data flow.** `data/sample.ts` exports mutable arrays. `data/store.ts` is the only writer: it
changes those arrays **in place**, so every importer sees the change, then saves a snapshot to
`sessionStorage` and notifies subscribers. `data/queries.ts` holds the read functions. Keep these
rules when changing data:

- A component that reads data calls `useStore()` so it re-renders. The return value is usually
  ignored; the call itself is the subscription. Without it, a screen goes stale after a change.
  `SeaStockPage` lacks it today, so its table does not update after Adjust stock.
- Every admin action goes through a `store.ts` function that takes `by: User`, writes an `audit()`
  row and calls `changed()`.
- Sea Stock is never stored. `stockLines()` adds it up from `transactions`, which are insert-only;
  a correction is a new adjustment row, never an edit. Negative stock is allowed and surfaced for
  review, not blocked.
- Time is the fixed `NOW` from `sample.ts` (21 Oct 2026, 16:00 UTC), not the real clock. `Date.now()`
  is used only to make IDs.
- If you change the shape of the data, bump `KEY` in `store.ts` (`seastock.data.v3`), or a tab's
  saved snapshot will load in the old shape.

**Roles and scope are two separate checks.** Both apply to every screen.

- Permissions: `can(user, permission)` from the `grants` table in `data/roles.ts`. There are two
  roles, `ppg-admin` and `customer-admin`. `navigation.ts` declares what each route `needs`, and
  `Layout` redirects anyone who lacks it. Buttons and tabs inside a page check `can()` themselves.
- Data scope: `visibleCustomers/Vessels/Devices(user)` in `queries.ts`. A Customer Admin sees one
  customer only. Filter through these rather than the raw arrays; anything outside scope must
  behave as if it does not exist.
- Vessels and crew have no portal accounts. They sign in on the tablet.

**Screen state.** `?tab=`, `?dn=<number>`, `?customer=<id>` and `?vessel=<id>` live in the URL. A link
without a filter clears it, and a value outside the user's scope is ignored. Other filters are local
state. The compact screens are merged from the 17-screen version, so each one holds what used to be several pages behind tabs and query
parameters. Admin routes share `features/admin/TabbedPage.tsx`, and `docs/screens.md` records what
each screen took over.

**Adding a screen**: add the route in `app/App.tsx`, the nav item with its `brd` and `needs` in
`app/navigation.ts`, and the path to `paths` in `App.test.tsx`.

**Styling**: Tailwind v4 with design tokens in `src/styles/index.css` (`@theme`). Use the token
classes (`bg-brand`, `text-ink-muted`, `border-line`); never hardcode colours or fonts in components.

**CSV export** goes through `lib/csv.ts`, which also handles a page published as a Claude artifact,
where the viewer must accept the download through `window.claude`.

## Testing

`test/setup.ts` runs `cleanup()` and `resetSampleData()` after each test, so tests can change data
freely. To open a page as a user, set `sessionStorage['seastock.session']` to a sample user ID, call
`window.history.pushState`, and render `<App />`. Only `status: 'active'` users can have a session.

## Contracts

OpenAPI 3.1, one file per area, written for Jira PIX-58 with the rules and open decisions in
`contracts/README.md`. Every operation carries `x-roles`, `x-brd`, `x-ticket` and `x-sprint`, and
`check.py` enforces this. Unresolved points are marked `x-decision-pending` and listed as SD-n
rather than guessed.

Naming differs from the web sample data: contracts use `ppg_admin` and snake_case, while `web/` uses
`ppg-admin` and camelCase.

## Known stale docs

`web/` is the source of truth: two roles, BRD v1.3. These still lag behind it:

- `docs/help/` (`steps.mjs`, `content.py`, the built help) and `docs/role-demos/` (`README.md`,
  `pack.py`) still describe a third **Ship Admin** role, which has been removed. They use `u12`,
  which is now an invited Customer Admin who cannot sign in, so those steps and that demo need
  rework, not just a rebuild. `docs/help/` also still describes regions, which were removed too.
- `tsconfig.app.json` mentions a CONSTITUTION that is not in this repo.

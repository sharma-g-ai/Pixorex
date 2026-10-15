# Final stack: EA + BU Admin dashboards

| Field | Value |
|---|---|
| Status | **Decided** Oct 15, 2026. The lead delegated the choices to the dashboard team with the brief "implement the best way possible"; decisions are taken for a multi-tenant SaaS product and recorded in `STATE.md` → *Decisions* |
| Scope | `web/` only: Enterprise Admin and BU Admin dashboards |
| Date | Oct 15, 2026 |
| Unblocks | PX-01-T11 (web scaffold), PX-01-T12 (web sign-in), PX-01-T13 (shell), PX-04-T10, PX-04-T11 |

## Why this is needed

ARCHITECTURE.md fixes the web framework (React + TypeScript + Vite, §2), the admin sign-in rules (§4.2) and the API conventions the client must follow (§10). It does not cover styling, routing, data fetching, the API client, tests or the `web/src/` layout. PX-01-T11 is due to start now, so these need one agreed answer before the first web PR; otherwise each task picks its own.

Once confirmed, this becomes a web section in ARCHITECTURE.md.

## Already decided (for reference)

| Area | Choice | Source |
|---|---|---|
| Framework | React + TypeScript (strict), Vite | ARCHITECTURE §2, CONSTITUTION pinned runtimes |
| Runtime | Node 24 LTS (changed from 22, see Q3) | CONSTITUTION pinned runtimes |
| Sign-in | Keycloak client `pixorex-web`, Authorization Code + PKCE, email code only, no passwords, no SAML in V1, tokens in memory only, silent refresh | ARCHITECTURE §4.2, SPEC-PX-01 |
| Lint | ESLint + strict TS | CONSTITUTION §4 |
| Users | Enterprise Admin and BU Admin only; technicians never get web access; no portal route | ARCHITECTURE §2, SPEC-PX-01 |
| Styling | Tailwind CSS | Release Plan v2 (not yet in the repo) |

## Stack choices (decided, Q1)

| # | Area | Proposed | Reason |
|---|---|---|---|
| 1 | Styling | Tailwind CSS | Already in Release Plan v2; recording it in the repo |
| 2 | Routing | React Router | Standard for a Vite SPA with role-based routes |
| 3 | Server data and caching | TanStack Query | Loading, caching and refetch for API data without hand-written state |
| 4 | API client | `openapi-typescript` + `openapi-fetch`, generated from `contracts/` | Types come from the contract, so the web app cannot drift from it (contract-first, CONSTITUTION §3) |
| 5 | Mock API | Prism, run from the contract files | Already named in the contracts README; web work can start before the API exists |
| 6 | OIDC library | `oidc-client-ts` + `react-oidc-context` | Maintained OIDC client supporting PKCE and in-memory token storage |
| 7 | Forms and validation | React Hook Form + Zod | Invite forms, unit setup, equipment type builder |
| 8 | UI components | Own small component set on Tailwind; no UI kit | Matches the prototypes exactly; no third-party kit to restyle |
| 9 | Design tokens | IBM Plex Sans / IBM Plex Mono; accent `#F07D22`, navy `#2E3192`; Pixorex logos from the design canvas | Taken from the prototypes |
| 10 | Icons | Inline SVG | No icon dependency |
| 11 | Unit and component tests | Vitest + React Testing Library | Native to Vite; feeds the 80% changed-line coverage gate |
| 12 | End-to-end tests | Playwright | Sign-in and role-gating flows against the local stack |
| 13 | Formatting | Prettier (alongside ESLint) | Consistent diffs |
| 14 | Package manager | npm | Ships with Node 24; no extra tooling in CI |

## Proposed `web/src/` layout

```
web/src/
├── auth/          # sign-in, token handling, route guards (CODEOWNERS: architects; A0)
├── api/           # generated types, client wrapper, problem+json error handling
├── app/           # shell, router, role-based navigation, unit switcher
├── features/
│   ├── units/            # EA-01 units overview, create unit, BU Admins
│   ├── locations/        # EA-02 levels, tree, publish
│   ├── scans/            # EA-03 scans, escalations
│   ├── audit/            # EA-04 audit log, export, notifications
│   ├── staff/            # BU-01 technicians, invites
│   ├── equipment-types/  # BU-02 type builder
│   ├── review/           # BU-03 review queue, decisions
│   ├── delegation/       # BU-04 batches
│   └── exports/          # BU-05 usage, CSV
├── components/    # shared UI (buttons, tables, dialogs, badges)
└── styles/        # Tailwind config, design tokens
```

`web/src/auth/` matches the existing CODEOWNERS entry.

## Rules the web app follows

- **Navigation by role.** EA and BU Admin get different navigation; a technician is refused.
- **Permissions from `GET /me`.** Units and roles come from the API (contract 1.1), never from token claims (CONSTITUTION §3).
- **Every call** sends the Bearer token and `X-Device-Id`; unit-scoped calls put the unit in the path as `{buId}` (ARCHITECTURE §10).
- **Errors** are read from the problem+json `type` code (for example `/problems/locked-after-publish`) and mapped to messages.
- **The API decides statuses.** The UI calls the action endpoint (`/publish`, `/decisions`, …) and shows a 409 when the move is refused or another user decided first.
- **Not built in V1:** portal route, process picker, editing a published location tree or equipment type, batch approve/reject (CONSTITUTION §0).

## Decisions

Each question below arose because two of our own sources disagree, or because none of them answers it. CONSTITUTION §0 says nothing OPEN is built until the decision is recorded in `STATE.md`; these decisions are recorded there.

Guiding principles, for a multi-tenant SaaS product:
- **Role hierarchy.** The Enterprise Admin is the tenant administrator and can do everything a BU Admin can, in any unit of the tenant. The BU Admin is limited to the units they run. This matches the contract convention "Enterprise Admin passes for every unit of the tenant" and means no unit gets stuck when its BU Admin seat is vacant.
- **PRD wins for behaviour.** Where the contracts and the PRD disagree on who may do what, CONSTITUTION §0 says the PRD wins; the contracts are updated to match.
- **Keep V1 small, keep the door open.** Choose what V1 needs, in a way that adds the enterprise options (SSO, newer versions) later without rework.

| # | Question | Decision | Blocks |
|---|---|---|---|
| Q1 | The 14 stack choices | Approved as listed above | PX-01-T11 and every web task after it |
| Q2 | Admin sign-in | Email code in V1; SSO added later per tenant through Keycloak identity brokering | PX-01-T10, PX-01-T12 |
| Q3 | PostgreSQL and Node versions | PostgreSQL 18 and Node 24 LTS everywhere (local, Compose, CI) | Local stack matching CI |
| Q4 | Who invites whom | EA invites BU Admins and technicians into any unit; BU Admin invites technicians into units they run | PX-04-T10 (EA-01), PX-04-T11 (BU-01) |
| Q5 | Who can override | BU Admin for their units, EA for any unit | BU-03, EA-03 |
| Q6 | Audit log access | EA for all units; BU Admin read and export for units they run | BU-05, EA-04 |
| Q7 | Screen ID mapping | Mapping table in `docs/design/README.md`; tasks cite both IDs | Every dashboard task and PR |

---

### Q1. Confirm the 14 stack choices

**What we're asking:** approve the proposed choices table above (accept, or name a replacement per row).

**Why we're asking:** ARCHITECTURE.md only fixes React + TypeScript + Vite. PX-01-T11 (scaffold, typed client, mock server) is the first web task and is due to start now. Whatever it installs becomes the pattern every later web task copies, and CONSTITUTION §4 requires a justification for each new dependency, so the choices should be approved once rather than argued in every PR.

**Example:** without an agreed API client, one developer hand-writes the TypeScript type for `GET /me` and another generates it from the contract. When contract 1.1 later adds a field, the generated type picks it up and the hand-written one silently goes stale. The bug shows up in a demo, not in CI.

**Decision:** approved as listed. Item 4 (generated client) and item 5 (Prism mock) matter most, because they let web work run against the contracts before the API exists.

---

### Q2. Admin sign-in: email code or SAML?

**What we're asking:** for V1, do EA and BU Admin sign in with a one-time email code, or through PPG's SAML login (Entra ID)?

**Why we're asking:** the sources disagree.

| Source | Says |
|---|---|
| PRD V3 FR-1.5, ARCHITECTURE §4.2 | Admins use an email code; "no SAML in V1" |
| CONSTITUTION §0 | "SAML as a product flow" is out of V1, never build |
| EA and BU Admin prototypes | Email address, then a 6-digit code; 5 wrong codes lock sign-in for 30 minutes |
| Release Plan v2 | Admins sign in with SAML SSO through PPG's Entra ID |
| STATE.md | The Sprint Deliverables text still says "BU Admin via SSO" and needs updating |

**Example:** with email codes, the EA types `ea@ppg.example`, receives a code and enters it on our themed Keycloak screen; lockout is ours. With SAML, the EA clicks "Sign in with PPG" and is sent to PPG's login page. There is no code screen and no lockout of our own, but we need PPG's metadata and an IT contact before anyone can sign in at all, including in the demo.

**What changes if SAML is chosen:** the Keycloak realm (PX-01-T01), the login theme (PX-01-T10), web sign-in (PX-01-T12), the Sprint 2 demo script, and CONSTITUTION §0 itself.

**Decision:** email code for V1, as the PRD and CONSTITUTION say. For a SaaS product, enterprise SSO is something individual customers ask for, not something every tenant needs on day one. Keycloak's identity brokering lets us add SAML or OIDC per tenant later (PPG's Entra ID first) without changing the web app: it still talks only to Keycloak through the same `pixorex-web` client. Admin MFA (PRD open item P-4) is a separate question to settle before release.

---

### Q3. PostgreSQL 16 or 18?

**What we're asking:** should local development stay on the native PostgreSQL 18 already installed, or match the version 16 that the repo pins?

**Why we're asking:** CONSTITUTION pins PostgreSQL 16, and `docker-compose.yml` and CI run `postgres:16`. Local development is on a native PostgreSQL 18 install, with no Docker on the machine. Code that works on 18 but not on 16 passes locally and fails in CI, or the reverse.

**Example:** `uuidv7()` is built into PostgreSQL 18 but does not exist in 16. A migration that uses it as a column default runs fine on the local machine and then fails in CI with "function uuidv7() does not exist".

**A related point:** the local install's default `postgres` user is a superuser, and superusers bypass row-level security. Isolation tests run as that user pass even if the policies are wrong. Local setup needs the same separate owner and app roles that ARCHITECTURE §4.4 describes.

**Options:**
- (a) Install PostgreSQL 16 locally next to 18. Nothing in the repo changes.
- (b) Move the whole project to 18: CONSTITUTION, `docker-compose.yml` and CI change together, approved by both architects.

**Decision:** (b): PostgreSQL 18 everywhere, and Node 24 LTS for the same reason. A SaaS product starting now should begin on current supported versions instead of planning an upgrade straight after launch: PostgreSQL 18 is supported into 2030 and Node 24 is the active LTS line. Local development already runs both. `docker-compose.yml`, CI and the CONSTITUTION pins change together. Keycloak and its own internal database (`keycloak-db`) are not part of this change and stay as they are. Local setup still needs the separate owner and app roles so that isolation tests do not run as a superuser.

---

### Q4. Who invites whom?

**What we're asking:** which admin can invite which role into which units?

**Why we're asking:** the sources disagree, and the repo's own ingest report (`.planning/INGEST-CONFLICTS.md`) flags it as a warning.

| Source | Says |
|---|---|
| Contract 1.8, SPEC-PX-01 REQ-01.10 | EA invites BU Admins, only into units with no BU Admin. BU Admin invites technicians, only into the units they run |
| PRD open item 5 | Unresolved. The permissions matrix gives the EA "oversight only" for technicians; BRD US-036 and US-049 say the BU Admin invites; the implementation PRD says "EA or BU Admin" |

**Example of the gap:** the EA creates "Plant 05" and leaves the BU Admin vacant for now. Under the contract rules, nobody can invite technicians to Plant 05: the EA isn't allowed to, and there is no BU Admin to do it. Scanning cannot start there until a BU Admin is found.

**What it changes on screen:**
- If the contract rules stand, the EA unit pages (EA-01) have "Invite BU Admin" only, and "Invite technician" appears only on the BU Admin staff page (BU-01).
- If the EA may also invite technicians, EA-01 gets an "Invite technician" action, and contract 1.8's roles change.

**Decision:** the EA can invite BU Admins and technicians into any unit; the BU Admin invites technicians into units they run. This follows the role hierarchy above: the tenant administrator is never blocked, and a vacant unit can still onboard technicians. The existing rule "only units with no BU Admin" for BU Admin invites stays (one active BU Admin per unit). Contract 1.8 `x-roles` and SPEC-PX-01 REQ-01.10 are updated to match.

---

### Q5. Who can override a decision?

**What we're asking:** who can reverse a review decision already made, for example change "approved" to "rejected"?

**Why we're asking:** the sources disagree, also flagged in `.planning/INGEST-CONFLICTS.md`.

| Source | Says |
|---|---|
| PRD permissions matrix | EA: Yes. BU Admin: unresolved (PRD open item 6) |
| Contract 3.7 (`POST /decisions/{decisionId}/override`) | BU Admin only |
| BU Admin prototype (BU 19, 22–23) | BU Admin has "Technician decisions" with an Override action |

**Example:** a delegated technician approves scan REC-90141 in Plant 04 with a wrong serial number. The BU Admin spots it under Technician decisions and overrides it to rejected; the technician receives a "decision changed" notice.

Now take the same case in Plant 05, which has no BU Admin. Under contract 3.7, nobody can override the bad approval. Under the PRD matrix, the EA can.

**What it changes on screen:** whether the EA scan detail (EA-03) shows an Override button, and whether the BU Admin keeps the one in the prototype.

**Decision:** the BU Admin overrides in units they run (as the prototype shows); the EA overrides in any unit (as the PRD matrix says, and so units with no BU Admin are covered). Contract 3.7 `x-roles` and PRD open item 6 are updated to match.

---

### Q6. Can a BU Admin see the audit log?

**What we're asking:** can a BU Admin read and export the audit log for their own units, or is the audit log for the EA only?

**Why we're asking:** the sources disagree, also flagged in `.planning/INGEST-CONFLICTS.md`.

| Source | Says |
|---|---|
| PRD permissions matrix, FR-6.4, screen BU-05 | BU Admin may read and export scans **and audit** for their own unit |
| SPEC-PX-07 REQ-07.01 | `audit_log` is readable by the EA only |
| Contract 3.22 (`GET /audit-log`) | EA only |
| Contract 4.1 (`POST /exports`) | BU Admin exports scans only; only the EA exports the audit log |
| BU Admin prototype | Has no audit log screen |

**Example:** a BU Admin wants to know who removed technician R. Kowalski from Plant 04 last Tuesday. Under the PRD, they open Audit log, filter by "users" and see the row. Under the contract, they cannot see it and have to ask the EA.

**What it changes:**
- the BU Admin navigation (an "Audit log" item or not)
- BU-05's filters and export options
- the row-level security policy on `audit_log`, which is architect-only (A0) work
- contracts 3.22 and 4.1

**Decision:** the EA reads and exports the audit log for every unit; the BU Admin reads and exports it for units they run. This is what the baselined PRD promises (BU-05, FR-6.4), and CONSTITUTION §0 says the PRD wins for behaviour. In SaaS admin consoles a unit administrator normally sees the activity of their own unit. `audit_log` already carries `bu_id`, so this is a unit-scoped RLS policy like every other unit table, not a schema change. Contracts 3.22 and 4.1 and SPEC-PX-07 REQ-07.01 are updated to match, and the BU Admin dashboard gains an Audit log screen (built in S4 with the EA one).

---

### Q7. Screen ID mapping

**What we're asking:** can we agree a mapping between the PRD's 9 dashboard screen IDs and the prototype screen numbers, and keep it in `docs/design/README.md`?

**Why we're asking:** two numbering schemes are in use, and no document links them (`.planning/INGEST-CONFLICTS.md`, INFO).

| Used in | Scheme |
|---|---|
| PRD, specs, ARCHITECTURE | 9 dashboard screens: EA-01–04, BU-01–05 |
| Contracts, prototypes, design canvas | EA 01–73, BU 01–35 |

**Example:** a task says "build BU-03 Review queue and decision". In the prototype that is at least 8 screens: from the contract Screens columns, 3.3 cites BU 03, 05, 08 and 10; 3.4 cites BU 07, 20 and 22; 3.5 cites BU 07 and 20–21. Without a mapping, the developer may build only some of them, and at G4 (end-of-sprint check) nobody can tell whether BU-03 is complete.

Another example: EA-01 "Units overview, create, edit" draws on contracts 1.12–1.17, which cite EA 03, 10, 11 and 13–18.

**Decision:** the mapping is drafted from the Screens columns in `docs/api-contracts.md` and kept in `docs/design/README.md`. Tasks then cite both IDs, for example "BU-03 (BU 03, 05, 07, 08, 10, 20–22)".

## Next steps

1. Commit the v3 contract files to `contracts/` (needed for items 4 and 5).
2. Add the confirmed choices as a web section in ARCHITECTURE.md.
3. Scaffold `web/` to match (PX-01-T11).

# STATE.md — Pixorex V1

> Operator updates this after every task, in the same PR. The agent reads it at session start. Keep the task table's column order: `start-session.sh` reads Status from the 5th column.

## Current wave
- **Sprint:** S2 (Wks 3–4) · ends **Tue Oct 20, 2026** · 4 working days left after Oct 14
- **Wave goal:** a signed-in user lands in their own unit, sees only what their role allows, and the isolation is proven by tests.
- **Environment:** local Compose stack, synthetic data only (stated up front in the demo).

### Demo script (replaces the Sprint Deliverables S2 wording)
The Sprint Deliverables plan says "BU Admin via SSO" and "Reviewer role". PRD V3 removed both: admins sign in by email code, and there is no Reviewer role. Update the plan to:
1. EA signs in with an email code → sees units; creates unit "Plant 04" and invites its BU Admin.
2. BU Admin accepts the invite, signs in with an email code → sees only Plant 04; invites a technician.
3. Technician accepts on the phone, signs in by **SMS** (and once by email) → lands on Home with the unit, can switch units.
4. Role-gating: same seeded data shown as EA vs BU Admin vs technician.
5. Proof: run the isolation test suite live; 5 wrong codes → 30-minute lock + audit row.

Lanes: **FSD-A** Foundation · **FSD-B** API & Security · **Divya** web · **Flutter** mobile · **DevOps** stack + CI. D = demo-critical; S = may slip to S3.

## Task board

| Task ID | Title | Grade | Operator | Status | PR | Notes |
|---|---|---|---|---|---|---|
| PX-10-T01 | Compose stack: postgres16, keycloak, minio, vault dev, mailpit, api, worker | A1 | DevOps | todo | | D · day 1 · blocks all |
| PX-10-T02 | API skeleton: layering, problem+json, JSON logs, config, /health, /ready | A1 | FSD-B | todo | | D · **G2 baseline** · needs T01 |
| PX-10-T03 | Vault secret loading at startup + dev seed script | A0 | DevOps + architect | todo | | D · needs T01 |
| PX-10-T04 | CI: path-filtered workflows, tests on Compose, 80% changed-line coverage | A1 | DevOps | todo | | D |
| PX-10-T05 | CI: gitleaks, Semgrep/Bandit, dependency + container scan | A1 | DevOps | todo | | D |
| PX-10-T06 | CI: Spectral contract lint, PR size, task-ID title; branch protection; CODEOWNERS | A1 | DevOps | todo | | D |
| PX-10-T07 | AI review job | A1 | DevOps | todo | | S |
| PX-04-T01 | Migration: Domain 1 tables + location_hierarchy_version, tenant FKs, unique rules | A1 | FSD-A | todo | | D · **G2 baseline** · needs T02 |
| PX-04-T02 | DB roles, grants, RLS policies Domain 1 | A0 | FSD-A + architect | todo | | D · needs PX-04-T01 |
| PX-04-T03 | Isolation test harness (2 tenants × 2 units) + Domain 1 isolation tests | A0 (tests by agent) | FSD-A | todo | | D · demo proof |
| PX-07-T01 | Migration: audit_log (monthly partitions, insert-only grants) + outbox_event | A1 | FSD-A | todo | | D |
| PX-07-T02 | Audit writer + outbox enqueue (same transaction) | A1 | FSD-A | todo | | D |
| PX-07-T03 | Outbox worker + SMTP adapter (Mailpit) | A2 | FSD-A | todo | | D · invite emails |
| PX-01-T01 | Keycloak realm as code: clients, PKCE, no passwords, claim mappers, brute-force 5/30 | A0 | FSD-B + architect | todo | | D · **G2 baseline** |
| PX-01-T02 | OTP authenticator: email code | A0 | FSD-B | todo | | D · largest risk with T03 |
| PX-01-T03 | OTP authenticator: SMS code + request throttling | A0 | FSD-B | todo | | D · needs P-3 answer |
| PX-01-T04 | Keycloak event listener → internal audit endpoint | A0 | FSD-B | todo | | D · lockout audit |
| PX-01-T05 | Request-context middleware: JWT, app_user, session, revocation ≤60 s, SET LOCAL | A0 | FSD-B + architect | todo | | D · needs PX-04-T02 |
| PX-04-T04 | Authorization helper require_role + role-boundary test generator from x-roles | A0 | FSD-B | todo | | D |
| PX-04-T05 | Tenant bootstrap CLI | A1 | FSD-A | todo | | D · needs P-1 decision |
| PX-04-T06 | Synthetic seed script | A2 | FSD-A | todo | | D |
| PX-01-T06 | GET /me, PUT /me/active-unit, POST /me/sign-out (1.1–1.3) | A1 | FSD-B | todo | | D · needs O-11 |
| PX-04-T07 | GET/POST /business-units, GET /business-units/{buId} (1.12–1.14) | A2 | FSD-A | todo | | D |
| PX-01-T07 | POST/GET /invites, resend, cancel (1.8–1.11) | A1 | FSD-B | todo | | D |
| PX-01-T08 | Invite preview + accept, Keycloak user creation (1.6–1.7) | A1 | FSD-B | todo | | D · activation part needs O-12, O-23 |
| PX-04-T08 | BU Admin list/assign/remove (1.15–1.17) | A1 | FSD-A | todo | | S |
| PX-04-T09 | Technician list/remove + lock state from Keycloak (1.18–1.19) | A1 | FSD-A | todo | | S · needs O-13 |
| PX-01-T09 | Phone change (1.4–1.5) | A0 | FSD-B | blocked | | S · O-12 |
| PX-01-T10 | Keycloak login theme matching MOB-01 / admin sign-in screens | A2 | Divya | todo | | D |
| PX-01-T11 | Web: Vite + TS scaffold, typed client + mock server from OpenAPI | A2 | Divya | todo | | D · day 1 |
| PX-01-T12 | Web: OIDC PKCE sign-in, token refresh, sign-out | A0 | Divya + architect | todo | | D |
| PX-01-T13 | Web: role-gated shell (EA vs BU Admin nav), unit switcher | A2 | Divya | todo | | D |
| PX-04-T10 | Web: EA-01 units overview + create unit + invite BU Admin | A2 | Divya | todo | | D |
| PX-04-T11 | Web: BU-01 staff and invites | A2 | Divya | todo | | D |
| PX-01-T14 | Mobile: Flutter scaffold, secure storage, X-Device-Id, API client | A2 | Flutter | todo | | D · day 1 |
| PX-01-T15 | Mobile: sign-in via system browser + PKCE (MOB-01), invite deep link | A0 | Flutter + architect | todo | | D |
| PX-01-T16 | Mobile: Home + unit switch (MOB-02) on /me and /me/active-unit | A2 | Flutter | todo | | D |
| PX-10-T08 | Demo runbook + phone-to-laptop network check | A3 | DevOps | todo | | D · do by Fri |

**Next tasks to start (Thu Oct 15 morning):** PX-10-T01 (DevOps), PX-01-T01 (FSD-B), PX-01-T11 (Divya), PX-01-T14 (Flutter). FSD-A starts PX-04-T01 as soon as PX-10-T02 merges; until then, write the isolation harness design.

## Gate status

| Gate | Scope | Status | Signed by | Date |
|---|---|---|---|---|
| G1 | SPEC-PX-01, 04, 07 (S2 part), 10 | pending | | |
| G2 | API skeleton (PX-10-T02) | pending | | |
| G2 | First migration + RLS (PX-04-T01/T02) | pending | | |
| G2 | Keycloak realm (PX-01-T01) | pending | | |
| G4 | Sprint 2 acceptance | pending | | |

## Decisions needed today (block S2 tasks)

| Ref | Question | Proposed | Owner | Decision |
|---|---|---|---|---|
| P-1 | Tenant + first EA creation | Operator CLI (ARCHITECTURE §4.6) | Owner + TA | |
| O-11 | Active unit: session vs token | `user_session.active_bu_id` + `X-Device-Id` | Manager / TA | |
| O-12 | Activation and phone-change codes | Keycloak required actions, same authenticator and lock counter; API learns via event listener | Manager / TA | |
| O-13 | Lock state in BU-01 | Keycloak attack-detection admin API | Manager / TA | |
| O-23 | Multi-unit activation, primary unit | Accept all pending invites for the email; primary = oldest invite's unit | You + Divya | |
| P-10 | bu_admin_user_id vs user_unit_role | Role row authoritative; checked by constraint trigger | TA | |
| P-3 | SMS provider | Existing account — confirm DLT sender + OTP template approved | You | |
| — | Email provider | SMTP adapter now (Mailpit); choose SES or SendGrid before a shared environment | TA | |
| — | Sprint Deliverables S2 demo text | Replace "SSO" and "Reviewer role" per the demo script above | You + Suchith | |

## Recently merged (last 5)
- none yet

## Decisions made this wave
- 2026-10-14 — Monorepo; Keycloak-direct sign-in; email + SMS OTP; trunk-based, 80% floor; React + TS; Sonnet build / Opus review; local-only environments; demo on synthetic data stated up front.
- 2026-10-14 — PRD V3 baseline adopted: 3 roles, no Client Portal, no SAML, frozen 31-table model, two approvals per PR (constitution v1.2).

## Open questions (not blocking S2)
- P-4 admin MFA · P-13 WAL-based RPO · P-14 OpenAI US/ZDR evidence · environment procurement (needed by S3–S4).

## Known issues / risks
- **SMS by Oct 20** depends on DLT registration on the existing account. Fallback: email live, SMS to a whitelisted test number.
- **Four working days** (Oct 15, 16, 19, 20) for 37 tasks across 5 people. S-tagged tasks move to S3 first if Friday's check is behind.
- Architect review time on Thu Oct 15 for the three G2 baselines.

## Carry-over from previous wave
- none (S1 was design)

## Notes for the next session
- Specs reference contract numbers (e.g. 1.8); the OpenAPI operation description starts with "Contract ref 1.8".
- Do not build anything marked BLOCKED or OPEN.

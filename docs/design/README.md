# Design canvases

Source of truth for screens and UI behaviour (CONSTITUTION §0). Screen numbers in specs and contracts (EA nn, BU nn, T nn) refer to these.

| Surface | Link |
|---|---|
| Enterprise Admin prototype | https://claude.ai/artifact/UhadGWCbeurJSfb5RNSv3b |
| BU Admin prototype | https://claude.ai/artifact/JytmkLLCrDZsPg6a5DAunb |
| Field Technician app prototype | https://claude.ai/artifact/FQdpCPvPzp4sGhuAi1H8dt |
| Full design canvas (all screens) | https://claude.ai/artifact/4VGjxk93z3Q6wKifeJYj2B |

## Screen ID mapping (decision D-07)

The PRD and specs use 9 dashboard screen IDs (EA-01–04, BU-01–05); the contracts and prototypes use EA 01–73 and BU 01–35. Tasks and PRs cite both, for example "BU-03 (BU 03, 05, 07, 08, 10, 19–23)".

Built from the Screens column of each operation in `docs/api-contracts.md`. A prototype number not listed here is not cited by any contract; add it when a task needs it.

### Enterprise Admin

| PRD screen | Prototype screens | Contract refs |
|---|---|---|
| Sign-in (Keycloak theme) | EA 01–02 | none (Keycloak) |
| App shell: me, unit context, notifications | EA 03, 24 | 1.1, 3.19–3.21 |
| **EA-01** Units overview, create, edit | EA 03, 10, 11, 13–18, 25–28, 67, 70–73 | 1.8–1.17 |
| **EA-02** Locations setup | EA 12, 19 | 2.1–2.8 |
| **EA-03** Scans and escalations | EA 04–09, 20, 29–50, 68 | 3.4–3.5, 3.8–3.9, 3.16–3.18 |
| **EA-04** Audit, export, alerts | EA 21–24, 51–66, 69 | 3.19–3.22, 4.1–4.2 |

### BU Admin

| PRD screen | Prototype screens | Contract refs |
|---|---|---|
| Activation and sign-in | BU 01, 33–35 | 1.6–1.7 (+ Keycloak) |
| App shell: me, unit switcher, notifications | BU 03, 04, 28–30 | 1.1–1.2, 1.12, 3.19–3.21 |
| **BU-01** Staff and invites | BU 25–27 | 1.8–1.11, 1.18–1.19 |
| **BU-02** Equipment type builder | BU 24 | 2.10–2.20 |
| **BU-03** Review queue and decision | BU 03, 05, 07, 08, 10, 19–23 | 3.3–3.7 |
| **BU-04** Delegation console | BU 06, 09, 11, 13–18 | 3.8–3.14 |
| **BU-05** Usage and CSV | BU 12 | 3.23, 4.1–4.2 |
| Audit log (decision D-06) | none yet: new screen, S4 | 3.22, 4.1 |

## Design tokens (from the prototypes)

| Token | Value |
|---|---|
| Fonts | IBM Plex Sans (UI), IBM Plex Mono (IDs, numbers, codes) |
| Accent | `#F07D22` |
| Navy | `#2E3192` |
| Logos | `pixorex-icon.png`, `pixorex-wordmark.png`, `pixorex-wordmark-white.png` in the design canvas (`project/assets/`) |

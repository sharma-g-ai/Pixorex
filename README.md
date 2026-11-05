# Pixorex
Pixorex Scanning Product Repo

## PPG | SeaStock web portal

The 8-screen web portal. This is the main version; a 17-screen version is kept for reference only.

Inventory and consumption tracking for PPG paint and thinners on board vessels.
Basis: *PPG Sea Stock — MVP Business Requirements*, v1.3, and SeaStock Data Models V2.

| Folder | What |
|---|---|
| `web/` | Web portal (React, Vite, Tailwind). **Static screens with sample data**, no API yet. |
| `contracts/` | API contracts (PIX-58), OpenAPI 3.1. |
| `docs/` | Screen list mapped to the BRD, open questions, help guide. |
| `frontend/` | Flutter mobile app, including PPG delivery note and can scanning. |
| `backend/` | Python backend for label extraction. |
| `client_portal_poc/` | Earlier static client portal proof of concept. |
| `supabase/`, `ppg_handoff/`, `documents/`, `output/` | Supabase setup, delivery note handoff, documents and build outputs. |

### Run the web screens

```
cd web
npm install
npm run dev        # http://localhost:5181 (the 17-screen version uses 5180)
```

Checks: `npm run typecheck`, `npm run lint`, `npm test` (renders every screen for every role, and checks the merged screens kept what they took over).

### Sign in

Sign in with e-mail and password; the role decides what opens. Every sample account uses the
password **SeaStock@2026** (static screens only).

| Role | E-mail | Opens |
|---|---|---|
| PPG Admin | dana.whitfield@ppg.example | Overview, all customers, administration |
| PPG Admin | lars.eriksen@ppg.example | Same (sales team) |
| Customer Admin | ingrid.solberg@nordhavn.example | Nordhavn Bulk Carriers only; its vessels, tablets and Customer Admins |
| Customer Admin | sofia.marino@meridian.example | Meridian Container Lines only |
| Disabled account | tom.hughes@ppg.example | Cannot sign in |
| Invited, not set up | nur.aisyah@straits.example | Cannot sign in yet |

Vessels sign in on their tablet (the mobile app), not in the portal, so there are no vessel or crew accounts here.

The BRD does not set the sign-in method (D-11); e-mail and password follow the Pixorex app.

## Sample data

Changes made in the screens (add, edit or import customers, vessels, users and products; pair,
prepare, retire or revoke tablets; adjust stock; match unrecognised scans; close held sync events)
are written to the audit log,
show on every screen and are kept until the browser tab is closed. **Reset sample data** on
the sign-in page brings everything back to the start, e.g. before a demo.

All names, IDs and e-mail addresses are made up (`.example` domains). Product names and
article numbers follow the BRD examples and are placeholders until PPG provides the master
item list (D-02). Imports ignore the file picked and show a sample; a file with "error" in its
name shows a refused customer or vessel file. Sea Stock is worked out from the transactions (opening count + receipts −
consumption ± adjustments), so totals always add up. Times are UTC; "now" is 21 Oct 2026, 16:00.

See [docs/screens.md](docs/screens.md).

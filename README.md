# PPG | SeaStock — compact version

The same portal as `C:\atg\ppg-seastock` (17 screens), merged into **8 screens** with no
repeated data. Both are shown to the team to choose one.

Inventory and consumption tracking for PPG paint and thinners on board vessels.
Basis: *PPG Sea Stock — MVP Business Requirements*, v1.2 (19 Sep 2026).

| Folder | What |
|---|---|
| `web/` | Web portal (React, Vite, Tailwind). **Static screens with sample data**, no API yet. |
| `docs/` | Screen list mapped to the BRD, and open questions. |

The mobile (tablet) app is not in this repo yet.

## Run the web screens

```
cd web
npm install
npm run dev        # http://localhost:5181 (the 17-screen version uses 5180)
```

Checks: `npm run typecheck`, `npm run lint`, `npm test` (renders every screen for every role, and checks the merged screens kept what they took over).

## Sign in

Sign in with e-mail and password; the role decides what opens. Every sample account uses the
password **SeaStock@2026** (static screens only).

| Role | E-mail | Opens |
|---|---|---|
| PPG Admin (all customers) | dana.whitfield@ppg.example | Overview, all customers, administration |
| PPG Admin (EMEA region) | lars.eriksen@ppg.example | Overview, EMEA customers only |
| PPG Admin (chosen customers) | meilin.tan@ppg.example | Overview, Pacific Crest and Straits only |
| Customer Admin | ingrid.solberg@nordhavn.example | Overview, Nordhavn Bulk Carriers only |
| Customer Admin | piotr.nowak@nordhavn.example | Same customer (Procurement) |
| Ship Admin | co.aurora@nordhavn.example | Nordhavn Aurora only |
| Disabled account | tom.hughes@ppg.example | Cannot sign in |
| Invited, not set up | co.endeavour@straits.example | Cannot sign in yet |

The BRD does not set the sign-in method (D-11); e-mail and password follow the Pixorex app.

## Sample data

All names, IDs and e-mail addresses are made up (`.example` domains). Product names and
article numbers follow the BRD examples and are placeholders until PPG provides the master
item list (D-02). Sea Stock is worked out from the transactions (opening count + receipts −
consumption ± adjustments), so totals always add up. Times are UTC; "now" is 21 Oct 2026, 16:00.

See [docs/screens.md](docs/screens.md).

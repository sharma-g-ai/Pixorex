# Web portal screens — compact version

Static screens for the web portal (BRD §7, FR-20 – FR-27), in 8 screens. The 17-screen version is in `C:\atg\ppg-seastock`.

## Screens (compact: 8)

| # | Screen | Path | BRD | Took over from the 17-screen version |
|---|---|---|---|---|
| 1 | Sign in | `/sign-in` | — | — |
| 2 | **Overview**: totals; *Needs attention* (late or no sync, negative stock, unrecognised scans with *Match to article*); recent activity | `/overview` | FR-20, §13, A-07 | Overview, Needs review |
| 3 | **Sea Stock**: by product, vessel, customer or region; pick one vessel to see its details (customer, IMO, tablet, opening stock, last sync); export summary or detail | `/sea-stock`, `?vessel=<id>` | FR-09, FR-20, FR-25 | Sea Stock, Vessel page, Reports (stock) |
| 4 | **Consumption**: by product, vessel, customer or region, any period; export summary or detail | `/consumption` | FR-07, FR-20, FR-25 | Consumption, Vessel page (consumption), Reports (consumption) |
| 5 | **Activity**: tabs *Transactions* (audit trail) and *Delivery notes*; a note's header and tally open in a panel | `/activity`, `?tab=notes`, `?dn=<number>` | FR-01 – FR-05, FR-12, FR-13 | Activity, Receipts, Delivery note, Vessel page (receipts, activity), Reports (receipts) |
| 6 | **Customers & vessels**: tabs *Customers*, *Vessels*, *Regions* | `/admin/customers?tab=` | FR-21, FR-24 | Customers, Vessels, Regions |
| 7 | **Users**: tabs *Users*, *Roles & permissions* | `/admin/users?tab=` | FR-22, FR-23 | Users, Roles & permissions |
| 8 | **Products**: tabs *Master item list*, *Label schema* | `/admin/products?tab=` | FR-26, FR-27 | Master item list, Label schema |

A Ship Admin (Chief Officer) has no Overview: they land on Sea Stock for their own vessel.

### What changed, and why nothing is lost

- **Repeated tables removed from Overview.** "By region" and the vessel list were the same numbers as Sea Stock and Consumption by region and by vessel. Overview keeps the totals and adds what needs attention.
- **Reports folded into Sea Stock and Consumption.** Both already group by vessel, customer and region; each now has *Export summary* (the roll-up) and *Export detail* (every line). Receipts roll-up: the delivery-note export carries region, customer and vessel columns.
- **Vessel page folded into Sea Stock.** Picking one vessel shows its details, with links to its consumption and activity.
- **Receipts folded into Activity.** Every receipt line was already in the transactions; the delivery notes and their tally sit in a second tab.
- **Admin grouped by subject** with tabs; every add, edit, retire, restore, bulk load and publish action is unchanged.

## Roles (FR-23, D-04, D-13)

Three roles, one per level, named as in the reference screens.

| Role | Level | Held by (D-04) | Sees |
|---|---|---|---|
| PPG Admin | PPG | Sea Stock admin; sales team | All customers, or only their regions or chosen customers |
| Customer Admin | Customer | Fleet Manager; Procurement | Own customer's vessels |
| Ship Admin | Vessel | Chief Officer | Own vessel |

Only a PPG Admin with access to all customers manages customers, vessels, users, regions and products.
A PPG Admin limited to regions or customers (sales) views and exports only.

## Left out on purpose (BRD §10)

- Low-stock alerts, thresholds, reorder suggestions: Phase 2 (Smart Locker).
- Liter-level tracking of opened cans, scanning returns: a can that leaves counts as used (A-04).
- Bin or shelf location, pallet scanning, ERP integration, job allocation: not in the MVP.
- Delivery note and label images: not kept (D-07).
- Vessel voyage status (in port, in transit): not in the BRD.

## Open questions for PPG

These are shown on the screens as proposals. Please confirm or correct.

1. **Customer Admin rights.** Can a Customer Admin add and edit their own customer's users? (FR-22 does not say who.) Procurement and Fleet Managers share this role — is that right?
2. **PPG Admin scope.** D-04 says sales are "customer specific"; FR-24 says by region. A PPG Admin can be given all customers, whole regions or chosen customers. Should a limited PPG Admin also run administration? The screens say no.
3. **Geography.** D-05 says not necessary for the MVP, FR-24/25 include it. Screens include it. Can a global customer span regions?
4. **Who reviews negative stock**, and is it only corrected by a stock adjustment on the tablet?
5. **Unrecognised scans.** Held aside until a PPG Admin matches them to an article — confirm.
6. **Pack size vs unit volume** (§8 lists both). Do they ever differ, e.g. a 20 L can holding 16 L of base?
7. **Customer ID and vessel ID formats** in PPG systems (D-03).
8. **Sign-in method:** PPG SSO, e-mail and password, or both (D-11)?
9. **Ship Admin account:** personal (named Chief Officer) or one shared account per vessel, given crew rotation?
10. **Late sync.** Overview lists a vessel as late after 3 days without sync (A-07: every 1–3 days). Confirm the threshold.
11. **Tablet pairing.** How a tablet is tied to its vessel (D-12: one per vessel).

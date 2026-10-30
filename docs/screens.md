# Web portal screens — compact version

Static screens for the web portal (BRD v1.3 §7, FR-20 – FR-26), in 8 screens, following the SeaStock Data Models document (30 Oct). The 17-screen version is in `C:\atg\ppg-seastock` (reference only).

## Screens (compact: 8)

| # | Screen | Path | BRD | Took over from the 17-screen version |
|---|---|---|---|---|
| 1 | Sign in | `/sign-in` | — | — |
| 2 | **Overview**: totals; *Needs attention* (late or no sync, negative stock, unrecognised scans with *Match to article*, held sync events with *Close*, delivery notes with an IMO mismatch); recent activity | `/overview` | FR-20, §13, A-07 | Overview, Needs review |
| 3 | **Sea Stock**: by product, vessel or customer; pick one vessel to see its details (IMO, customer, tablet, receiving mode, opening stock, sign-in, last sync) and *Adjust stock*; export summary or detail | `/sea-stock`, `?vessel=<id>` | FR-09, FR-13, FR-20, FR-24 | Sea Stock, Vessel page, Reports (stock) |
| 4 | **Consumption**: by product, vessel or customer, any period; export summary or detail | `/consumption` | FR-07, FR-20, FR-24 | Consumption, Vessel page (consumption), Reports (consumption) |
| 5 | **Activity**: tabs *Transactions*, *Delivery notes* (with IMO check), *Audit log*; a note's header and tally open in a panel | `/activity`, `?tab=notes\|audit`, `?dn=<number>` | FR-01 – FR-05, FR-12, FR-13 | Activity, Receipts, Delivery note, Vessel page (receipts, activity), Reports (receipts) |
| 6 | **Customers & vessels**: tabs *Customers* (add, edit, import), *Vessels* (add, edit, import, pair tablet, reset password), *Tablets* (retire, revoke) | `/admin/customers?tab=` | FR-21 | Customers, Vessels |
| 7 | **Users**: tabs *Users* (invite, resend, cancel, edit), *Roles & permissions* | `/admin/users?tab=` | FR-22, FR-23 | Users, Roles & permissions |
| 8 | **Products**: tabs *Master item list*, *Label schema* | `/admin/products?tab=` | FR-25, FR-26 | Master item list, Label schema |

Both roles land on the Overview. Vessels sign in on their tablet, not in the portal.

### What changed for BRD v1.3 and the data model

- **No geography.** Regions are gone; roll-up is vessel → customer → PPG (FR-24).
- **Two portal roles.** The vessel is the tablet's user, so there is no vessel account in the portal.
- **The IMO is the vessel ID**, checked with its check digit. The customer ID is the customer code.
- **Tablets** are paired with a one-time enrolment code (72 hours), and can be retired or revoked.
- **Held sync events** (uploads the server could not apply) are listed for an admin to close.
- **Unrecognised scans** are matched by a PPG Admin to an active article; no product + shade fallback (FR-02).
- **Portal stock adjustment** with a required reason (FR-13); never edits an earlier row.
- **Audit log** of every admin and tablet action.

## Roles (FR-22, FR-23, D-04)

| Role | Held by (D-04) | Sees |
|---|---|---|
| PPG Admin | Sea Stock admin; sales team | Every customer and vessel |
| Customer Admin | Fleet Manager; Procurement | Own customer's vessels |

Only a PPG Admin manages customers, adds or edits vessels, matches unrecognised scans, closes held events and maintains products and the label schema.
A Customer Admin imports their own vessels, pairs and revokes their tablets, resets vessel passwords, adjusts stock and invites their own customer's Customer Admins.

## Left out on purpose (BRD §10)

- Low-stock alerts, thresholds, reorder suggestions: Phase 2 (Smart Locker).
- Liter-level tracking of opened cans, scanning returns: a can that leaves counts as used (A-04).
- Periodic stock-taking, bin or shelf location, pallet scanning, ERP integration, job allocation: not in the MVP.
- Delivery note and label images: not kept (D-07).
- Product + shade fallback for unreadable article numbers: post-MVP (FR-02, A-02).

## Open questions for PPG

These are shown on the screens as proposals. Please confirm or correct.

1. **Vessel Admin.** FR-22/23 name a Vessel Admin; the data model makes the vessel the tablet's user with no portal account. Confirm.
2. **Customer Admin rights.** Adjust stock, invite their own Customer Admins, pair and revoke tablets, see their own audit log — confirm each.
3. **Who closes held sync events** and who adjusts stock from the portal.
4. **Vessel password**: the rule, and who gives it to the crew at crew change.
5. **Pack size vs unit volume** (§8 lists both). Do they ever differ?
6. **Sign-in method:** PPG SSO, e-mail and password, or both (D-11)?
7. **Late sync.** Overview lists a vessel as late after 3 days without sync (A-07: every 1–3 days). Confirm the threshold.

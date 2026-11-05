# Web portal screens — compact version

Static screens for the web portal (BRD v1.3 §7, FR-20 – FR-26), in 8 screens, following SeaStock Data Models V2 (16 tables, with the data model review of 2 Nov). The 17-screen version is in `C:\atg\ppg-seastock` (reference only).

## Screens (compact: 8)

| # | Screen | Path | BRD | Took over from the 17-screen version |
|---|---|---|---|---|
| 1 | Sign in | `/sign-in` | — | — |
| 2 | **Overview**: totals; *Needs attention* (late or no sync, negative stock, unrecognised scans with *Match to article*, held sync events with *Close*, delivery notes with an IMO mismatch); recent activity | `/overview` | FR-20, §13, A-07 | Overview, Needs review |
| 3 | **Sea Stock**: by product, vessel or customer; pick one vessel to see its details (IMO, customer, tablet, receiving mode, opening stock, sign-in, last sync) and *Adjust stock*; export summary or detail | `/sea-stock`, `?vessel=<id>` | FR-09, FR-13, FR-20, FR-24 | Sea Stock, Vessel page, Reports (stock) |
| 4 | **Consumption**: by product, vessel or customer, any period, with the last sync; filter by component type or search; export summary or detail | `/consumption` | FR-07, FR-20, FR-24 | Consumption, Vessel page (consumption), Reports (consumption) |
| 5 | **Activity**: tabs *Transactions*, *Delivery notes* (with IMO check), *Audit log*; a note's header and tally open in a panel | `/activity`, `?tab=notes\|audit`, `?dn=<number>` | FR-01 – FR-05, FR-12, FR-13 | Activity, Receipts, Delivery note, Vessel page (receipts, activity), Reports (receipts) |
| 6 | **Customers & vessels**: tabs *Customers* (add, edit, import), *Vessels* (add, edit, import, pair tablet, reset password), *Tablets* (prepare to retire, retire now, revoke) | `/admin/customers?tab=` | FR-21 | Customers, Vessels |
| 7 | **Users**: tabs *Users* (invite, resend, cancel, edit), *Roles & permissions* | `/admin/users?tab=` | FR-22, FR-23 | Users, Roles & permissions |
| 8 | **Products**: the master item list | `/admin/products` | FR-25 | Master item list |

Both roles land on the Overview. Vessels sign in on their tablet, not in the portal.

### What changed for BRD v1.3 and the data model

- **No geography.** Regions are gone; roll-up is vessel → customer → PPG (FR-24).
- **Two portal roles.** The vessel is the tablet's user, so there is no vessel account in the portal.
- **The IMO is the vessel ID**, checked with its check digit. The customer ID is the customer code.
- **Tablets** are paired with a one-time enrolment code (72 hours), shown once as a QR and as text; both are the same code. A vessel has one active tablet: to replace a working one, prepare it to retire, it uploads at its next sync and retires, and only then can the new tablet enrol. A broken or lost tablet is retired at once. Replacing a tablet at enrolment is gone.
- **Customer and vessel imports** are all-or-nothing: one bad row refuses the whole file and names the row.
- **A vessel's customer** cannot be changed in the MVP.
- **Articles are never retired or deleted**: the master list only grows, and a scan can be matched to any article on it.
- **The label schema is deferred past the pilot** (FR-26): the tablet reads labels by article number only.
- **Held sync events** (uploads the server could not apply) are listed for an admin to close.
- **Unrecognised scans** are matched by a PPG Admin to an active article; no product + shade fallback (FR-02).
- **Delivery notes to check**: every note whose IMO is not a match, so a mismatch or an IMO not read.
- **Portal stock adjustment** with a required reason (FR-13); never edits an earlier row.
- **Audit log** of every admin and tablet action.

## Roles (FR-22, FR-23, D-04)

| Role | Held by (D-04) | Sees |
|---|---|---|
| PPG Admin | Sea Stock admin; sales team | Every customer and vessel |
| Customer Admin | Fleet Manager; Procurement | Own customer's vessels |

Only a PPG Admin manages customers, adds or edits vessels, matches unrecognised scans, closes held events and maintains products.
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
8. **BRD v1.4.** Data Models V2 says articles are no longer retired (FR-25 says "additions and retirements") and the label schema is deferred (FR-26). The screens follow V2; both should be recorded in the BRD.
9. **Wrong IMO on a delivery note.** The review proposed stopping the note on the server and showing it to the Customer Admin. Today it is accepted and flagged; the handling is to be decided.
10. **Invite expiry.** No period is stated; the screens propose 7 days.
11. **Editing an article.** The master list is maintained (FR-25) but no document says what can be edited, so the screens offer add and bulk load only.
12. **Inactive vessels and customers.** Should an inactive vessel stay in Late or no sync (it does), and should an inactive customer's admin still sign in (they can)?

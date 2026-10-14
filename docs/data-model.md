# **Pixorex V3 — Data Models**

Oct 13, 2026 · @vishnu

The Pixorex V3 data model has 31 PostgreSQL tables in 6 domains. It matches the Enterprise Admin, BU Admin and Technician screens of 13 Oct and the team decisions of the same day.

## **Overview**

Everything hangs off tenant and business\_unit; a scan is the centre of the model, tagged on one location, pinned to one extraction contract, and reviewed through revisions. Columns are omitted here; each domain section has its full diagram. Every tenant-owned table also carries tenant\_id, created\_at and updated\_at. Foreign keys between tenant-owned tables include tenant\_id (for example, user\_unit\_role (tenant\_id, user\_id) references app\_user (tenant\_id, id)), so a row can never link to a row in another tenant (US-024).

![Overview ER diagram of all Pixorex domains][image1]

| Domain | Tables |
| :---- | :---- |
| 1\. Tenancy, users and sign-in | 7 |
| 2\. Locations | 3 |
| 3\. Equipment types and extraction contracts | 5 |
| 4\. Scans, photos and extraction | 4 |
| 5\. Review, delegation and escalation | 6 |
| 6\. Audit, notifications, exports, quota, retention | 6 |
| Total | 31 |

## **Domain 1: Tenancy, users and sign-in (7 tables)**

A user account is separate from its unit assignments: one app\_user holds one user\_unit\_role row per unit, so removing someone from Plant 04 keeps the account and Plant 07\. Sign-in codes and lockout live in Keycloak; this domain holds only who may act where.

![ER diagram: tenancy, users and sign-in][image2]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| tenant | The customer company (PPG Industries) and its package | Not tenant-scoped itself; root of every RLS policy. tenant.name is the read-only Customer header in the mobile location picker | EA Overview, mobile location picker |
| business\_unit | A plant or division (PPG Plant 04 — Coatings) | bu\_admin\_user\_id nullable: null \= "No BU Admin". Its scans that wait over 24 hours go to the Enterprise Admin, and a unit\_no\_bu\_admin alert is sent | Create unit, Overview, Units without a BU Admin |
| business\_process | BRD process level (US-024) | One is\_default \= true row seeded per unit, so the UI needs no process picker | Not shown in UI |
| app\_user | One person; link to Keycloak | status: invited, active, removed. email unique per tenant. phone\_number (E.164) unique; a technician must verify one before activation, admins have none. last\_bu\_id \= unit opened at next sign-in. last\_active\_at feeds "Last active" | Activate, Sign in, Profile, Technicians, BU Admins |
| user\_unit\_role | Role of a user in one unit | role: enterprise\_admin (bu\_id null), bu\_admin, field\_technician. One active bu\_admin per unit (partial unique index). is\_trusted\_reviewer marks who can get delegated batches. is\_primary (one per user) and assigned\_by | Switch unit, Edit units, Activate "Primary" and "Assigned by" |
| invite | Magic-link invite for a BU Admin or technician | expires\_at \= sent \+ 24 h; single use; only a token hash is stored. A multi-unit invite \= one row per unit with the same hash. status: pending, accepted, expired, cancelled. A technician confirms name and mobile number and verifies the number with a texted code; a BU Admin verifies the email with a code. No passwords | Invite BU Admin, Invite technician, Activate, Invite expired |
| user\_session | Which unit the user is working in, per device | active\_bu\_id changes on Switch unit without a new sign-in and updates app\_user.last\_bu\_id. revoked\_at is set on removal and, for every other device, on a phone change; the API checks it within 60 s (US-051) | Profile, Switch unit, Sign out, Mobile number changed |

Sign-in uses a one-time code: technicians choose text message or email, admins use email. Keycloak counts wrong codes per account across both channels; on the 5th it locks sign-in for 30 minutes and unlocks it on its own, and nobody approves an unlock. Every lock writes an audit\_log row (sign\_in). A phone change saves the new number only after the code sent to it is verified (5 wrong codes lock changes for 30 minutes), signs out the other devices, writes a users audit row and emails the user.

## **Domain 2: Locations (3 tables)**

Locations are one self-referencing tree per unit, managed only by the Enterprise Admin. The EA chooses the levels, builds the tree and can add, rename, move or delete anything until the unit is published. Publishing freezes the tree snapshot, and from then on the unit's levels and locations are locked: nothing is added, edited or deleted. Adding locations after publishing is a later feature; the version table is kept so it can be added without a schema change.

![ER diagram: locations][image3]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| location\_hierarchy\_version | A unit's location setup and its published snapshot | One row per unit (unique bu\_id); version\_no \= 1\. status: not\_published, published. tree\_snapshot \= the full tree as JSON, frozen at publish; the phone caches it | Locations editor, Review & publish, mobile picker |
| location\_level\_rule | One level the EA defines (for example Facility, Building, Shop, Bin, Sub-bin) | level\_name, level\_order (1 \= top), requirement: required, optional, off. Top level always required. Unique (version\_id, level\_order). Locked at publish | Levels, mobile picker |
| location\_node | One place at one level | parent\_id \= same table; path \= materialised ID path; level\_rule\_id; is\_placeholder. Name unique among siblings. A trigger blocks INSERT, UPDATE and DELETE once the unit is published | Tree editor, Create the skeleton, mobile picker |

The mobile picker shows tenant.name (PPG Industries) as a read-only Customer header above the levels; it is not a level and not a step. scan.location\_path\_snapshot keeps the full path as it was at capture.

## **Domain 3: Equipment types and extraction contracts (5 tables)**

An equipment type is built while it is not published: the BU Admin adds, edits, reorders and deletes fields, then publishes. Publishing locks the type, with no renaming, no field changes and no deleting; for something different the BU Admin creates a new type, from blank, as a copy or with AI-assist. Each type has one version (version 1\) that holds its fields; editing a published type is a later feature, and the version table is kept so it can be added without a schema change, the same as locations. Publishing also creates the extraction contract that binds the type's fields to one prompt version, and every scan pins one contract, so the AI always runs the exact fields and prompt the technician picked (US-018, US-022).

![ER diagram: equipment types and extraction contracts][image4]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| equipment\_type | A kind of label a unit can scan (Motor Nameplate, Control Valve) | Owned by one unit; process\_id \= the unit's default process. Name unique per unit. status: not\_published, published. Only a not-published type can be renamed, edited or deleted. created\_via: blank, copy, ai\_assist; copied\_from\_type\_id | Equipment types, Publish, New type, AI-assist, mobile type picker |
| equipment\_type\_version | The field list of a type, frozen at publish | One row per type for now (unique equipment\_type\_id); version\_no \= 1\. published\_by, published\_at. Fields and the extraction contract link here. A later "edit published type" adds version 2 without touching old scans | Not shown in UI |
| field\_definition | One field of a type version | type\_version\_id, field\_key, label, sort\_order. data\_type: text, number, date, dropdown, boolean (Yes / No); options holds 2 or more choices for a dropdown (check constraint). is\_required, is\_critical, format\_rule, is\_unique\_in\_unit, flag\_below\_confidence default 0.85. origin: manual, ai\_suggested. Read-only once the type is published (trigger) | Add field, Choices, Preview as technician |
| prompt\_version | Platform-owned AI instructions and model name | Global (no tenant), managed by Amzur; never edited after use; never contains client data | Not shown in UI |
| extraction\_contract | Frozen pair: one published type version \+ one prompt version | Created when the type is published; a new prompt version adds a new contract, never a silent change. Unique (type\_version\_id, prompt\_version\_id). status: active, blocked, retired. A blocked contract stops new attempts | Not shown in UI; drives AI calls |

For a dropdown field the AI value must match one of the choices, or it is flagged format\_failed. A boolean field stores true / false in values\_json. is\_unique\_in\_unit compares the value with the unit's other scans of that type.

## **Domain 4: Scans, photos and extraction (4 tables)**

A scan is created once, from an ID the phone generates offline, and is never duplicated by retries. It carries two separate statuses: processing (upload and AI) and review (business approval) (US-011, US-045). A scan gets at most 3 extraction attempts in total, whether they are retries or re-extracts with another type.

![ER diagram: scans, photos and extraction][image5]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| scan | One capture of one piece of equipment (REC-90141) | client\_capture\_id unique per tenant: a repeated upload returns the existing scan. bu\_id \= unit active when captured. equipment\_type\_id and contract\_id change only on a re-extract. location\_node\_id and location\_path\_snapshot \= the place at capture time. retake\_of\_scan\_id links a retake to the closed original | Home, My Scans, Queue, Review queue, Scans (EA) |
| scan\_photo | 1 to 4 photos of a scan | photo\_no between 1 and 4; unique (scan\_id, photo\_no). Bytes in MinIO at /{tenant}/{bu}/{scan}/{photo\_no}; only the key and SHA-256 are stored. Image-quality numbers stay on the phone | Add photo 2 of 4, Photo limit |
| extraction\_attempt | One call through the AI Inference Proxy | Unique (scan\_id, attempt\_no); attempt\_no 1 to 3 per scan across all types, then retake only. trigger: first, retry, re\_extract. contract\_id \= the contract this attempt used. status: queued, running, succeeded, failed, timed\_out. detected\_label, suggested\_type\_id and suggestion\_confidence drive the Type mismatch screen. Tokens and cost for billing (US-018b) | Analyzing, Retry extraction, Type mismatch, Re-extract |
| ai\_field\_value | The AI's answer for one field, never edited | confidence null when the model gives no score. flag\_reasons: low\_confidence, format\_failed, no\_confidence, missing\_required, critical\_not\_found. Insert-only | Review flagged fields |

Status columns on scan:

* processing\_status: queued\_on\_phone (phone only), uploading, extracting, ready\_to\_review, failed, retake\_required.  
* review\_status: draft, waiting\_for\_approval, approved, rejected, closed (replaced by a retake), discarded.

## **Domain 5: Review, delegation and escalation (6 tables)**

Every technician check creates an immutable revision, and every approve or reject is a decision on one exact revision. Delegation, reassignment, take-back, override and 24 h escalation are rows, not overwritten statuses, so the audit trail stays complete.

![ER diagram: review, delegation and escalation][image6]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| revision | A frozen set of values a technician sends for approval | origin: technician\_review, rejection\_fix. Insert-only. values\_json \= final values by field\_key. Only the scan's own technician can create one. It can be sent with required fields still empty (Submit anyway); empty\_required\_fields lists them for the reviewer. resubmit\_to\_user\_id \= the reviewer a fixed scan goes back to | Submit for review, Submit anyway, Resubmit |
| revision\_field | The technician's verdict on one field | verification\_state: accepted, corrected, unreadable, left\_empty. unreadable\_reason: label\_worn, not\_on\_nameplate, covered\_or\_unreachable, other (+ note). ai\_field\_value\_id links to the untouched AI value | Review flagged fields, Mark unreadable |
| review\_decision | One approve or reject on one revision | decider\_role: bu\_admin, enterprise\_admin, delegated\_technician. reject\_category: image\_unclear, data\_correction\_needed, wrong\_equipment\_type, other. decided\_by ≠ scan's technician (trigger). One is\_current per revision \= first decider wins. Override inserts a new row with overrides\_decision\_id | Approve / Reject, Override, Decision changed |
| review\_batch | A delegated batch (B-15) given to one trusted technician | 1 to 50 scans; created\_by \= BU Admin or EA; assigned\_to \= one technician. status: active, completed, taken\_back. Scans the technician captured are left out. Reassign changes assigned\_to, closes the old assignment rows (reason reassigned) and writes an audit row. reminded\_at for Send reminder; optional take\_back\_message. alert\_1d\_at and alert\_1w\_at stop repeat alerts | Delegate scans, Delegations, Reassign, Take back, Send reminder |
| review\_assignment | One scan inside a batch | status: assigned, decided, removed. removed\_reason: taken\_back, reassigned, admin\_decided, user\_removed. One assigned row per scan at a time | Review batch (mobile) |
| escalation | A scan handed to the Enterprise Admin | reason: not\_approved\_24h, no\_bu\_admin. The scheduled job creates both once a scan has waited 24 hours. reminded\_at is set when the EA presses Remind. Resolved by the first decision; the BU Admin still sees the scan | EA Escalated scans, Remind, Units without a BU Admin |

## **Domain 6: Audit, notifications, exports, quota, retention (6 tables)**

These tables support the main flow and point at users and units, referring to other objects by type and ID. The audit log is insert-only, partitioned by month, kept 1 year online and 3 years archived (US-044, US-046).

![ER diagram: audit, notifications, exports, quota, retention][image7]

| Table | Purpose | Key rules | Screens |
| :---- | :---- | :---- | :---- |
| audit\_log | Who did what, when, in which unit | Partitioned by month on occurred\_at. INSERT only; no UPDATE or DELETE grant for any role. actor\_type: user, system. category: sign\_in, users, locations, equipment\_types, review, override, escalation, export, retention | Audit log and its filters, Audit export |
| notification | One alert to one admin or technician | Bell panel and email (no push). kind (17): scan\_waiting\_1d, scan\_waiting\_1w, scans\_escalated, unit\_no\_bu\_admin, escalation\_reminder, batch\_delegated, batch\_no\_progress, batch\_reminder, batch\_reassigned, batch\_taken\_back, scan\_removed\_from\_batch, scan\_approved, scan\_rejected, decision\_overridden, ea\_delegated\_in\_unit, invite\_expired, export\_ready | Notifications panel, home cards |
| export\_job | A CSV export request | export\_kind: scans, audit\_log. filters\_json \= unit, status, dates; options\_json \= columns and photo links. Up to 1,000 rows in the request; above that queued → ready, file in MinIO, link valid 1 h, export\_ready alert. Every job writes an audit row | Export CSV, Audit export |
| quota\_usage | Scans used per unit per month | Unique (bu\_id, period\_month). alert\_level\_sent (0, 80, 95, 100\) prevents duplicate alerts | None yet |
| retention\_config | How long each kind of data is kept | Columns as BRD US-046b. bu\_id null \= tenant default. API rejects values below the floor (HTTP 400\) | None yet |
| outbox\_event | Work to run after a transaction commits | Written in the same transaction as the change and its audit row. A worker sends emails and text messages, calls the AI proxy, builds exports, retries with backoff. status: pending, done, failed | Not shown in UI |

## **Scan status lifecycle**

The API decides every status change; any move not drawn below is refused with HTTP 409\. The diagram combines the scan's processing states (up to ready\_to\_review) and review states (from waiting\_for\_approval), stored in two separate columns. A retry and a re-extract both need an attempt left of the scan's 3\.

![Scan status lifecycle][image8]

My Scans tabs map onto these states: Needs action \= ready\_to\_review, rejected, failed, retake\_required; In progress \= queued\_on\_phone, uploading, extracting, waiting\_for\_approval; Approved \= approved.
[image1]: data-model/00-overview.png
[image2]: data-model/01-tenancy-users-and-sign-in.png
[image3]: data-model/02-locations.png
[image4]: data-model/03-equipment-types-and-extraction-contracts.png
[image5]: data-model/04-scans-photos-and-extraction.png
[image6]: data-model/05-review-delegation-and-escalation.png
[image7]: data-model/06-audit-notifications-exports-quota-retention.png
[image8]: data-model/07-scan-status-lifecycle.png

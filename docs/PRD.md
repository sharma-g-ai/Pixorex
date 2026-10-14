# **Pixorex PRD V3 — V1 Baselined**

Oct 13, 2026 

## **Purpose and precedence**

This PRD defines what Pixorex V1 builds. It is derived from the frozen V3 logical data model (31 tables, 6 domains) and from the V1 scope decisions in the owner's 13 Oct 2026 addendum to the BRD.

**Source documents**

* [Pixorex\_BRD\_v2.1](https://docs.google.com/document/d/1W4UGpmCxTGTQSGMOeX30qY6RALwT_4k4XZ07pPp1fnE/edit), including the "V3 V1 Owner-Approved Scope and Model Alignment Addendum" (13 Oct 2026).  
* [Pixorex V3 — Data Models](https://docs.google.com/document/d/1lRZFwczFVEezkif5LOlWW4xI3-7onePz2EX9l339J4o/edit) (13 Oct 2026, @vishnu). The implementation PRD, Pixorex\_PRD\_V3\_V1\_Baselined.docx, was merged in later on 13 Oct for the journeys, screens, permissions matrix and release tests.

**Order of precedence when sources disagree**

1. The 13 Oct addendum. For V1 it overrides any incompatible V2.1 user-story text.  
2. The V3 Data Models document, for tables, columns, keys, triggers and status values.  
3. The V2.1 BRD body, for everything the first two do not change (security, residency, NFRs, DevSecOps).

**What this PRD does not do**

* It does not change the data model, add a 32nd table, or claim a physical schema is deployed or frozen in a database.  
* It does not certify readiness. Engineering still has to validate DDL, API authorization, concurrency, provider and region security, retention execution, device QA, RPO/RTO and release gates.  
* It does not restate columns. Column-level definitions stay in the per-domain diagrams of the Data Models document.  
* It does not carry story-point estimates. The V2.1 totals (245 SP) predate the addendum and must be rebaselined.

## **V1 scope**

V1 lets a field technician photograph an equipment nameplate, get an AI extraction, verify and correct it, and have a different person approve the exact revision — inside a tenant, business unit (BU) and location structure that admins configure first.

**In V1**

* Three primary roles: Enterprise Admin (EA), BU Admin, Field Technician. is\_trusted\_reviewer is a delegated capability, not a fourth role.  
* Keycloak sign-in by one-time code: technicians by SMS or email, admins by email. No passwords.  
* One hidden default Business Process per BU; there is no process picker.  
* Locations: the EA defines levels and builds the node tree for each BU; publishing freezes both.  
* Equipment types: the BU Admin builds a type from blank, copy or AI-assisted draft; publishing freezes its single version and binds it to a prompt version in an extraction contract.  
* Mobile capture of 1–4 photos, offline-first, with a phone-generated client\_capture\_id that makes retries safe.  
* AI extraction through the AI Inference Proxy, at most 3 attempts per scan.  
* Technician verification (accepted, corrected, unreadable, left empty) recorded as immutable revisions, including Submit Anyway.  
* Review: approve or reject one exact revision, delegated review batches of 1–50 scans, override, and 24-hour escalation to the EA.  
* Monthly unique-scan quota per BU, bell and email notifications, scoped CSV export of scans and the audit log.  
* Non-schema obligations: append-only audit, outbox-driven external effects, retention floors, private MinIO storage, security controls and US data residency.

**What "approved" means in V1.** An approved scan, its exact revision and its effective review decision together are the reviewed record. There is no separate GovernedRecord, Publication or Client Portal projection.

Post-V1 items are listed after the requirements.

## **Users and roles**

V1 has three roles plus one delegated capability. A person is one app\_user; each unit they work in is a separate user\_unit\_role row, so removing someone from one unit keeps their account and their other units.

| Role | Scope | What they do in V1 | Limits |
| :---- | :---- | :---- | :---- |
| Enterprise Admin (enterprise\_admin) | Whole tenant (bu\_id null) | Creates units, defines location levels and builds the node tree, publishes a unit's locations, handles escalated scans, reads scans and the audit log, exports CSV | Edits no unit's locations after publish; no aggregate cross-BU reporting |
| BU Admin (bu\_admin) | One unit; one active BU Admin per unit | Creates and publishes equipment types, manages the unit's technicians, approves or rejects scans, delegates review batches to trusted technicians, reassigns, reminds and takes back batches | Cannot edit a published equipment type |
| Field Technician (field\_technician) | One or more units | Captures scans, verifies each field, submits a revision for review, reworks rejected scans | Cannot decide their own scans |
| Delegated reviewer | A technician with is\_trusted\_reviewer | Decides scans in a review batch assigned to them | Only another person's exact submitted revision; scans they captured are left out of their batch |

**Account and session rules**

* app\_user.status is invited, active or removed. Email is unique per tenant; a technician must verify an E.164 phone number (unique) before activation, admins have none.  
* Each user has one is\_primary unit; user\_session.active\_bu\_id records the unit they are working in per device, and switching units needs no new sign-in.  
* Removing a user, or changing a technician's phone, sets user\_session.revoked\_at; the API must deny a revoked session within 60 seconds.  
* Sign-in codes, wrong-code counting and lockout live in Keycloak, not in these tables. The 5th wrong code locks sign-in for 30 minutes; it unlocks on its own and no one approves it. Every lock writes an audit\_log row (sign\_in).

## **Frozen data model**

The V1 data model is the V3 logical model published 13 Oct 2026: 31 PostgreSQL tables in 6 domains. It is frozen, so V1 features are built on it and not the other way round. The scan is its centre: tagged to one location, pinned to one extraction contract, and reviewed through revisions.

| Domain | Tables | What the domain holds |
| :---- | :---- | :---- |
| 1\. Tenancy, users and sign-in (7) | tenant, business\_unit, business\_process, app\_user, user\_unit\_role, invite, user\_session | The customer, its units, who may act where, invitations and per-device unit context |
| 2\. Locations (3) | location\_hierarchy\_version, location\_level\_rule, location\_node | One self-referencing location tree per unit and its frozen snapshot |
| 3\. Equipment types and extraction contracts (5) | equipment\_type, equipment\_type\_version, field\_definition, prompt\_version, extraction\_contract | Label types, their fields, platform prompts, and the frozen type-plus-prompt pair each scan pins |
| 4\. Scans, photos and extraction (4) | scan, scan\_photo, extraction\_attempt, ai\_field\_value | One capture, its 1–4 photos, each AI call, and the untouched AI answer per field |
| 5\. Review, delegation and escalation (6) | revision, revision\_field, review\_decision, review\_batch, review\_assignment, escalation | Technician revisions, field verdicts, decisions, delegated batches and 24-hour escalations |
| 6\. Audit, notifications, exports, quota, retention (6) | audit\_log, notification, export\_job, quota\_usage, retention\_config, outbox\_event | Append-only history, alerts, CSV jobs, monthly quota, retention settings and post-commit work |

**Invariants the build must preserve**

* Every tenant-owned table carries tenant\_id, created\_at and updated\_at. Foreign keys between tenant-owned tables include tenant\_id, so a row cannot link into another tenant. tenant and the global prompt\_version are the exceptions.  
* Insert-only tables: ai\_field\_value, revision, audit\_log. The audit log is partitioned by month and no role holds UPDATE or DELETE on it.  
* Database triggers enforce freezing and separation of duties: location\_node accepts no INSERT, UPDATE or DELETE once its unit is published; field\_definition is read-only once its type is published; review\_decision.decided\_by can never be the scan's technician.  
* Uniqueness rules: client\_capture\_id per tenant; (scan\_id, attempt\_no) with attempt\_no 1–3; (scan\_id, photo\_no) with photo\_no 1–4; one current review\_decision per revision; one assigned review\_assignment per scan; one active BU Admin per unit; one default business\_process per unit; one extraction contract per (type\_version\_id, prompt\_version\_id); one quota\_usage row per (bu\_id, period\_month).  
* A scan carries two independent statuses, processing\_status and review\_status. The API decides every change; a move not in the lifecycle is refused with HTTP 409\.  
* location\_hierarchy\_version and equipment\_type\_version hold version 1 only in V1. They exist so post-publish editing can be added later without a schema change.

**Proposed change control**

* No table is added, removed or renamed, and no column changes meaning, for V1.  
* Indexes, partitions, seed data and the DDL that implements the rules above need no change request.  
* Anything else goes to the owner and the Technical Architect as a written change request before engineering starts it.

## **Lifecycles and core workflows**

A scan carries two independent statuses: processing (upload and AI) and review (business approval). Processing progress is never confused with technician submission or reviewer approval.

| Status column | Values |
| :---- | :---- |
| scan.processing\_status | queued\_on\_phone (phone only), uploading, extracting, ready\_to\_review, failed, retake\_required |
| scan.review\_status | draft, waiting\_for\_approval, approved, rejected, closed (replaced by a retake), discarded |

The mobile My Scans tabs group these states: Needs action \= ready\_to\_review, rejected, failed, retake\_required; In progress \= queued\_on\_phone, uploading, extracting, waiting\_for\_approval; Approved \= approved.

**End-to-end workflow**

1. **Setup.** Units, locations and equipment types are configured and published before the first scan. Users join by single-use magic-link invite (24 hours) and activate by verifying their phone or email with a code.  
2. **Capture.** The technician picks the equipment type and location, takes 1–4 photos and confirms the quality preview. The phone creates client\_capture\_id and queues the scan locally. A repeated upload returns the existing scan. The scan records its location node, a location path snapshot and its pinned extraction contract.  
3. **Extraction.** The AI Inference Proxy runs the pinned contract and writes an extraction\_attempt plus one ai\_field\_value per field. A scan gets at most 3 attempts in total, whether retries or re-extracts with another type. A type mismatch may suggest another permitted type; the technician approves the change explicitly. Once attempts are exhausted the scan is retake\_required and needs a new linked physical retake, which closes the original.  
4. **Verification.** The technician records a verdict for each field: accepted, corrected, unreadable (with a reason) or left empty. Submit for Review creates an immutable revision. Submit Anyway sends it with required fields still empty, and lists them for the reviewer.  
5. **Review.** A BU Admin, an EA or a currently delegated trusted reviewer approves or rejects another person's exact submitted revision. The first valid decision wins; an override appends a new linked decision row. A rejection carries a category (image unclear, data correction needed, wrong equipment type, other) and sends the scan back to the technician. The fix becomes a new rejection\_fix revision, resubmitted to the named reviewer.  
6. **Delegation.** A BU Admin or EA assigns a review batch of 1–50 scans to one trusted technician. A batch is a set of review assignments, not bulk approval. Reassign, remind and take back are rows and audit entries, never overwritten statuses.  
7. **Escalation.** A scheduled job escalates a scan to the EA once it has waited 24 hours. The reason is no\_bu\_admin when its unit has no BU Admin, and not\_approved\_24h otherwise. The first decision resolves the escalation; the BU Admin still sees the scan.

The full transition diagram is in the Data Models document and is authoritative for which moves are legal.

## **Operational journeys**

Eight journeys cover V1 from setup to audit. Each row names the actor, the key steps and the rule an implementer is most likely to get wrong. The step detail is from the implementation PRD (Pixorex\_PRD\_V3\_V1\_Baselined.docx); the functional requirements below carry the table mapping.

| Journey | Actor | Key steps | Rule to preserve |
| :---- | :---- | :---- | :---- |
| J01 Configure a BU | EA | Create the unit (default process seeded, BU Admin may be vacant). Choose location levels, build nodes, preview, publish. | The publish screen shows an explicit irreversible warning: no node or level changes after publish in V1. The mobile app then fetches and caches the frozen tree. |
| J02 Invite, sign in, switch unit | EA, BU Admin, technician | Single-use hashed invite (24 hours). Technician verifies phone, then signs in by SMS or email code; admin by email code. Home opens the last authorised unit; switching changes active\_bu\_id without a new login. | Five wrong codes lock sign-in for 30 minutes. Access removal revokes sessions; a verified phone change signs out other devices. |
| J03 Create and publish an equipment type | BU Admin | Start blank, as a copy, or from a reference image (AI suggests a draft only). Configure fields, validate prompt and field policy, preview, publish. | Publish freezes version 1 and binds the prompt in extraction\_contract. To change fields, create a new type and select it deliberately in later captures. |
| J04 Capture and offline acceptance | Technician | Pick unit, published type and published location (last-used proposed only if still valid). Take 1–4 photos, retake or confirm. Persist client\_capture\_id, checksums, location snapshot and contract together on the device. | Nothing is transmitted before image confirmation. Offline shows queued\_on\_phone with a count; on reconnect the same identity is retried and the server returns an ACK without waiting for AI. |
| J05 AI attempt, mismatch, retry, retake | Technician, system | Attempt 1 runs the scan's contract. Results become immutable ai\_field\_value rows; confidence is NULL if unsupported. A mismatch suggests another permitted type; the technician decides. | Retries and re-extracts share a budget of 3 attempts. When it is spent, a new linked physical retake is the only path. |
| J06 Technician review and submit | Technician | In My Scans, open the stored photos and each AI field; mark accepted, corrected, unreadable (with reason) or left empty. Submit for review writes a revision and its revision\_field rows. | Submit Anyway lists missing required fields and never auto-approves. A rejected revision is kept; the rework is a new revision. |
| J07 Review, delegation, escalation | BU Admin, EA, trusted technician | Reviewer sees the exact revision, machine value and technician verdict. Admin delegates a batch of 1–50 scans (own captures excluded); reassign and take back close old assignments. After 24 hours a scan escalates to the EA. | First valid decision wins; an override appends a linked decision row. Mandatory fields must be resolved before approval, otherwise reject for rework. |
| J08 Search, export, audit, retention | EA, BU Admin | Filter scans and audit within authorised scope. CSV up to 1,000 rows is immediate, above that queued with a 1-hour private link. Daily retention job runs. | Every export is DLP-checked and audited. The audit row and outbox intent commit in the same transaction as the change. Signed image access is separately authorised, 15-minute TTL. |

## **Screens**

V1 has 16 screens across the EA dashboard, BU Admin dashboard and technician mobile app. There is no portal route and no process selector anywhere.

| ID | Screen | Visible data and actions | Critical constraint |
| :---- | :---- | :---- | :---- |
| EA-01 | Units overview, create, edit | Unit name and status, BU Admin or vacant, user and scan counts, recent escalation; create unit, assign or revoke admin | No cross-tenant assignment; warn on vacancy; other unit roles stay intact |
| EA-02 | Locations setup | Customer read-only header, level rules, nodes, hierarchy preview, publish confirmation | No reopening after publish (read-only snapshot); block invalid parent, cycle and duplicate sibling |
| EA-03 | Scans and escalations | Authorised units only, 24-hour and no-admin escalations, scan detail, remind, decide | Decided or expired escalation not actionable; losing a first-decision race returns a conflict |
| EA-04 | Audit, export, alerts | Category, time and unit filters, append-only event view, CSV export, notification bell | Exports recheck scope and DLP; no portal access |
| BU-01 | Staff and invites | Users, unit role, verified phone, status, pending and expired invites, primary and trusted flags | One active BU Admin; no revoking another unit; expired invite must be recreated |
| BU-02 | Equipment type builder | Type list, create blank, copy or AI assist, fields, required and critical flags, dropdown options, preview, publish | AI draft needs human validation; no edit of a published type or its fields |
| BU-03 | Review queue and decision | Submitted revision, photos, raw AI value, technician verdict, flags, missing fields, approve or reject | Own scan cannot be approved; missing mandatory field blocks approval; a race shows 409 and current state |
| BU-04 | Delegation console | Trusted reviewer, eligible scans, batch of 1–50, progress, remind, reassign, take back | Excludes the reviewer's own captures; stale assignments cannot decide |
| BU-05 | Usage and CSV | Monthly BU scan usage, scans and audit filters, exports | No process selector; no quota push notifications |
| MOB-01 | Activate and sign in | SMS or email choice for technicians, code challenge, phone verification, retry timer | Expired, invalid and locked states explicit; no unlock approval |
| MOB-02 | Home and context | Unit switch, type list, last location, offline queue count, My Scans | No unassigned unit; no process picker |
| MOB-03 | Capture and preview | Camera with 1–4 photo count, quality retake or confirm, location breadcrumb | Never transmit before confirmation; a retry creates no duplicate capture |
| MOB-04 | Offline queue | Queued count, upload and extraction status, retry, repair or discard where permitted | No silent deletion on retry exhaustion or age; local-only evidence may be lost after key loss |
| MOB-05 | My Scans and fields | Needs action, In progress and Approved tabs; photos with flagged fields; accepted, corrected, unreadable, left empty | Unknown confidence never scored as high; submit needs an explicit action |
| MOB-06 | Type mismatch and retake | Detected label, suggested permitted type, remaining attempt budget, explicit re-extract or new retake | Fourth attempt blocked; a physical retake creates a new linked scan |
| MOB-07 | Delegated review | Only the trusted reviewer's currently assigned reviews; raw value, result and revision; approve or reject | No own scan; stale assignment returns 409; approval rules still enforced |

## **Functional requirements**

Every requirement below is V1 must-have and maps to tables in the frozen model. The BRD column gives the V2.1 story it traces to; "A" means the 13 Oct addendum changed or replaced that story's V1 behaviour.

### **1\. Tenancy, users and sign-in**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-1.1 | A tenant owns business units. Creating a unit seeds exactly one default business process (is\_default \= true); the UI has no process picker. | tenant, business\_unit, business\_process | US-024, A |
| FR-1.2 | Every tenant-owned row carries tenant\_id; composite foreign keys keep rows inside one tenant. PostgreSQL RLS restricts rows to the tenant, then to the user's authorised unit, as defense in depth alongside API authorization. | all tenant-owned tables | US-024, US-026, US-028 |
| FR-1.3 | A user's role in a unit is one user\_unit\_role row: enterprise\_admin (bu\_id null), bu\_admin or field\_technician. One active BU Admin per unit; business\_unit.bu\_admin\_user\_id null means "No BU Admin". | user\_unit\_role, business\_unit | US-027, A |
| FR-1.4 | Invitations are single-use magic links that expire 24 hours after sending; only a token hash is stored. A multi-unit invite is one row per unit with the same hash. A technician confirms name and mobile number and verifies the number by texted code; a BU Admin verifies email by code. An expired invite raises an invite\_expired notification. | invite, app\_user, notification | US-036, US-049, A |
| FR-1.5 | Sign-in is by one-time code: technicians choose SMS or email, admins use email. Keycloak counts wrong codes per account across both channels; the 5th locks sign-in for 30 minutes with automatic unlock and an audit\_log row (sign\_in). | Keycloak, audit\_log | US-001, A |
| FR-1.6 | Each device session records the unit in use. Switching units needs no new sign-in and updates app\_user.last\_bu\_id, which opens at next sign-in. | user\_session, app\_user | US-004, US-030 |
| FR-1.7 | Removing a user revokes all their sessions; changing a phone revokes the other devices. The API denies a revoked session within 60 seconds. | user\_session | US-051, US-027 |
| FR-1.8 | A phone number changes only after the code sent to the new number is verified. Five wrong codes lock changes for 30 minutes. The change signs out other devices, writes a users audit row and emails the user. | app\_user, user\_session, audit\_log | A |

### **2\. Locations**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-2.1 | The EA defines a unit's levels (for example Facility, Building, Shop, Bin, Sub-bin) as location\_level\_rule rows: name, order (1 \= top) and required, optional or off. The top level is always required. | location\_level\_rule | US-025b, A |
| FR-2.2 | The EA builds the node tree: each location\_node has a parent, a materialised path and a level; names are unique among siblings. Until publish the EA can add, rename, move or delete any node. | location\_node | US-034, A |
| FR-2.3 | Publishing sets location\_hierarchy\_version to published (version\_no 1\) and freezes the full tree as tree\_snapshot. Afterwards levels and nodes are locked by trigger; post-publish edits are not V1. The publish screen first shows a preview and an irreversible-change warning. | location\_hierarchy\_version, location\_node | US-025, A |
| FR-2.4 | The mobile picker shows tenant.name as a read-only Customer header above the levels. Customer is not a level and not a selectable node. | tenant, location\_node | US-014, A |
| FR-2.5 | The phone caches tree\_snapshot, shows only levels that are not off, enforces required levels, and offers the last-used location for one-tap confirm. A location that is no longer valid or authorised needs manual repair and is never silently replaced. | location\_hierarchy\_version | US-014, US-015 |
| FR-2.6 | Each scan stores its location\_node\_id and a location\_path\_snapshot taken at capture time, so its place is preserved as it was. | scan | US-014, US-025 |

### **3\. Equipment types and extraction contracts**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-3.1 | A BU Admin creates an equipment type for their unit from blank, as a copy, or as an AI-assisted draft (created\_via). Names are unique per unit. Only a not\_published type can be renamed, edited or deleted. | equipment\_type | US-033, A |
| FR-3.2 | Until publish the BU Admin adds, edits, reorders and deletes fields: key, label, order, data type (text, number, date, dropdown, boolean), required and critical flags, format rule, unique-in-unit flag, and a review threshold that defaults to 0.85. A dropdown needs 2 or more choices. | field\_definition | US-033, US-023 |
| FR-3.3 | AI assistance proposes fields from reference images and marks them ai\_suggested. A person reviews and edits them; AI never publishes a type. | equipment\_type, field\_definition | US-033b, A |
| FR-3.4 | Publishing freezes the type's single version (version\_no 1, with publisher and time) and its fields, and creates an active extraction contract binding that version to one prompt version. A published type cannot be renamed, changed or deleted; something different needs a new type. | equipment\_type, equipment\_type\_version, field\_definition, extraction\_contract | US-033, US-018, A |
| FR-3.5 | Prompt versions are platform-owned, global and managed by Amzur; they are never edited after use and never hold client data. A new prompt version adds a new contract rather than silently changing an old one. A blocked contract stops new attempts. | prompt\_version, extraction\_contract | US-018, US-022 |
| FR-3.6 | The mobile type picker lists only published types of the active unit's default process. | equipment\_type | US-009 |
| FR-3.7 | A dropdown extraction must match one of the choices or the field is flagged format\_failed. A boolean is stored as true or false in values\_json. Unique-in-unit compares a value with the unit's other scans of that type. | field\_definition, ai\_field\_value | US-022 |

### **4\. Scans, photos and extraction**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-4.1 | The phone generates client\_capture\_id offline. It is unique per tenant, and a repeated upload, including a retry after a lost response, returns the existing scan. scan.bu\_id is the unit active at capture. | scan | US-010, US-013, A |
| FR-4.2 | A scan has 1–4 photos, numbered and unique per scan. Image bytes live in private MinIO at /{tenant}/{bu}/{scan}/{photo\_no}; the database stores only the key and a SHA-256. Image-quality numbers stay on the phone. | scan\_photo | US-010, US-029 |
| FR-4.3 | An offline capture is held in the AES-256 encrypted local queue under its client\_capture\_id and syncs oldest-first when connectivity and the OS allow. Foreground reconciliation on app resume is the mandatory fallback. Failed or blocked items stay visible and are never silently deleted. | scan (queued\_on\_phone) | US-016, US-017 |
| FR-4.4 | A scan pins one extraction contract at creation. The pin changes only on a re-extract; a newer publish never upgrades it silently. | scan, extraction\_contract | US-018, US-022 |
| FR-4.5 | Every AI call through the AI Inference Proxy is an extraction\_attempt: attempt\_no 1–3 per scan across all types, trigger first, retry or re-extract, status queued, running, succeeded, failed or timed out, with the contract used and tokens and cost for billing. After 3, only a retake is possible. | extraction\_attempt | US-018, US-018b, A |
| FR-4.6 | The mobile app holds no provider key. The Proxy builds the outbound request, strips PII and operational metadata, applies prompt-injection defenses and per-tenant rate limits, and reads secrets from Vault. | extraction\_attempt | US-018–US-021, US-055 |
| FR-4.7 | AI answers are stored insert-only, one ai\_field\_value per field. Confidence is NULL when the model gives no score. Flag reasons are low\_confidence, format\_failed, no\_confidence, missing\_required and critical\_not\_found. | ai\_field\_value | US-022, US-023, A |
| FR-4.8 | An attempt records detected\_label, suggested\_type\_id and suggestion\_confidence. The app shows the Type mismatch screen, and a re-extract with another type happens only after the technician approves it. | extraction\_attempt, scan | A |
| FR-4.9 | Extraction targets under 15 seconds at p95 in the background. The technician receives an immediate acknowledgement and is never blocked waiting for extraction. | scan (processing\_status) | US-011 |

### **5\. Review, delegation and escalation**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-5.1 | Submit for Review creates an immutable revision holding the final values by field key. Only the scan's own technician can create one. Origin is technician\_review or rejection\_fix. | revision | US-012, US-012c, US-013 |
| FR-5.2 | The technician's verdict on each field is a revision\_field: accepted, corrected, unreadable or left empty. Unreadable carries a reason (label worn, not on nameplate, covered or unreachable, other, plus a note). Each verdict links to the untouched AI value. | revision\_field, ai\_field\_value | US-012c |
| FR-5.3 | Submit Anyway sends a revision with required fields still empty and lists them in empty\_required\_fields for the reviewer. In V1 such a revision cannot be approved; unresolved mandatory data must be rejected for rework, with no automatic or exception approval. | revision | US-031, A |
| FR-5.4 | A decision approves or rejects one exact revision, as bu\_admin, enterprise\_admin or delegated\_technician. The decider can never be the scan's technician (trigger). The first valid decision is current; an override inserts a new row linked to the one it overrides. A reject carries a category: image unclear, data correction needed, wrong equipment type or other. | review\_decision | US-031, A |
| FR-5.5 | A rejected scan returns to its technician with the category shown. The fix is a new rejection\_fix revision sent to the named reviewer; the rejected revision is preserved. | revision, review\_decision, scan | US-013, US-012b |
| FR-5.6 | A BU Admin or EA creates a review batch of 1–50 scans for one trusted technician. Scans that technician captured are left out. A batch is a set of review assignments, never bulk approval. | review\_batch, review\_assignment | US-032, A |
| FR-5.7 | Reassign changes the assignee, closes the old assignment rows and writes an audit row. Take back may carry a message. Send reminder sets reminded\_at. Alert timestamps stop repeat alerts. | review\_batch, review\_assignment, notification | A |
| FR-5.8 | A scheduled job creates an escalation (not\_approved\_24h or no\_bu\_admin) once a scan has waited 24 hours. The EA can send a reminder. The first decision resolves it; the BU Admin still sees the scan. | escalation, notification | A |

### **6\. Audit, notifications, exports, quota and retention**

| ID | Requirement | Tables | BRD |
| :---- | :---- | :---- | :---- |
| FR-6.1 | The audit log is append-only and partitioned by month, with actor type user or system and categories sign\_in, users, locations, equipment\_types, review, override, escalation, export and retention. It is kept 1 year online and 3 years archived; this floor cannot be lowered. | audit\_log | US-044, US-045, US-046 |
| FR-6.2 | Work that must follow a commit (emails, texts, AI proxy calls, export builds) is written to outbox\_event in the same transaction as the change and its audit row. A worker runs it with retry and backoff. | outbox\_event | US-044 |
| FR-6.3 | Notifications appear in the bell panel and by email, with no push. There are 17 kinds, listed in Domain 6 of the Data Models document. | notification | A |
| FR-6.4 | A CSV export is a job for scans or audit\_log, limited to the requester's authorised units. Up to 1,000 rows return in the request; above that the job is queued, the file is stored in MinIO, the link is valid for 1 hour and an export\_ready alert is sent. Every job writes an audit row and passes a DLP scan before delivery. | export\_job, audit\_log | US-039, US-057 |
| FR-6.5 | Quota usage is one row per unit per month and counts unique scans, separate from provider attempt cost. A scan is counted when the server accepts it, so a retry of the same capture never counts twice. At the limit the server refuses with HTTP 402 and an actionable message. Where the ceiling is stored is open item 9\. The 80, 95 and 100 percent alert levels are tracked to avoid duplicates; the alert experience is post-V1. | quota\_usage | US-021, US-037, A |
| FR-6.6 | Retention is set per data class, with a tenant default (bu\_id null) and a hard floor; the API rejects a value below the floor with HTTP 400\. Defaults at provisioning: source images 30 days, AI attempts 90 days, approved records 7 years, revision history 7 years, user accounts 90 days after deactivation. A daily enforcement job applies these in V1, skips legally held records and audits every purge. | retention\_config | US-046b |

## **Permissions matrix**

The server decides every operation from the user's role in the active unit. Two cells are unresolved and marked; see open items 5 and 6\.

| Operation | EA | BU Admin | Technician | Constraint |
| :---- | :---- | :---- | :---- | :---- |
| Create unit, assign BU Admin | Yes | No | No | Tenant scope; one active BU Admin per unit |
| Build and publish location tree | Yes | No | No | EA only, before publish |
| Create and publish equipment type | No, unless separately authorised in the unit | Yes | No | BU Admin owns types |
| Invite or disable a technician | Oversight only (open item 5\) | Yes, own unit | No | No cross-unit revocation |
| Capture, verify and submit own scan | Only if assigned as technician | Only if assigned as technician | Yes | Revisions are creator-only; admin rights do not create capture ownership |
| Decide own scan | No | No | No | No self-approval, enforced by trigger |
| Decide another person's exact revision | Yes | Yes, own unit | Only if trusted and assigned | Current submission, resolved mandatory fields, first-decision guard |
| Delegate a batch | Yes | Yes, own unit | No | 1–50 scans authored by others |
| Override a decision | Yes | Unresolved (open item 6\) | No | Appends a linked decision row |
| Read or export scans and audit | Yes, within authority | Yes, own unit | No | DLP, strict row scope, audit event |

## **Non-functional requirements and system obligations**

These carry over from BRD v2.1 and hold for V1. The addendum treats them as obligations that sit outside the data model and need implementation evidence before they count as met.

| Area | Requirement | BRD |
| :---- | :---- | :---- |
| Performance | API responses within 20 s at p95, excluding AI extraction. Acknowledgement of a submitted scan under 500 ms. Background extraction under 15 s at p95. Mobile launch under 3 s on a mid-range Android. | NFR, US-011 |
| Availability | 99.9% uptime, planned maintenance off-peak only. RTO 4 hours or less, RPO 1 hour or less. | NFR, US-061 |
| Scale | 10 units per client, 10–20 users per unit, 1,000 scans per day per unit. | NFR |
| Encryption | AES-256 at rest in PostgreSQL and MinIO, with Vault-managed keys for MinIO. TLS 1.3 only in transit, HSTS of at least 1 year. | US-053, US-054 |
| Secrets | All secrets loaded from HashiCorp Vault at container start, never from environment variables or config files. Secret-scan gates block any commit containing credentials. | US-055, US-064 |
| Image storage | MinIO is private. Images are served only by object-specific presigned URLs valid 15 minutes, issued after a current authorization check; none is issued after revocation. | US-029, US-056 |
| Access control | Every API call validates the Keycloak token, session freshness, action permission, tenant and unit scope. A role or scope change or a removal takes effect within 60 seconds. | US-004, US-028, US-051 |
| Mobile security | Root and jailbreak detection blocks the scan workflow. TLS certificate pinning. All local data encrypted with AES-256 using a hardware-backed key. | US-007, US-008, US-017 |
| Mobile platform | iOS 16+ and Android 10+ (API 29+). Offline-first capture; background sync where the OS permits, with foreground reconciliation as the mandatory fallback. Human verification and submission are never automated. No tablet-native layout. | NFR, US-016, US-017b–d |
| Data residency | All real client data stays on US infrastructure. The India E2E environment holds synthetic data only. OpenAI calls use US endpoints with Zero Data Retention; this needs deployment evidence (open item 14). | NFR, US-059 |
| Privacy in AI calls | PII and operational metadata are stripped before any image is sent to the provider, and logs record only which categories were stripped. | US-019 |
| Compliance | Audit log kept 1 year online and 3 years archived. Breach notification to designated PPG contacts within 24 hours. SOC 2 readiness documents available for review. | US-046, US-048, NFR |
| Export | CSV only. Exports up to 1,000 records are immediate; larger exports are background jobs with a 1-hour download link. All exports pass a DLP scan. | US-039, US-057 |
| Backup | Daily encrypted PostgreSQL snapshots retained 7 days. MinIO object versioning on all buckets. Monthly restore test against the 4-hour RTO (should have). Daily snapshots alone cannot meet the 1-hour RPO; a WAL-based or equivalent design is needed (open item 13). | US-058, US-060, US-061 |
| Delivery pipeline | Two reviewer approvals per PR, SAST and dependency scanning, container scanning, DAST on the US VPS, and a deployment gate that blocks on any failed or skipped check. | US-062–US-067 |

## **Release tests and build sequence**

V1 is accepted when all 18 tests pass in representative environments and each security or compliance commitment has deployment evidence and a named owner. An entity appearing in the data model does not make a feature pass.

| Test | Scenario | Expected outcome |
| :---- | :---- | :---- |
| AT-01 | Duplicate uploads, including a timeout after a successful commit | One scan per tenant and client\_capture\_id, one counted scan, same ACK on retry |
| AT-02 | Capture offline, then switch user or unit before sync | Encrypted queue stays isolated and cannot sync into the wrong context; explicit reauthorisation or repair |
| AT-03 | Unverified phone, or 5 wrong codes | Activation blocked; 30-minute lock, then automatic unlock |
| AT-04 | Publish locations, then try to rename, move or add | Server refuses; the frozen snapshot stays |
| AT-05 | Publish a type, then try to edit or rename a field | Server refuses; a copy can be created and published separately |
| AT-06 | No provider confidence, invalid dropdown value, missing mandatory field | NULL confidence, explicit format and required flags, no silent pass |
| AT-07 | Mismatch plus two failures use all 3 attempts | Attempt 4 blocked; retake creates a linked new scan; no hidden scan on retry |
| AT-08 | Submit Anyway with a mandatory field empty | Revision accepted for review with the gap shown; approval blocked; reject and rework available |
| AT-09 | Two reviewers act on one revision at once | Exactly one current decision; the other gets 409; override is a separate action |
| AT-10 | Batch assigned to a trusted technician who captured some of the scans | Own scans excluded, up to 50 others assigned; a reassigned reviewer cannot decide the old item |
| AT-11 | Scan unapproved at 24 hours, or unit with no BU Admin | EA escalation and notification; a decision retires the escalation without deleting history |
| AT-12 | Admin removed from one unit but kept in another | Session change applies within 60 seconds; the other unit stays authorised; no new signed image URLs for the removed scope |
| AT-13 | Download of restricted or out-of-scope CSV or images | Blocked by API projection, DLP and authorisation; attempts logged |
| AT-14 | Export of 1,001 rows | Async file in MinIO, export\_ready alert, 1-hour link, scoped download, audit history |
| AT-15 | Outbox worker retries after an email or provider timeout | Correlated intent and outcome, safe at-least-once reconciliation, no duplicate scan or review rows |
| AT-16 | Legally held evidence reaches its retention date | Purge suppressed; audit floor kept; job behaviour observable |
| AT-17 | Attempt to reach a Client Portal or create a PortalReader | No such surface or entitlement exists; no migration or API depends on missing tables |
| AT-18 | US hosting versus India E2E data boundary | No production client data in India E2E database, MinIO, logs, backups or provider test payloads |

**Build sequence**

1. **Security and data foundation.** Identity and unit grants, session freshness, Keycloak codes, RLS and tenant-safe foreign keys, audit and outbox, private object storage.  
2. **Pre-capture authoring.** EA location publish, BU Admin type and contract publish, all pre-publish warnings.  
3. **Mobile capture to result.** Image preview, offline reconciliation, stable scan identity, async AI, flags, mismatch, attempt cap.  
4. **Human decision loop.** Revisions and field verdicts, Submit Anyway, approval and rework, delegation, escalation, override.  
5. **Operational controls and release.** Scoped exports, notifications, retention, quota, audit and security gates, US residency, backup and WAL-based RPO, real-device testing.

**Definition of done.** Authenticated authorisation, bounded sync, immutable evidence, error recovery and real-device verification must work. Physical DDL, indexes, status preconditions and APIs are implementation deliverables constrained by the frozen model. This PRD is a product baseline: it does not claim code is built, RTO or RPO is met, provider data retention is verified or a production database is audited. A feature that needs a 32nd table, portal entitlement, a new reviewer role, a mutable published tree or version-two type editing is a post-V1 change request.

## **Post-V1 items**

Nothing below is built or promised in V1. The data model keeps room for several of these (version tables, quota\_usage.alert\_level\_sent) without a schema change.

**Named by the 13 Oct addendum**

* Client Portal, the PortalReader persona, client login, publication projection and portal CSV (UX-006, US-006, EP-06 including US-040 to US-043).  
* Enterprise SAML as a product flow (US-002).  
* Additional dashboard roles beyond the three above, and process selection.  
* Post-publish changes to locations and equipment types, and location CSV import (US-035).  
* Batch approve and reject (US-032).  
* Asset master, on-device VLM inference, ERP or CMMS integration, advanced analytics.  
* Automated inactive-account detection and quota-alert experience (US-050, US-052).

**Already deferred in BRD v2.1**

* BU Admin self-service retention UI (US-038), JSON export, export download history, admin action logging (US-047).  
* Phase 2: Tier 2 SaaS, OAuth 2.0 or OIDC mobile auth, in-app billing engine, multi-language support, full WCAG 2.1 AA audit, Helm and Kubernetes packaging, Azure Terraform modules.

## **Open items and decisions needed**

Fourteen items are open. Each is a gap or conflict between the source documents, and none changes the frozen model; each needs an answer before the related requirement can be built. Two earlier items are now settled and listed below the table.

| \# | Open item | Why it matters | Decide |
| :---- | :---- | :---- | :---- |
| 1 | How a tenant and its first Enterprise Admin are created. The invite table covers BU Admins and technicians only, and BRD v2.1 mentions a Super Admin setting defaults at provisioning. | No requirement or table covers bootstrapping, so FR-1.4 cannot start with an empty tenant. | Owner, Technical Architect |
| 2 | When the 30-day source-image clock starts, and what happens to export photo links after images are purged. | Approved records live 7 years, but reviewers and exports need the photo; links in export\_job.options\_json could point at deleted objects. | Owner |
| 3 | SMS provider for technician sign-in and phone verification. BRD v2.1 names only SendGrid or SMTP for email. | FR-1.4, FR-1.5 and FR-1.8 depend on texting codes; US residency and Vault storage of its credentials also apply. | Technical Architect |
| 4 | Whether admin email code satisfies the MFA requirement (US-003, TOTP or push for privileged roles). The addendum asks engineering to verify privileged-login controls. | V1 admin login is one email code; the V2.1 story expects a second factor. | Owner, Engineering |
| 5 | Who may invite whom. The Data Models screens show Invite BU Admin and Invite technician; BRD US-036 and US-049 say the BU Admin invites; the implementation PRD says both "EA or BU Admin" invites and gives the EA only oversight. | Determines the permission check on invite, and the EA cell in the permissions matrix. | Owner |
| 6 | Who may override a decision. The implementation PRD allows "EA/admin" in one place and BU Admin "as V3 policy permits" in another; review\_decision.decider\_role does not settle it. | Determines the check on appending an override row. | Owner |
| 7 | The legal scan-transition matrix. It exists only as a diagram in the Data Models document. | The API must refuse any other move with HTTP 409, so the allowed moves need transcribing into a table first. | Technical Architect |
| 8 | How audit-log retention is held. BRD US-046b seeds an audit default but its data-class list omits audit logs; the Data Models document says retention\_config follows that story. | Confirm the 1 year online and 3 years archived floor is fixed by partition and archival, not stored as a retention\_config row. | Technical Architect |
| 9 | Where the per-unit monthly quota ceiling is stored. The Data Models text describes quota\_usage as usage and alert level only; the diagram may show more. | FR-6.5 needs a limit to enforce and BU-05 needs one to display. The implementation PRD says to use an existing secured mechanism. | Technical Architect |
| 10 | business\_unit.bu\_admin\_user\_id and the bu\_admin row in user\_unit\_role both say who administers a unit. | If they disagree, vacancy alerts and 24-hour escalation fire wrongly. One must be derived from, or checked against, the other. | Technical Architect |
| 11 | A single rule for a scan's effective decision over revision and review\_decision, covering first-decision races, overrides and resubmission. | Every screen must show the same status; the rule belongs in the API spec before BU-03, EA-03 and MOB-07 are built. | Technical Architect |
| 12 | Handling of ambiguous provider outcomes (timeout after the call was sent): retries and an external idempotency key. | Prevents double-billed attempts without treating the logical scan as a billing transaction (US-018b). | Technical Architect |
| 13 | Daily snapshots alone cannot meet the RPO of 1 hour or less. | The backup requirement and the availability target contradict each other until a WAL-based or equivalent DR design is chosen. | Technical Architect, DevOps |
| 14 | Evidence for OpenAI US endpoints and Zero Data Retention. No document or data model proves the provider configuration. | The residency commitment needs deployment evidence and a named owner before release (AT-18). | Owner, Security |

**Settled by the implementation PRD**

* The daily retention enforcement job runs in V1 (FR-6.6, journey J08). This overrides the V1.1 label on US-046c.  
* Quota alerts are not part of V1. BU-05 has no quota push notifications, and reaching the limit returns a policy error (FR-6.5). The alert levels in quota\_usage stay for later.

## **Appendix: BRD v2.1 story disposition for V1**

This table shows what happens to each V2.1 story in V1. "Changed" means the requirement stands but the addendum or the V3 model changes its V1 behaviour; the matching FR rows above give the V1 wording. The classification is this PRD's reading of the addendum and should be confirmed with the owner.

| Epic | Kept as written | Changed for V1 | Out of V1 | Deferred (V1.1 or later) |
| :---- | :---- | :---- | :---- | :---- |
| EP-D Design | UX-001, UX-003, UX-005, UX-007, UX-008 | UX-002, UX-004 (location picker, type creation flows) | UX-006 | none |
| EP-01 Authentication | US-004, US-005, US-007, US-008 | US-001 (SMS or email code), US-003 (open item 4\) | US-002 (SAML flow), US-006 | none |
| EP-02 Mobile capture | US-012b, US-015, US-016, US-017, US-017b, US-017c, US-017d | US-009, US-010, US-011, US-012, US-012c, US-013, US-014 | none | none |
| EP-03 AI Inference Proxy | US-018b, US-018c, US-019, US-020 | US-018, US-021, US-022, US-023 | none | none |
| EP-04 Tenancy and locations | US-024, US-028, US-029 | US-025, US-025b, US-026, US-027 | none | none |
| EP-05 Admin dashboard | US-037 | US-030, US-031, US-033, US-033b, US-034, US-036, US-039 | none | US-032, US-035, US-038 |
| EP-06 Client Portal | none | none | US-040, US-041, US-042, US-043 | none |
| EP-07 Audit and retention | US-044, US-046, US-046b, US-048 | US-045, US-046c (runs in V1) | none | US-047 |
| EP-08 Account management | US-049, US-051 | none | none | US-050, US-052 |
| EP-09 Data security | US-053 to US-057 | none | none | none |
| EP-10 Backup and resilience | US-058 to US-061 | none | none | none |
| EP-11 DevSecOps | US-062 to US-067 | none | none | none |

**Term mapping.** V2.1 stories use older logical names. These are the closest V3 equivalents, as read from the Data Models document.

| V2.1 term | V3 table or column |
| :---- | :---- |
| Capture, logical scan | scan |
| ExtractionAttempt, ExtractionJob | extraction\_attempt |
| MachineResult, MachineFieldValue | ai\_field\_value |
| SchemaVersion | equipment\_type\_version |
| ExtractionContractVersion | extraction\_contract |
| LocationNode, LocationHierarchyVersion | location\_node, location\_hierarchy\_version |
| CaptureLocationSnapshot | scan.location\_path\_snapshot |
| Revision, ReviewDecision | revision, review\_decision |
| TenantMembership with ScopeGrants | user\_unit\_role (three roles, one unit each) |
| GovernedRecord, Publication | none in V1; the approved scan, exact revision and effective decision are the record |
| last\_login\_at (US-050) | app\_user.last\_active\_at |


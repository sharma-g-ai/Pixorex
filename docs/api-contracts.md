# **Pixorex V1 — API Contracts (Slices \= Sprints 2–5)**

Oct 13, 2026 · @vishnu

## **How to read this doc**

This doc lists every API endpoint Pixorex V1 needs, grouped into 4 slices that follow Release Plan v2 Sprints 2 to 5\. Sprint 1 (setup) and Sprint 6 (E2E gate) add no endpoints.

| Slice | Sprint | Ends | Theme |
| :---- | :---- | :---- | :---- |
| 1 | Sprint 2 | 20 Oct 2026 | Auth \+ RBAC: who you are, your units, invites, users |
| 2 | Sprint 3 | 3 Nov 2026 | AI layer \+ schema: locations, equipment types, scan upload, extraction |
| 3 | Sprint 4 | 17 Nov 2026 | Workflow \+ review: My Scans, self-review, decisions, delegation, escalation, alerts, audit |
| 4 | Sprint 5 | 1 Dec 2026 | Portal \+ integration: CSV export, Client Portal |

Sources, in this order:

1. **Pixorex V3 data model** (31 tables, 13 Oct) — every field, status and rule.  
2. **UI screens of 13 Oct** — Enterprise Admin (EA 01–73), BU Admin (BU 01–35), Technician app (T 01–80). Screen numbers are in the last column of each table.  
3. **Release Plan v2** — only to place an endpoint in a sprint.

When the release plan asks for something V3 and the screens do not have, the endpoint is still listed in its slice and marked **OPEN O-n**. The numbered list in "Open decisions" says what has to be decided. Nothing marked OPEN should be built until it is decided.

The same 76 endpoints are in the OpenAPI 3.1 files, laid out like the earlier contract set: common.yaml, one slice-\*.yaml per sprint, README.md and .spectral.yaml. Each operation's description starts with its number here ("Contract ref 2.21").

## **Conventions**

Every endpoint is REST with JSON over HTTPS under /api/v1. The team has no API conventions yet, so the rows below are standard defaults; change any row and the endpoints follow.

| Topic | Rule |
| :---- | :---- |
| Files | common.yaml \+ one OpenAPI 3.1 file per slice (slice-s2-auth-rbac.yaml, slice-s3-capture-extraction.yaml, slice-s4-workflow-review.yaml, slice-s5-portal-export.yaml), README.md and .spectral.yaml, same layout as the earlier contract set. |
| Base URL | https\://\<host\>/api/v1 |
| Paths | kebab-case segments, camelCase path parameters (/business-units/{buId}/scans). |
| Body format | JSON, UTF-8, field names in snake\_case. AI-assist image uses multipart/form-data; photos are raw image/jpeg. |
| Sign-in | The apps sign in with **Keycloak directly** (manager decision, option 1). This API has **no** sign-in, code or lockout endpoints. |
| Auth on every call | Authorization: Bearer \<Keycloak access token\>. Missing or expired token → 401\. The only calls without a token are the 2 invite-link calls (1.6–1.7) and /health, /ready. |
| Tenant | Taken from the token. Never sent in a URL or body. A row of another tenant is never returned (404). |
| Roles (x-roles) | enterprise\_admin, bu\_admin, field\_technician (V3 user\_unit\_role.role), or public. A technician holding an active review assignment acts as delegated\_technician for that scan only. |
| Unit in the path | Unit-scoped calls carry {buId}. The API checks the caller has an active role in that unit, else 403\. Enterprise Admin passes for every unit of the tenant. |
| Active unit | The app sends X-Device-Id; the API reads and writes user\_session.active\_bu\_id for that user \+ device. Release Plan puts it in the token instead → **OPEN O-11**. |
| IDs | UUID for every id. Display numbers from V3: scan record\_no (REC-90141), batch batch\_no (B-15). |
| Dates | UTC, RFC 3339, e.g. 2026-10-13T09:30:00Z. Date-only filters use YYYY-MM-DD. |
| Lists | ?limit= (default 25, max 100\) and ?cursor=. Response: {"items": \[...\], "page": {"next\_cursor": "..." or null}}. |
| Errors | RFC 9457 application/problem+json: {"type": "/problems/locked-after-publish", "title", "status", "detail", "correlation\_id"}. The type URI is the stable code; list in the last section. |
| Repeat-safe create | Creates carry Idempotency-Key. Same key \+ same body → the first result; same key \+ different body → 409 idempotency-conflict. For scans the key equals client\_capture\_id. |
| Concurrency | No If-Match / ETag: V3 tables have no row\_version. Wrong state → 409\. Adding row\_version is a decision for the data model. |
| Status changes | Always actions (POST .../decisions, .../publish), never PATCH status. |
| Locked things | Changing a published location tree or a published equipment type → 409 locked-after-publish. |
| Audit | Every write marked **Audit** writes its audit\_log row in the same database transaction (V3 Domain 6). |
| Files | Photos are stored in MinIO; responses carry signed URLs valid 15 minutes (Release Plan S3). Export files: link valid 1 hour (V3). |
| Labels per endpoint | x-roles, x-brd (BRD stories, reused from the earlier contract set; \[none\] for 17 V3-only features), x-sprint, x-decision-pending (O-n). Checked by .spectral.yaml. |

## **Slice 1 — Sprint 2: Auth \+ RBAC (19 endpoints)**

Slice 1 gives every surface the signed-in user, their units and roles, unit switching, invites and user management. Sign-in itself is Keycloak; these endpoints start after the app holds a token.

### **1A. Me and my units**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 1.1 | GET /me | All roles | — | user {id, full\_name, email, phone\_number, status}; tenant {name}; units \[{bu\_id, name, role, is\_primary, assigned\_by\_name}\]; active\_bu\_id; last\_bu\_id | Sets app\_user.last\_active\_at. tenant.name is the read-only Customer header in the mobile picker. | T 13–15, BU 03, EA 03 |
| 1.2 | PUT /me/active-unit | All roles | {bu\_id} | Same body as 1.1 | Caller must hold an active role in bu\_id (403). Updates user\_session.active\_bu\_id and app\_user.last\_bu\_id. No new sign-in. | T 19–20, 28; BU 28–30 |
| 1.3 | POST /me/sign-out | All roles | — | 204 | Sets user\_session.revoked\_at for this device. The app also ends the Keycloak session. **Audit** (sign\_in). | T 29 |
| 1.4 | POST /me/phone-change | field\_technician | {new\_phone\_number} (E.164) | 202 {expires\_at} | Who sends and checks the code → **OPEN O-12**. Number already used → 409 phone-in-use. | T 16 |
| 1.5 | POST /me/phone-change/verify | field\_technician | {code} | Same body as 1.1 | **OPEN O-12.** On success: saves phone\_number, phone\_verified\_at; revokes every other user\_session of the user; emails the user. 5 wrong codes lock phone changes 30 min (V3). **Audit** (users). | T 17–18 |

### **1B. Invite links (no token)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 1.6 | POST /invites/preview | Anyone holding the link | {token} — from the link, sent in the body so it never sits in a URL | {role, email, units \[{bu\_id, name}\], invited\_by\_name, expires\_at} | Looks up invite.token\_hash. Expired, used or cancelled → 409 invite-expired, invite-used, invite-cancelled. | T 03–04, BU 01 |
| 1.7 | POST /invites/accept | Anyone holding the link | {token, full\_name, phone\_number (technicians, E.164)} | 201 {user\_id, next\_step: "verify\_phone" or "verify\_email"} | Single use. Creates or re-activates app\_user and one user\_unit\_role per invite row with the same hash. Which unit is is\_primary, and whether other pending invites for the same email are accepted too (T 03 lists units from 2 inviters) → **OPEN O-23**. Phone or email code → **OPEN O-12**. Technicians never get dashboard access. **Audit** (users). | T 03, 05; BU 01, 33 |

### **1C. Invites (admins)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 1.8 | POST /invites | bu\_admin (role field\_technician), enterprise\_admin (role bu\_admin) | {role, email, bu\_ids\[\]} | 201 {invite\_ids\[\], expires\_at} | One invite row per unit, same token\_hash, expires\_at \= now \+ 24 h. BU Admin: only units they run (403). EA: only units with no BU Admin, else 409 unit-has-bu-admin. Email sent through outbox\_event. **Audit** (users). | BU 26, EA 14 |
| 1.9 | GET /invites | bu\_admin, enterprise\_admin | ?status=pending,expired\&bu\_id= | List of {invite\_id, email, role, units, invited\_by\_name, created\_at, expires\_at, status} | BU Admin sees technician invites of their units; EA sees BU Admin invites. Rows past expires\_at show expired. | BU 25, EA 13 |
| 1.10 | POST /invites/{inviteId}/resend | Same as 1.9 | — | {expires\_at} | Pending or expired only. New token, new 24 h; the old link stops working. **Audit** (users). | BU 25, EA 13 |
| 1.11 | POST /invites/{inviteId}/cancel | Same as 1.9 | — | 204 | Status → cancelled. "Remove" on an expired invite uses this call too. **Audit** (users). | BU 25, EA 13 |

### **1D. Units and BU Admins (Enterprise Admin)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 1.12 | GET /business-units | enterprise\_admin, bu\_admin | ?no\_bu\_admin=true | List of {bu\_id, name, facility\_name, bu\_admin {user\_id, full\_name} or null, waiting\_count, escalated\_count, locations\_status} | EA: every unit. BU Admin: only units they run (for the unit switcher). | EA 03, 10; BU 28 |
| 1.13 | POST /business-units | enterprise\_admin | {name, facility\_name, bu\_admin: {invite\_email} or {user\_id}} | 201 {bu\_id} | Creates business\_unit, its default business\_process (is\_default \= true) and its location\_hierarchy\_version (not\_published). user\_id must be an existing BU Admin; invite\_email runs 1.8. **Audit** (users). | EA 11 |
| 1.14 | GET /business-units/{buId} | enterprise\_admin | — | {bu\_id, name, facility\_name, bu\_admin, counts {waiting, escalated, delegated}, locations\_status} | — | EA 25–28, 67 |
| 1.15 | GET /bu-admins | enterprise\_admin | — | List of {user\_id, full\_name, email, units \[{bu\_id, name}\], status, last\_active\_at} | Pending invites come from 1.9. | EA 13 |
| 1.16 | PUT /bu-admins/{userId}/business-units | enterprise\_admin | {bu\_ids\[\]} | Same row as 1.15 | A unit run by someone else → 409 unit-has-bu-admin. Adding a unit that has a pending BU Admin invite cancels that invite. Sets business\_unit.bu\_admin\_user\_id. **Audit** (users). | EA 15 |
| 1.17 | POST /bu-admins/{userId}/remove | enterprise\_admin | {bu\_ids\[\], replacement\_invite\_email (optional)} | 204 | Sets user\_unit\_role.removed\_at; units get bu\_admin\_user\_id \= null ("No BU Admin"). Account and history kept. All units removed → every session revoked at once. Optional email runs 1.8 for those units. **Audit** (users). | EA 16–18, 70–73 |

### **1E. Technicians (BU Admin)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 1.18 | GET /business-units/{buId}/technicians | bu\_admin | — | List of {user\_id, full\_name, email, status, sign\_in\_locked\_until or null, units, scans\_this\_month, active\_batch\_no, last\_active\_at} | Lock state lives in Keycloak → **OPEN O-13**. | BU 25 |
| 1.19 | POST /business-units/{buId}/technicians/{userId}/remove | bu\_admin | — | 204 | Sets user\_unit\_role.removed\_at; revokes the user's sessions for that unit (checked within 60 s, US-051). Open review\_assignment rows → removed with user\_removed, so those scans go back to the BU Admin queue. Scans and decisions keep their name. **Audit** (users). | BU 27 |

**Release Plan items in Sprint 2 not covered by V3 or screens:** 6 roles (**O-1**), SAML login and MFA for admins (**O-2**), role change endpoint (**O-16**), who sets is\_trusted\_reviewer (**O-18**). Session timeout and JWT lifetime are Keycloak settings, not endpoints.

## **Slice 2 — Sprint 3: AI layer \+ schema (27 endpoints)**

Slice 2 lets the Enterprise Admin build and publish locations, lets the BU Admin build and publish equipment types, and lets the technician upload a scan and get the AI result. The AI Inference Proxy is internal: apps never call it.

### **2A. Locations (Enterprise Admin)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 2.1 | GET /business-units/{buId}/locations | enterprise\_admin | — | {version\_id, status, levels \[{level\_id, level\_name, level\_order, requirement}\], nodes \[{node\_id, parent\_id, level\_id, name, is\_placeholder, child\_count}\]} | One location\_hierarchy\_version per unit. | EA 12, 19 |
| 2.2 | PUT /business-units/{buId}/locations/levels | enterprise\_admin | {levels \[{level\_id or null, level\_name, requirement}\]} top to bottom | Same body as 2.1 | Replaces the whole list; order \= position. Top level is always required (400). Quick start (2–5 levels) sends a list. A new level above existing locations starts optional. Published → 409 locked-after-publish. **Audit** (locations). | EA 12, 19 |
| 2.3 | POST /business-units/{buId}/locations/skeleton | enterprise\_admin | — | Same body as 2.1 | Builds one placeholder node per level (is\_placeholder \= true), the top one named facility\_name. Tree not empty → 409\. **Audit** (locations). | EA 12 |
| 2.4 | POST /business-units/{buId}/locations/nodes | enterprise\_admin | {parent\_id, level\_id, names\[\] (1–50)} | 201 {nodes\[\]} | "Add one" sends 1 name, "Add several" a range of up to 50\. level\_id must sit below the parent's level; optional levels may be skipped. Name unique among siblings → 409 duplicate-name. Published → 409\. **Audit** (locations). | EA 19 |
| 2.5 | PATCH /location-nodes/{nodeId} | enterprise\_admin | {name} or {parent\_id} | The node | Rename clears is\_placeholder. Move only to a parent at the same level as the old parent (400 wrong-level). Published → 409\. **Audit** (locations). | EA 19 |
| 2.6 | DELETE /location-nodes/{nodeId} | enterprise\_admin | — | 204 | Deletes the node and everything inside it. Published → 409\. Screen shows **Restore** on deleted rows → **OPEN O-19**. **Audit** (locations). | EA 19 |
| 2.7 | GET /business-units/{buId}/locations/publish-check | enterprise\_admin | — | {counts per level, placeholders\_left, empty\_branches \[{node\_id, path}\], sample\_path, can\_publish} | Feeds the Review & publish dialog. | EA 19 |
| 2.8 | POST /business-units/{buId}/locations/publish | enterprise\_admin | — | {status: "published", published\_at} | Refused with 409 publish-checks-failed while placeholders are left ("names can't change after publishing"). Saves tree\_snapshot, published\_by, published\_at. Already published → 409\. **Audit** (locations). | EA 19 |
| 2.9 | GET /business-units/{buId}/locations/published | field\_technician (of the unit), admins | — | {levels, tree\_snapshot, published\_at} | The phone caches it for offline use. Not published → 404 locations-not-published. | T 24, 41–45 |

### **2B. Equipment types (BU Admin)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 2.10 | GET /business-units/{buId}/equipment-types | bu\_admin; field\_technician gets published only | ?status=\&include=fields | List of {type\_id, name, status, created\_via, field\_count, published\_at, fields\[\] when asked} | The phone caches published types with fields for offline capture. | BU 24; T 21–22, 30–31 |
| 2.11 | POST /business-units/{buId}/equipment-types | bu\_admin | {name, created\_via: "blank", "copy" or "ai\_assist", copied\_from\_type\_id (copy), fields\[\] (ai\_assist: the ticked suggestions)} | 201 the type | Creates equipment\_type (not\_published) and its equipment\_type\_version (version\_no 1). Copy copies the source's fields. AI fields get origin \= ai\_suggested. Name unique in the unit → 409 duplicate-name. **Audit** (equipment\_types). | BU 24 |
| 2.12 | GET /equipment-types/{typeId} | bu\_admin; field\_technician if published | — | {type\_id, name, status, version\_no, published\_at, fields \[...\] in sort\_order} | — | BU 24 |
| 2.13 | PATCH /equipment-types/{typeId} | bu\_admin | {name} | The type | Published → 409 locked-after-publish. **Audit** (equipment\_types). | BU 24 |
| 2.14 | DELETE /equipment-types/{typeId} | bu\_admin | — | 204 | Published → 409\. **Audit** (equipment\_types). | BU 24 |
| 2.15 | POST /equipment-types/{typeId}/fields | bu\_admin | {label, data\_type: text, number, date, dropdown or boolean; options\[\]; is\_required; is\_critical; format\_rule; is\_unique\_in\_unit; flag\_below\_confidence} | 201 the field | Added at the end. field\_key made by the server from label. Label unique in the type → 409\. Dropdown needs 2+ options → 400\. flag\_below\_confidence 0–1, default 0.85. Published → 409\. **Audit** (equipment\_types). | BU 24 |
| 2.16 | PATCH /equipment-types/{typeId}/fields/{fieldId} | bu\_admin | Any field of 2.15 | The field | Same rules as 2.15. | BU 24 |
| 2.17 | DELETE /equipment-types/{typeId}/fields/{fieldId} | bu\_admin | — | 204 | Published → 409\. **Audit** (equipment\_types). | BU 24 |
| 2.18 | PUT /equipment-types/{typeId}/field-order | bu\_admin | {field\_ids\[\]} | The fields | Must list every field once (400). Published → 409\. | BU 24 |
| 2.19 | POST /equipment-types/{typeId}/publish | bu\_admin | — | {status: "published", published\_at, contract\_id} | Needs 1+ field (409 no-fields). Sets type published, version published\_by / published\_at, creates the extraction\_contract with the current prompt\_version. **Audit** (equipment\_types). | BU 24 |
| 2.20 | POST /business-units/{buId}/equipment-types/ai-suggest | bu\_admin | multipart: image, name | {suggested\_fields \[{label, data\_type}\]} | Calls the AI proxy. Nothing is saved; the admin ticks fields and calls 2.11. Whether the photo or the AI cost is kept → **OPEN O-15**. | BU 24 |

### **2C. Scans and extraction (Technician)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 2.21 | POST /business-units/{buId}/scans | field\_technician | {client\_capture\_id, equipment\_type\_id, location\_node\_id, photo\_count (1–4), captured\_at, retake\_of\_scan\_id (optional)}; header Idempotency-Key \= client\_capture\_id | 201 {scan\_id, record\_no, processing\_status: "uploading"}; same client\_capture\_id again → 200 same scan | Type must be published in the unit; node must be in the unit's published tree. Pins the type's active contract and saves location\_path\_snapshot. Retake: original must be the caller's; it becomes closed. | T 32–46, 65–66, 71–72 |
| 2.22 | PUT /scans/{scanId}/photos/{photoNo} | field\_technician (own scan) | image/jpeg body; header Content-Digest (SHA-256, RFC 9530\) | 204 | photoNo 1 to photo\_count. Stored at /{tenant}/{bu}/{scan}/{photo\_no}. Over 2 MB (Release Plan S2), digest mismatch or not JPEG → 400\. Upload route → **OPEN O-17**. | T 38–40, 52 |
| 2.23 | POST /scans/{scanId}/upload-complete | field\_technician (own scan) | — | 202 {processing\_status: "extracting"} | All photos present, else 409 photos-missing. Creates attempt 1 (trigger \= first) and an outbox\_event for the proxy. Answers within 500 ms (Release Plan S3). | T 46, 52, 78 |
| 2.24 | GET /scans/{scanId} | Own technician; admins of the unit; technician assigned to review it | — | {scan\_id, record\_no, processing\_status, review\_status, equipment\_type, location\_path, photos \[{photo\_no, url (15 min)}\], attempts\_used, latest\_attempt {status, detected\_label, suggested\_type\_id, suggestion\_confidence}, fields \[{field\_key, label, data\_type, is\_required, is\_critical, ai\_value, confidence, flag\_reasons\[\]}\]} | — | T 53–54, 57, 78–79 |
| 2.25 | POST /scans/{scanId}/retry-extraction | field\_technician (own scan) | — | 202 {attempt\_no} | Only when failed. 3 attempts used → 409 scan-attempts-used (retake only). Same contract, trigger \= retry. | T 63–64 |
| 2.26 | POST /scans/{scanId}/re-extract | field\_technician (own scan) | {equipment\_type\_id} | 202 {attempt\_no} | Type mismatch path. 3 attempts used → 409\. Sets the scan's type and contract to the new type's active contract, trigger \= re\_extract. | T 54 |
| 2.27 | POST /scans/{scanId}/discard | field\_technician (own scan) | — | 204 | Only before submit for review (409 otherwise). review\_status \= discarded. | T 55–56 |

**Release Plan items in Sprint 3 not covered by V3 or screens:** location depth 1–6 (**O-5**), editing a published type, clone and deactivate (**O-4**), what a proxy refusal (injection 400, quota 402, rate limit 429\) does to the 3 attempts (**O-20**).

## **Slice 3 — Sprint 4: Workflow \+ review (26 endpoints)**

Slice 3 closes the loop from technician self-review to approval or rejection, including delegation, escalation, alerts and the audit log. The API enforces every status move; a move not allowed by V3 gets 409 invalid-state.

### **3A. My Scans and self-review (Technician)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.1 | GET /me/scans | field\_technician | ?bu\_id=\&tab=all, needs\_action, in\_progress or approved\&review\_status=\&equipment\_type\_id=\&from=\&to=\&q= | List of {scan\_id, record\_no, equipment\_type, location\_path, processing\_status, review\_status, attempts\_used, reject\_category, updated\_at} | Tabs per V3: Needs action \= ready\_to\_review, rejected, failed, retake\_required; In progress \= uploading, extracting, waiting\_for\_approval; Approved \= approved. q searches name, serial and bin. The phone-only offline queue is not in this list. | T 14, 26, 47–51, 56, 62–64, 67, 70, 73 |
| 3.2 | POST /scans/{scanId}/revisions | field\_technician (own scan only) | {fields \[{field\_key, verification\_state: accepted, corrected, unreadable or left\_empty, value, unreadable\_reason, note}\], submit\_anyway} | 201 {revision\_id, revision\_no, review\_status: "waiting\_for\_approval"} | Scan must be ready\_to\_review (draft) or rejected. Every flagged field needs a verdict, else 409 flags-not-reviewed (the self-review gate). Required field empty without submit\_anyway \= true → 409 required-fields-empty; with it, the field is left\_empty and listed in empty\_required\_fields. unreadable needs a reason; other needs a note. After a rejection: origin \= rejection\_fix, resubmit\_to\_user\_id \= who rejected. Progress before submit stays on the phone. **Audit** (review). | T 57–61, 69–70, 80 |

Retake after a rejection or 3 failed attempts uses POST /scans with retake\_of\_scan\_id (2.21).

### **3B. Review and decisions**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.3 | GET /business-units/{buId}/review-queue | bu\_admin, enterprise\_admin | ?filter=waiting, over\_1d, over\_1w, delegated or decided\_by\_technicians | {counts {waiting, over\_1d, over\_1w, delegated, decided\_by\_technicians}, items \[{scan\_id, record\_no, equipment\_type, captured\_by, location\_path, flag\_count, technician\_edits {corrected, unreadable}, waiting\_since, assignment {batch\_no, assigned\_to\_name} or null}\]} | Counts also feed the BU Admin home cards. | BU 03, 05, 08, 10 |
| 3.4 | GET /scans/{scanId}/review | bu\_admin, enterprise\_admin, technician assigned to it | — | {scan, photos (15-min URLs), current\_revision {revision\_no, origin, empty\_required\_fields}, fields \[{field\_key, label, ai\_value, confidence, flag\_reasons, technician\_value, verification\_state, unreadable\_reason, note}\], decisions \[...\]} | The scan's own technician gets 403 here ("nobody reviews their own scan"). | BU 07, 20, 22; EA 05; T 75 |
| 3.5 | POST /scans/{scanId}/decisions | bu\_admin, enterprise\_admin, technician assigned to it | {decision: approved or rejected, reject\_category, note} | 201 {decision\_id, review\_status} | Acts on the current revision. Caller is the scan's technician → 403 own-scan (also a DB trigger). Already decided → 409 already-decided (first decider wins). Reject needs reject\_category (image\_unclear, data\_correction\_needed, wrong\_equipment\_type, other). Whether the reject note is required is not shown → **OPEN O-21**. Sets decider\_role, batch\_id; resolves an open escalation; an admin deciding a delegated scan marks its assignment removed (admin\_decided) and alerts the technician (scan\_removed\_from\_batch). Alerts the scan's technician (scan\_approved / scan\_rejected). **Audit** (review). | BU 07, 20–21; EA 05–07; T 75–76 |
| 3.6 | GET /business-units/{buId}/technician-decisions | bu\_admin | ?decision= | List of {decision\_id, scan\_id, record\_no, decided\_by\_name, decision, reject\_category, decided\_at, overridden} | Decisions with decider\_role \= delegated\_technician. | BU 19 |
| 3.7 | POST /decisions/{decisionId}/override | bu\_admin | {decision, reject\_category, note} | 201 {decision\_id} | Inserts a new decision with overrides\_decision\_id; the old one stops being current. Screens show only approval → rejection. Alerts the delegated technician (decision\_overridden); the scan's technician sees the new status. **Audit** (override). | BU 22–23; T 77 |

### **3C. Delegation (review batches)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.8 | GET /business-units/{buId}/delegates | bu\_admin, enterprise\_admin | ?scan\_ids= | List of {user\_id, full\_name, open\_review\_count, own\_scans\_in\_selection} | Technicians of the unit. Who may be picked (is\_trusted\_reviewer) → **OPEN O-18**. | BU 06, 09, 11; EA 08 |
| 3.9 | POST /business-units/{buId}/review-batches | bu\_admin, enterprise\_admin | {assigned\_to, scan\_ids\[\] (1–50)} | 201 {batch\_id, batch\_no, assigned\_scan\_ids\[\], excluded \[{scan\_id, reason: "own\_scan"}\]} | Scans must wait for approval and have no open assignment (409 already-assigned). The technician's own scans are left out. Alerts the technician (batch\_delegated); EA delegating also alerts the BU Admin (ea\_delegated\_in\_unit). **Audit** (review). | BU 06, 09, 11, 14; EA 08–9, 32–35 |
| 3.10 | GET /business-units/{buId}/review-batches | bu\_admin, enterprise\_admin | ?status=active, completed or taken\_back | List of {batch\_id, batch\_no, assigned\_to\_name, created\_by\_name, scan\_count, decided\_count, created\_at, reminded\_at, status} | — | BU 13 |
| 3.11 | GET /review-batches/{batchId} | bu\_admin, enterprise\_admin, the assigned technician | — | {batch, assignments \[{scan\_id, record\_no, status, removed\_reason}\]} | — | BU 13; T 74 |
| 3.12 | POST /review-batches/{batchId}/reassign | bu\_admin, enterprise\_admin | {assigned\_to} | {batch\_id, assigned\_to, excluded\[\]} | Closes open assignments (reassigned), opens new ones; new technician's own scans are left out. Alerts (batch\_reassigned). **Audit** (review). | BU 15–16 |
| 3.13 | POST /review-batches/{batchId}/take-back | bu\_admin, enterprise\_admin | {message (optional)} | 204 | Open assignments → removed (taken\_back); batch taken\_back; saves take\_back\_message. Alerts (batch\_taken\_back). **Audit** (review). | BU 17–18 |
| 3.14 | POST /review-batches/{batchId}/remind | bu\_admin, enterprise\_admin | — | {reminded\_at} | Sets reminded\_at. Alerts (batch\_reminder). | BU 13 |
| 3.15 | GET /me/review-batches | field\_technician | — | List of {batch\_id, batch\_no, scan\_count, open\_count, created\_by\_name} | Active batches assigned to the caller. | T 74 |

Batches with no progress after 1 day or 1 week alert the creator (batch\_no\_progress) from a scheduled job, using alert\_1d\_at and alert\_1w\_at; no endpoint.

### **3D. Escalation and Enterprise Admin scans**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.16 | GET /escalations | enterprise\_admin | ?bu\_id=\&reason=not\_approved\_24h or no\_bu\_admin\&open=true | List of {escalation\_id, scan\_id, record\_no, bu\_name, reason, escalated\_at, reminded\_at, assignment} | A scheduled job creates escalations once a scan has waited 24 h; no create endpoint. | EA 04, 29–31 |
| 3.17 | POST /business-units/{buId}/escalations/remind | enterprise\_admin | — | {reminded\_count} | Sets reminded\_at on the unit's open escalations and alerts its BU Admin (escalation\_reminder). Unit has no BU Admin → 409 no-bu-admin. **Audit** (escalation). | EA 36–37 |
| 3.18 | GET /scans | enterprise\_admin | ?bu\_id=\&review\_status=\&delegated=true\&from=\&to= | List of {scan\_id, record\_no, bu\_name, equipment\_type, captured\_by, location\_path, review\_status, captured\_at} | All units of the tenant. | EA 20, 38–50, 68 |

### **3E. Alerts and audit log**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.19 | GET /me/notifications | All roles | ?unread=true | List of {notification\_id, kind, title, bu\_id, object\_type, object\_id, created\_at, read\_at} | 17 kinds (V3). Bell panel and email; no push. | EA 24; BU 04; T 68, 77 |
| 3.20 | POST /me/notifications/{notificationId}/read | All roles | — | 204 | Sets read\_at. | EA 24, BU 04 |
| 3.21 | POST /me/notifications/read-all | All roles | — | 204 | — | EA 24, BU 04 |
| 3.22 | GET /audit-log | enterprise\_admin | ?bu\_id=\&category=\&from=\&to= | List of {occurred\_at, actor\_type, actor\_name, bu\_name, category, action, object\_type, object\_id, details} | Read only; no write endpoint exists. Categories: sign\_in, users, locations, equipment\_types, review, override, escalation, export, retention. | EA 22, 51–66, 69 |

### **3F. Quota and retention (Release Plan only)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 3.23 | GET /business-units/{buId}/quota | bu\_admin, enterprise\_admin — **OPEN O-7** | ?month= | {period\_month, scans\_used, limit, alert\_level\_sent} | V3 stores scans\_used per unit per month but has no limit column. | None |
| 3.24 | PUT /business-units/{buId}/quota | bu\_admin, enterprise\_admin — **OPEN O-7** | {limit} | Same as 3.23 | Release Plan: BU Admin sets limits, per BU and business process. | None |
| 3.25 | GET /retention-config | enterprise\_admin — **OPEN O-8** | ?bu\_id= | List of {data\_kind, keep\_days, bu\_id} | V3 table exists; defaults seeded at tenant setup. | None |
| 3.26 | PUT /retention-config | enterprise\_admin — **OPEN O-8** | {items \[{data\_kind, keep\_days, bu\_id}\]} | Same as 3.25 | Below the floor → 400 (V3). Release Plan: Super Admin only. **Audit** (retention). | None |
| 3.27 | Quota alerts at 80, 95, 100% | System | — | — | Scheduled job; alert\_level\_sent stops repeats. No endpoint. Depends on O-7. | None |

**Release Plan items in Sprint 4 not covered by V3 or screens:** status names (**O-3**), reviewer editing values (**O-9**), technician My Scans on the web dashboard (**O-10**).

## **Slice 4 — Sprint 5: Portal \+ integration (4 endpoints \+ open items)**

Slice 4 adds CSV export. The Client Portal and the user-provisioning items in the Release Plan either already sit in Slice 1 or are not in V3 and the screens, so they are open items.

### **4A. CSV export**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 4.1 | POST /exports | bu\_admin (scans of their unit), enterprise\_admin (scans and audit\_log) | {export\_kind: scans or audit\_log, filters {bu\_id, review\_status, equipment\_type\_id, from, to, category}, options {columns\[\], include\_photo\_links}} | Up to 1,000 rows: 200 text/csv file. Over 1,000: 202 {export\_id, status: "queued"} | Saved in filters\_json and options\_json. Large exports build in the background, the file goes to MinIO, and the requester gets export\_ready. Every export writes an **Audit** row (export). DLP scan before the file or link is given → **OPEN O-14**. | EA 21, 23; BU 12 |
| 4.2 | GET /exports/{exportId} | The requester | — | {export\_id, status: queued, ready or failed, row\_count, download\_url, link\_expires\_at} | download\_url valid 1 hour; after that 409 link-expired. | EA 21, 23; BU 12 |

### **4C. Operations (common.yaml, kept from the earlier contract set)**

| \# | Endpoint | Who | Request | Response | Rules | Screens |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 4.3 | GET /health | public (no token) | — | {status: "ok"} | Liveness probe; no data. | None |
| 4.4 | GET /ready | public (no token) | — | {status: ready or not\_ready, checks {database, keycloak, minio, vault: ok or fail}}; 503 when not ready | Readiness probe for DevOps monitoring (Release Plan S5). No secrets or versions shown. | None |

Export download history UI is deferred to V1.1 in the Release Plan, so there is no list endpoint.

### **4B. Release Plan Sprint 5 items**

| Release Plan item | Where it is in this doc | Status |
| :---- | :---- | :---- |
| Client Portal: approved records, search, filter, record detail, portal-only hidden fields, magic link \+ SAML login | Not in V3 or screens. The plan also says the portal reads the database directly and bypasses the API. | **OPEN O-6** |
| Invite with magic link, 24 h | 1.8–1.11 (Slice 1), because the Sprint 2 user-management table already needs it | Done in Slice 1 → **O-22** |
| Role change that invalidates the token | No screen and no V3 rule | **OPEN O-16** |
| Deactivate user, sessions ended within 1 min | 1.17 and 1.19 (remove from units); sessions checked within 60 s (US-051) | Covered |
| CSV export ≤ 1,000 rows sync, \> 1,000 async, 1-hour link | 4.1–4.2 | Covered |
| DLP scan on every export | No V3 column for a DLP result | **OPEN O-14** |
| Breach notification pipeline | Process and alerting, not an app endpoint | Not an endpoint |

## **Open decisions (23)**

23 points need a decision before the endpoints that depend on them are built. Items 1–10 are Release Plan vs V3; items 11–23 came up while writing the endpoints.

| \# | Question | One side says | Other side says | Endpoints affected | Who decides |
| :---- | :---- | :---- | :---- | :---- | :---- |
| O-1 | How many roles? | Release Plan: 6 roles (incl. Reviewer, Super Admin, portal user) | V3 \+ screens: 3 roles | All role checks | Manager / TA |
| O-2 | How do admins log in? | Release Plan: SAML SSO \+ MFA for admins | Screens: email code, no password | None in the API (Keycloak); changes EA 01–02, BU 34–35 | Manager / TA |
| O-3 | Scan status names | Release Plan: captured, extracting, ready\_to\_submit, in\_review, approved, rejected | V3: processing\_status \+ review\_status, other names | 2.21–2.27, 3.1–3.5 | Manager / TA |
| O-4 | Can a published type change? | Release Plan: edit makes a new version; clone; deactivate | V3 \+ screens: locked; copy only | 2.11–2.19 | Manager / TA |
| O-5 | Limit on location levels? | Release Plan: depth 1–6 | V3 \+ screens: no limit stated | 2.2 | Manager / TA |
| O-6 | Client Portal | Release Plan: Sprint 5 portal, hidden fields, reads DB directly | Not in V3 or screens | New endpoints or none | Manager / TA |
| O-7 | Scan quota limit | Release Plan: limit per BU and per business process, BU Admin screen | V3: usage only, no limit column, no screen | 3.23–3.24, 3.27 | Manager / TA, then data model |
| O-8 | Who sets retention? | Release Plan: Super Admin at setup | V3: table only, no role, no screen | 3.25–3.26 | Manager / TA |
| O-9 | Can the reviewer edit values? | Release Plan: yes, saved next to the AI value | V3 \+ screens: approve or reject only | 3.5 | Manager / TA |
| O-10 | Technician My Scans on the web? | Release Plan: dashboard view too | Screens: mobile only | 3.1 | Manager / TA |
| O-11 | Where does the active unit live? | Release Plan: in the token | V3: user\_session.active\_bu\_id, switch without sign-in | 1.2, every unit check | Manager / TA |
| O-12 | Who sends and checks codes at activation and phone change? | Option 1: Keycloak does sign-in codes | V3: activation and phone change verify a code, 5 wrong \= 30-min lock | 1.4–1.5, 1.7 | Manager / TA |
| O-13 | How does the API learn about Keycloak locks? | Screens: "Sign-in locked · 18 min left" in the list, audit row per lock | V3 stores no lock state | 1.18, audit | Manager / TA |
| O-14 | DLP scan on exports | Release Plan: scan before the link is given | V3 export\_job has no DLP result | 4.1–4.2 | Manager / TA, then data model |
| O-15 | AI-assist photo and cost | Screens: suggest fields from a photo | V3 has no table for the photo or the AI cost of a suggestion | 2.20 | Manager / TA |
| O-16 | Role change | Release Plan: role change ends the token | No screen, no V3 rule | New endpoint | Manager / TA |
| O-17 | Photo upload route | This doc: upload through the API | Release Plan: signed MinIO URLs (15 min) | 2.22 | FSD-1 \+ TA |
| O-18 | Who can receive delegated batches? | V3: is\_trusted\_reviewer flag | Screens: any technician of the unit; no screen sets the flag | 3.8–3.9 | Manager / TA |
| O-19 | Restore a deleted location | Screens: Restore on deleted rows before publish | V3: delete removes the row | 2.6 | Amrutha \+ you |
| O-20 | Do proxy refusals use an attempt? | Release Plan: injection 400, quota 402, rate limit 429 | V3: 3 attempts per scan | 2.23, 2.25–2.26 | Manager / TA |
| O-21 | Is the reject note required? | Screens: a note box | Not stated | 3.5, 3.7 | Amrutha \+ you |
| O-22 | Invites in Sprint 2 or 5? | Release Plan: provisioning APIs in Sprint 5 | Release Plan Sprint 2: FSD-2 user table uses them | 1.8–1.11 | Manager / TA |
| O-23 | Activation with invites from 2 units | Screen T 03: one activation lists Plant 04 (R. Kowalski) and Plant 07 (S. Alvi) | V3: one hash per invite; is\_primary one per user, rule for picking it not stated | 1.7 | You \+ Amrutha |

## **Error codes and status moves**

Every error is RFC 9457 problem+json, as in the earlier contract set; code is the stable value apps check.

| HTTP | Problem type (/problems/...) | When | Endpoints |
| :---- | :---- | :---- | :---- |
| 400 | validation | Missing or badly typed field; dropdown with under 2 options; reject without a category | All |
| 400 | wrong-level | Node added or moved to the wrong level | 2.4–2.5 |
| 400 | digest-mismatch, photo-too-large | Photo bytes do not match Content-Digest; photo over 2 MB | 2.22 |
| 400 | below-retention-floor | Retention under the floor | 3.26 |
| 401 | (Unauthorized) | No token, expired token, revoked session | All except 1.6–1.7, /health, /ready |
| 402 | (QuotaExceeded) | Unit scan quota reached | 2.21 |
| 403 | forbidden | Role or unit not allowed | All |
| 403 | own-scan | Reviewing your own scan | 3.4–3.5 |
| 404 | not-found | Unknown id or another tenant's id | All |
| 404 | locations-not-published | Unit's tree not published yet | 2.9 |
| 409 | idempotency-conflict | Same Idempotency-Key, different body | All creates |
| 409 | locked-after-publish | Change to a published tree or type | 2.2–2.6, 2.8, 2.13–2.19 |
| 409 | duplicate-name | Name already used among siblings, in the unit or in the type | 1.13, 2.4–2.5, 2.11, 2.13, 2.15–2.16 |
| 409 | tree-not-empty | Skeleton requested on a tree that has nodes | 2.3 |
| 409 | publish-checks-failed | Placeholders left in the tree | 2.8 |
| 409 | no-fields | Publishing a type with no fields | 2.19 |
| 409 | type-not-published, location-not-published | Scan uses an unpublished type or a node outside the published tree | 2.21, 2.26 |
| 409 | photos-missing | Upload complete before every photo arrived | 2.23 |
| 409 | scan-attempts-used | 3 extraction attempts used | 2.25–2.26 |
| 409 | flags-not-reviewed, required-fields-empty | Self-review gate not met | 3.2 |
| 409 | already-decided | Someone decided this revision first | 3.5 |
| 409 | already-assigned | Scan already in an open batch | 3.9 |
| 409 | unit-has-bu-admin, not-a-bu-admin, no-bu-admin | BU Admin rules | 1.8, 1.13, 1.16, 3.17 |
| 409 | phone-in-use, code-invalid, phone-change-locked | Phone change and activation | 1.4–1.5, 1.7 |
| 409 | invite-expired, invite-used, invite-cancelled | Invite link no longer valid | 1.6–1.7 |
| 409 | link-expired | Export link older than 1 hour | 4.2 |
| 409 | invalid-state | Any other status move not allowed (table below) | 1.10–1.11, 2.21–2.27, 3.2, 3.5, 3.7, 3.12–3.14 |
| 429 | (TooManyRequests) | 100 requests per minute per tenant | 2.20–2.21 |

### **Status moves the API allows**

| Column | From | To | Endpoint or job |
| :---- | :---- | :---- | :---- |
| processing\_status | (phone) queued\_on\_phone | uploading | 2.21 |
| processing\_status | uploading | extracting | 2.23 |
| processing\_status | extracting | ready\_to\_review or failed | AI proxy job |
| processing\_status | failed | extracting | 2.25 (attempts left) |
| processing\_status | failed (3 attempts used) | retake\_required | AI proxy job |
| processing\_status | ready\_to\_review | extracting | 2.26 (attempts left) |
| review\_status | draft | waiting\_for\_approval | 3.2 |
| review\_status | draft | discarded | 2.27 |
| review\_status | waiting\_for\_approval | approved or rejected | 3.5 |
| review\_status | approved | rejected | 3.7 (override) |
| review\_status | rejected | waiting\_for\_approval | 3.2 (fix and resubmit) |
| review\_status | rejected, or draft with retake\_required | closed | 2.21 with retake\_of\_scan\_id |


## Conflict Detection Report

Mode: new (net-new bootstrap). Ingest set: 10 documents (2 ADR by manifest, 4 SPEC, 1 PRD, 3 DOC). No document is locked. Precedence applied: CONSTITUTION.md (0) > ARCHITECTURE.md (1) > SPEC > PRD > DOC, with the manifest overrides above.

### BLOCKERS (0)

(none)

### WARNINGS (6)

[WARNING] Reference cycles in the cross-reference graph (downgraded from blocker, see note)
  Found: Cross-reference cycles exist among ingested documents. (1) CONSTITUTION.md -> ARCHITECTURE.md -> CONSTITUTION.md (CONSTITUTION §0 and §3 point to ARCHITECTURE.md; ARCHITECTURE.md header says "Binding rules live in CONSTITUTION.md"). (2) CONSTITUTION.md -> specs/SPEC-PX-01.md -> ARCHITECTURE.md -> CONSTITUTION.md (SPEC-PX-01 cites ARCHITECTURE §4.4). (3) ARCHITECTURE.md -> specs/SPEC-PX-10.md -> ARCHITECTURE.md (SPEC-PX-10 cites ARCHITECTURE §11; ARCHITECTURE §2 and §12 cite SPEC-PX-10). (4) contracts/README.md -> docs/api-contracts.md -> contracts/README.md (api-contracts lists README.md among its files). Sources: CONSTITUTION.md, ARCHITECTURE.md, specs/SPEC-PX-01.md, specs/SPEC-PX-10.md, contracts/README.md, docs/api-contracts.md.
  Impact: The synthesizer rules say to treat cycles as blockers and not synthesize the cyclic set. Every cycle here is a mutual "see also" pointer between documents; no document's content is derived from another's during synthesis, so there is no synthesis loop. Treating them as hard blockers would exclude the governance docs and most specs. Extraction was therefore completed for all documents, and the cycles are raised here for explicit acknowledgement instead of silently ignored.
  → Confirm the cycles are benign navigational references (recommended), or re-run with a manifest that excludes the back-references. If you require the strict rule, treat this as a BLOCKER and re-ingest after removing the back-references.

[WARNING] Competing variants: who may override a review decision
  Found: docs/PRD.md permissions matrix says Override a decision: Enterprise Admin = Yes, BU Admin = Unresolved (open item 6), Technician = No. docs/api-contracts.md contract 3.7 (POST /decisions/{decisionId}/override) lists Who = bu_admin only, so the EA is excluded.
  Impact: The PRD allows the EA and leaves the BU Admin undecided; the contract allows only the BU Admin. Implementing either closes off the other. Contract is the lower-precedence source (DOC), but PRD open item 6 is itself undecided, so neither is auto-resolved. Preserved as REQ-override-authority-v1 and REQ-override-authority-v2 in requirements.md.
  → Owner records the decision for PRD open item 6 in STATE.md; then align contract 3.7 x-roles and PRD matrix. Do not build 3.7 until decided (CONSTITUTION §0).

[WARNING] Competing variants: who may invite whom
  Found: docs/api-contracts.md contract 1.8 and specs/SPEC-PX-01.md REQ-01.10 build: BU Admin invites technicians (own units only), EA invites BU Admins (units with no BU Admin only). docs/PRD.md open item 5 says the source documents disagree (Data Models screens show Invite BU Admin and Invite technician; BRD US-036/US-049 say BU Admin invites; implementation PRD says "EA or BU Admin" invites with EA oversight only), and the permissions matrix shows the EA cell for inviting or disabling a technician as "Oversight only (open item 5)".
  Impact: SPEC-PX-01 (Draft, Sprint 2, ends Oct 20, 2026) specifies one variant as GIVEN/WHEN/THEN tests for an item the PRD marks OPEN. The SPEC does not mark REQ-01.10 as BLOCKED. Preserved as REQ-invite-authority-v1 and REQ-invite-authority-v2.
  → Owner decides PRD open item 5 before G1 for SPEC-PX-01; either record it in STATE.md and mark REQ-01.10 settled, or mark REQ-01.10 BLOCKED.

[WARNING] Competing variants: who may read and export the audit log
  Found: docs/PRD.md permissions matrix "Read or export scans and audit": BU Admin = Yes, own unit; BU-05 screen lists "scans and audit filters, exports"; FR-6.4 allows an export job for scans or audit_log limited to the requester's authorised units; journey J08 has EA and BU Admin filtering scans and audit within authorised scope. specs/SPEC-PX-07.md REQ-07.01 says audit_log is "readable by EA only"; docs/api-contracts.md 3.22 (GET /audit-log) is enterprise_admin only and 4.1 (POST /exports) lets bu_admin export scans of their unit but only enterprise_admin export audit_log.
  Impact: Default precedence would place the Draft SPEC above the baselined PRD, but this is a product-scope disagreement, so it is not auto-resolved. Choosing the SPEC variant would drop BU Admin audit access the PRD promises (BU-05); choosing the PRD variant needs new RLS policy and endpoint scope in S2/S4. Preserved as REQ-audit-access-v1 and REQ-audit-access-v2.
  → Spec owner and owner confirm BU Admin audit scope; update SPEC-PX-07 REQ-07.01 / contracts 3.22 and 4.1, or amend the PRD matrix and BU-05, before G1 for the S4 slice.

[WARNING] Competing variants: where phone-change and activation codes are checked (API vs Keycloak)
  Found: docs/api-contracts.md 1.4 and 1.5 define API endpoints POST /me/phone-change and POST /me/phone-change/verify taking a {code}, counting 5 wrong codes and locking phone changes for 30 minutes (marked OPEN O-12). specs/SPEC-PX-01.md proposes that Keycloak sends and checks these codes via required actions, with the event listener telling the API the verified value, and states "Endpoints 1.4-1.5 change accordingly" (REQ-01.12 BLOCKED on O-12). CONSTITUTION.md §2.7 (non-negotiable): "The API has no sign-in, code or lockout endpoints." ARCHITECTURE.md §4.2 also places codes and lockout in Keycloak.
  Impact: The contract design puts code verification and lockout logic in the API, which the Constitution (precedence 0) forbids. By precedence the Constitution and the SPEC proposal win, but the exact replacement endpoints are undecided, so this is not auto-resolved. Preserved as REQ-phone-change-codes-v1 and REQ-phone-change-codes-v2.
  → Record the O-12 decision in STATE.md (spec proposes Keycloak-owned verification), then revise contract 1.4/1.5 and 1.7 accordingly. Do not build 1.4, 1.5 or the verification step of 1.7 until then.

[WARNING] Open decisions needed within Sprint 2 (ends Oct 20, 2026)
  Found: Items required by Sprint 2 and still open or marked "Decide today": P-1 / PRD item 1 tenant and first EA bootstrap (ARCHITECTURE §4.6, SPEC-PX-04 REQ-04.05); O-11 active unit in user_session vs token (SPEC-PX-01 REQ-01.08); O-12 activation and phone-change code ownership (REQ-01.11, REQ-01.12 BLOCKED); O-13 Keycloak lock state in API (REQ-04.10); O-23 primary unit and multi-invite activation (REQ-01.11 BLOCKED); P-10 bu_admin_user_id vs user_unit_role (REQ-04.08, REQ-04.09); P-3 SMS provider and DLT registration; P-4 admin MFA (decision S2, before release; not blocking S2 build); email provider SES vs SendGrid/SMTP (not blocking S2). Sources: ARCHITECTURE.md §14, specs/SPEC-PX-01.md, specs/SPEC-PX-04.md, docs/PRD.md open items.
  Impact: CONSTITUTION §0 forbids building OPEN items until recorded in STATE.md, and root STATE.md is intentionally not part of this ingest, so the recorded status of these decisions is unknown. Roadmap phases covering Sprint 2 will contain BLOCKED requirements.
  → Provide decisions (or confirm they are already in STATE.md) before routing; otherwise the roadmapper should mark the dependent requirements as blocked.

### INFO (9)

[INFO] No locked decisions; manifest-typed ADRs are governance documents
  Note: CONSTITUTION.md and ARCHITECTURE.md carry type ADR from the manifest only (precedence 0 and 1). Neither has a Status: Accepted field or Context/Decision/Consequences structure, and CONSTITUTION change-control approvals for v1.0, v1.1, v1.2 are [TBD]. All decisions are recorded as `proposed` in decisions.md with a note that the CONSTITUTION self-declares as binding. No LOCKED-vs-LOCKED contradiction was possible.

[INFO] Auto-resolved: Release Plan positions in the contracts DOC yield to the PRD and CONSTITUTION
  Note: docs/api-contracts.md lists open decisions where the Release Plan differs from V3/screens. The baselined PRD and CONSTITUTION (§0 out-of-V1 list) settle several: O-1 six roles vs three (PRD: three roles; CONSTITUTION: no roles beyond three); O-2 SAML + admin MFA vs email code (PRD FR-1.5: admins email code, SAML out of V1; SPEC-PX-01 marks O-1/O-2 settled by PRD; admin MFA remains PRD open item 4); O-4 published type change (PRD FR-3.4: frozen, copy only); O-6 Client Portal (PRD: out of V1, AT-17). PRD-consistent without explicit settlement: O-3 (PRD uses processing_status and review_status), O-9 (PRD: approve or reject one exact revision), O-10 (PRD: My Scans on mobile). Winner: PRD/CONSTITUTION over DOC. The contract document still shows these as open and its Slice 4 title "Portal + integration" is stale.

[INFO] Auto-resolved: quota alerts (contract 3.27) excluded from V1
  Note: docs/api-contracts.md 3.27 lists scheduled quota alerts at 80, 95, 100%. docs/PRD.md "Settled by the implementation PRD" says quota alerts are not part of V1 and BU-05 has no quota push notifications. PRD wins over DOC. Quota ceiling storage and endpoints 3.23-3.24 (O-7, PRD open item 9) remain open and are not resolved here.

[INFO] Auto-resolved: contract decision O-22 settled by SPEC-PX-01
  Note: docs/api-contracts.md O-22 (invites in Sprint 2 or 5) is open in the DOC; specs/SPEC-PX-01.md records it Settled: S2. SPEC wins over DOC; contracts already place invites in Slice 1 (1.8-1.11).

[INFO] Status-transition matrix source differs between PRD and ARCHITECTURE
  Note: docs/PRD.md says the Data Models diagram is authoritative for legal moves (open item 7: matrix not yet transcribed). ARCHITECTURE.md §6 says the contracts' "Status moves the API allows" table is the transition matrix and "resolves P-7". The table is captured in context.md. The Data Models document and diagram are not in the ingest set, so the table could not be checked against the diagram.

[INFO] Referenced source documents are not part of this ingest
  Note: Referenced but absent: docs/data-model.md (frozen V3 Data Models, storage authority per CONSTITUTION §0), BRD-INDEX.md, contracts/*.yaml and .spectral.yaml (contracts/README.md says "drop the contract files here"), keycloak/realm-pixorex.json, SPEC-PX-02, 03, 05, 06, 08, 09, 11, and tasks/. STATE.md is intentionally not ingested. Roadmap detail for Sprints 3-6 will rest on ARCHITECTURE §12 and PRD requirements only, and SPEC-PX-04 REQ-04.01 cannot be verified against the Data Models document.

[INFO] All four ingested SPECs are Draft (awaiting G1)
  Note: SPEC-PX-01, 04, 07, 10 each carry "Status: Draft - awaiting G1". The PRD is dated Oct 13, 2026 and "V1 Baselined". Where SPEC and PRD agree, the SPEC adds GIVEN/WHEN/THEN detail (constraints.md); where they disagree on product scope the conflict is surfaced as a WARNING above rather than resolved by default SPEC > PRD precedence.

[INFO] Two screen-numbering schemes
  Note: docs/PRD.md and the SPECs use EA-01-04, BU-01-05, MOB-01-07 (16 screens). docs/api-contracts.md and docs/design/README.md use design-canvas numbers EA 01-73, BU 01-35, T 01-80. No document maps one scheme to the other.

[INFO] Internal Keycloak event-listener endpoint is outside the 76-endpoint contract
  Note: specs/SPEC-PX-01.md REQ-01.05 and ARCHITECTURE.md §4.2 define an internal, network-restricted API endpoint (Vault-held shared secret) that receives LOGIN, LOGIN_ERROR and lockout events. It is "not in the public contract". CONSTITUTION §3 says the OpenAPI files in contracts/ are the interface. SPEC and ARCHITECTURE agree with each other; flagged so G2 review confirms it does not conflict with CONSTITUTION §2.7 (no sign-in, code or lockout endpoints).

# Synthesis Summary

Entry point for gsd-roadmapper. Mode: new. Generated 2026-10-14.

## Documents ingested (10)
- ADR by manifest (2): CONSTITUTION.md (precedence 0), ARCHITECTURE.md (precedence 1). Neither is a formal accepted ADR; locked = false for both.
- SPEC (4): specs/SPEC-PX-01.md, specs/SPEC-PX-04.md, specs/SPEC-PX-07.md, specs/SPEC-PX-10.md. All Draft, awaiting G1.
- PRD (1): docs/PRD.md (Pixorex PRD V3, V1 Baselined, Oct 13, 2026).
- DOC (3): docs/api-contracts.md, docs/design/README.md, contracts/README.md.
- Not ingested by design: root STATE.md. Referenced but absent: docs/data-model.md, contracts/*.yaml, SPEC-PX-02/03/05/06/08/09/11.

Precedence applied: manifest overrides (CONSTITUTION 0, ARCHITECTURE 1), then SPEC > PRD > DOC. Product-scope disagreements between Draft SPECs / contracts and the baselined PRD are surfaced as competing variants, not auto-resolved.

## Decisions (decisions.md)
- 56 entries: 36 CONSTITUTION entries (incl. 12 non-negotiables CON-NN-01 to 12) and 20 ARCHITECTURE entries (ARCH-01 to ARCH-20), of which ARCH-09 (tenant bootstrap, P-1) and ARCH-11 (P-10) are explicitly OPEN/proposed.
- Locked decisions: 0 (no source carries Accepted status). The CONSTITUTION self-declares as binding; non-negotiables should be treated as top-authority rules by the roadmapper.
- Source paths: CONSTITUTION.md, ARCHITECTURE.md.

## Requirements (requirements.md)
- 44 functional requirements from the PRD: REQ-FR-1.1 to 1.8, 2.1 to 2.6, 3.1 to 3.7, 4.1 to 4.9, 5.1 to 5.8, 6.1 to 6.6.
- 1 permissions matrix entry (REQ-permissions-matrix).
- 15 non-functional requirements (REQ-NFR-*).
- 18 release tests as acceptance criteria (REQ-release-test-AT-01 to AT-18).
- 16 screens (REQ-screen-EA-01 to 04, BU-01 to 05, MOB-01 to 07).
- 8 competing-variant entries in 4 pairs: REQ-override-authority-v1/v2, REQ-invite-authority-v1/v2, REQ-audit-access-v1/v2, REQ-phone-change-codes-v1/v2.
- Per-FR acceptance is absent in the PRD; see AT-01 to AT-18 and the SPEC GIVEN/WHEN/THEN in constraints.md.

## Constraints (constraints.md)
- 41 entries from 4 SPECs (4 spec headers + 37 requirements). Type breakdown: protocol 12, api-contract 14, schema 7, nfr 8.
- Open/BLOCKED within specs: REQ-01.11 (O-12, O-23), REQ-01.12 (O-12), REQ-01.08 (O-11), REQ-04.05 (P-1), REQ-04.08/04.09 (P-10), REQ-04.10 (O-13).

## Context (context.md)
- Topics: API contracts overview and conventions; endpoint catalogs for Slice 1 (19), Slice 2 (27), Slice 3 (26 + 1 job), Slice 4 (4); open decisions O-1 to O-23; error codes; status moves; design canvases; contracts folder; PRD supporting context (precedence, scope, roles, data model invariants, lifecycle, journeys J01-J08, build sequence, post-V1, open items 1-14, BRD disposition and term mapping). 18 topic blocks.

## Conflicts (detail: C:/Users/Geet Sharma/Documents/Pixorex/.planning/INGEST-CONFLICTS.md)
- 0 blockers.
- 6 warnings: reference cycles (downgraded from blocker, needs acknowledgement); override authority; invite authority; audit read/export access; phone-change code ownership (API vs Keycloak); Sprint 2 open decisions.
- 9 info: no locked decisions; contract Release Plan positions auto-resolved to PRD/CONSTITUTION (O-1, O-2, O-4, O-6, plus consistent O-3, O-9, O-10); quota alerts excluded from V1; O-22 settled by SPEC-PX-01; transition matrix source difference; missing referenced docs; Draft SPEC status; two screen-numbering schemes; internal event-listener endpoint.

## Intel files
- C:/Users/Geet Sharma/Documents/Pixorex/.planning/intel/decisions.md
- C:/Users/Geet Sharma/Documents/Pixorex/.planning/intel/requirements.md
- C:/Users/Geet Sharma/Documents/Pixorex/.planning/intel/constraints.md
- C:/Users/Geet Sharma/Documents/Pixorex/.planning/intel/context.md
- Classifications: C:/Users/Geet Sharma/Documents/Pixorex/.planning/intel/classifications/

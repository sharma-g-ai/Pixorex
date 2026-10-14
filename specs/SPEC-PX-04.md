# SPEC-PX-04 — Tenancy, roles & RLS

| Field | Value |
|---|---|
| Bounded context | BC-04 |
| Grade | **A0** for RLS policies, DB grants and authorization helpers · A1 for schema migrations and bootstrap · A2 for CRUD endpoints around them |
| PRD | FR-1.1, FR-1.2, FR-1.3 · data-model invariants · journey J01 (unit creation), J02 (removal) · screens EA-01, BU-01 |
| Contracts | Slice 1: 1.12–1.19 |
| Release tests | AT-12 |
| Sprint | S2 (ends Oct 20, 2026) |
| Status | Draft — awaiting G1 |

## Decisions this spec depends on

| Ref | Question | Proposed answer | Status |
|---|---|---|---|
| P-1 | Creating the tenant and first EA | Operator-only CLI (ARCHITECTURE §4.6) | **Decide today** |
| P-10 | `bu_admin_user_id` vs `user_unit_role` | `user_unit_role` authoritative; column set in the same transaction; deferred constraint trigger checks agreement | **Decide today** |
| O-13 | Lock state in technician list | Read from Keycloak attack-detection admin API per listed user | **Decide today** |
| O-5 | Location depth limit | Not needed in S2 | Deferred to S3 |

---

## Requirements

### REQ-04.01 Domain 1 schema (A1) — frozen model
Migrations create `tenant`, `business_unit`, `business_process`, `app_user`, `user_unit_role`, `invite`, `user_session` exactly as in the V3 Data Models document, plus `location_hierarchy_version` (needed by unit creation).
- GIVEN the migration WHEN compared with the Data Models document THEN table and column names, types, nullability, keys and status values match; no extra tables or columns.
- GIVEN any tenant-owned table THEN it has `tenant_id`, `created_at`, `updated_at`, and every FK to another tenant-owned table includes `tenant_id`.
- GIVEN an attempt to link a row to a parent in another tenant THEN the insert fails at the database.
- GIVEN uniqueness rules THEN the DB enforces: email unique per tenant; phone (E.164) unique; one active BU Admin per unit (partial unique index on active `bu_admin` rows); one default `business_process` per unit.

### REQ-04.02 Database roles and grants (A0)
- GIVEN the API connection role WHEN it queries any tenant-owned table THEN RLS applies (role is not owner and lacks BYPASSRLS).
- GIVEN migrations THEN they run under a separate owner role whose credentials are only used by the migration job.

### REQ-04.03 RLS policies (A0) — FR-1.2
Policies per ARCHITECTURE §4.5 for every Domain 1 table and `location_hierarchy_version`.
- GIVEN users in tenants A and B WHEN a tenant-B user lists units, users, invites or sessions THEN no tenant-A row is returned, and fetching a tenant-A id returns 404.
- GIVEN a BU Admin of unit X WHEN they query technicians THEN unit Y's rows are invisible.
- GIVEN an EA WHEN they query THEN all units of their tenant are visible and none of another tenant.
- GIVEN no RLS context set (e.g. a code path that forgot the middleware) THEN queries return zero rows rather than all rows.
- An isolation test harness (`tests/isolation/`) seeds two tenants × two units and is reused by every later table.

### REQ-04.04 Authorization helpers (A0) — FR-1.3
A single module provides `require_role(roles, bu_id)` used by every router.
- GIVEN a caller without an active role in `{buId}` THEN 403 `forbidden`.
- GIVEN an EA THEN they pass for any unit in their tenant.
- GIVEN a technician holding an open `review_assignment` for a scan THEN they act as `delegated_technician` for that scan only (helper exists now; used in S4).
- Every endpoint is covered by a role-boundary test generated from its `x-roles` in the contract.

### REQ-04.05 Tenant bootstrap CLI (A1) — P-1 (if approved)
- GIVEN an operator with migration credentials WHEN they run `bootstrap_tenant.py --name ... --ea-email ...` THEN a `tenant`, an `app_user` + `enterprise_admin` role, the Keycloak user with claims, and default `retention_config` rows are created, with an `audit_log` row (actor `system`).
- GIVEN the tenant already exists THEN the script exits without changes.
- The script is not reachable over HTTP.

### REQ-04.06 Synthetic seed (A2)
`seed_synthetic.py` creates the demo dataset: 2 tenants, 3 units, EA, BU Admins, technicians (fake names and numbers, test SMS destinations only), and one unit with no BU Admin. No real PPG data.

### REQ-04.07 List and read units — contracts 1.12, 1.14
- GIVEN an EA WHEN they call `GET /business-units` THEN every unit of the tenant is returned with BU Admin (or null), `waiting_count`, `escalated_count`, `locations_status`; `?no_bu_admin=true` filters vacant units.
- GIVEN a BU Admin WHEN they call it THEN only the units they run are returned.
- Counts that depend on S3–S4 tables return 0 until those tables exist **[confirm]**.

### REQ-04.08 Create unit — contract 1.13, FR-1.1
- GIVEN an EA WHEN they create a unit THEN `business_unit`, exactly one default `business_process` (`is_default = true`) and a `location_hierarchy_version` (`not_published`) are created with an `audit_log` row (`users`) in one transaction.
- GIVEN `bu_admin.invite_email` THEN an invite is created as in REQ-01.10 in the same transaction.
- GIVEN `bu_admin.user_id` of an existing BU Admin THEN the role row and `bu_admin_user_id` are set (P-10 rule).
- GIVEN a duplicate unit name in the tenant THEN 409 `duplicate-name`.
- GIVEN a non-EA caller THEN 403.

### REQ-04.09 BU Admin management — contracts 1.15–1.17, FR-1.3
- GIVEN an EA WHEN they list BU Admins THEN name, email, units, status and `last_active_at` are returned.
- GIVEN an EA WHEN they assign a unit already run by someone else THEN 409 `unit-has-bu-admin`; assigning a unit with a pending BU Admin invite cancels that invite.
- GIVEN an EA WHEN they remove a BU Admin from units THEN `user_unit_role.removed_at` is set, those units get `bu_admin_user_id = null`, the account and history stay, and an `audit_log` row (`users`) is written; removal from all units revokes every session at once.
- GIVEN `replacement_invite_email` THEN an invite is created for those units.
- GIVEN the removed admin's next call scoped to a removed unit THEN 403 within 60 seconds; their other units still work (AT-12).

### REQ-04.10 Technician management — contracts 1.18–1.19
- GIVEN a BU Admin of unit X WHEN they list technicians THEN each row shows name, email, status, units, `last_active_at` and `sign_in_locked_until` (O-13); `scans_this_month` and `active_batch_no` are 0/null until S3–S4.
- GIVEN a BU Admin WHEN they remove a technician from X THEN `user_unit_role.removed_at` is set, the technician's access to X ends within 60 seconds, open `review_assignment` rows would close with `user_removed` (S4 table; no-op until then), and an `audit_log` row (`users`) is written.
- GIVEN a BU Admin WHEN they try to remove a technician from a unit they do not run THEN 403.

---

## Out of scope for this spec
Role change (O-16), trusted-reviewer flag (O-18), location tree content (SPEC-PX-05), quota and retention screens (SPEC-PX-11).

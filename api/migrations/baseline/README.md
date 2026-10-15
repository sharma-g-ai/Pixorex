# Database baseline: Pixorex V1

SQL for all **31 tables** of the frozen **Pixorex V3 Data Model** (13 Oct 2026), with the triggers, roles, grants and row-level security the model and CONSTITUTION require. Target: **PostgreSQL 18** (decision D-03).

Tested on PostgreSQL 18.4: all files run cleanly on an empty database, and `verify_baseline.sql` passes 19 behaviour checks.

## Files

| File | What it creates | Run as |
|---|---|---|
| `setup_roles_and_database.sql` | Roles `pixorex_owner`, `pixorex_app`, `pixorex_worker` and database `pixorex`. Once per server | superuser |
| `00_foundation.sql` | `set_updated_at()` helper | `pixorex_owner` |
| `01_domain1_tenancy.sql` | tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session | `pixorex_owner` |
| `02_domain2_locations.sql` | location_hierarchy_version, location_level_rule, location_node | `pixorex_owner` |
| `03_domain3_equipment_types.sql` | equipment_type, equipment_type_version, field_definition, prompt_version, extraction_contract | `pixorex_owner` |
| `04_domain4_scans.sql` | scan, scan_photo, extraction_attempt, ai_field_value | `pixorex_owner` |
| `05_domain5_review.sql` | revision, revision_field, review_batch, review_decision, review_assignment, escalation | `pixorex_owner` |
| `06_domain6_audit_ops.sql` | audit_log (monthly partitions to Dec 2027), notification, export_job, quota_usage, retention_config, outbox_event | `pixorex_owner` |
| `07_triggers.sql` | updated_at, location freeze, field freeze, own-scan block, insert-only | `pixorex_owner` |
| `08_roles_grants.sql` | Table grants for the app and worker roles (**draft, A0**) | `pixorex_owner` |
| `09_rls.sql` | Row-level security on 29 tables (**draft, A0**) | `pixorex_owner` |
| `run_all.sql` | Runs 00 to 09 in order | `pixorex_owner` |
| `verify_baseline.sql` | 19 checks; **inserts test data, throwaway database only** | superuser |

## Set up a local database

```bash
# 1. Once, as the postgres superuser
psql -h localhost -U postgres -f api/migrations/baseline/setup_roles_and_database.sql

# 2. Local-only passwords (deployed environments get them from Vault)
psql -h localhost -U postgres -c "ALTER ROLE pixorex_owner PASSWORD 'local-only'; ALTER ROLE pixorex_app PASSWORD 'local-only'; ALTER ROLE pixorex_worker PASSWORD 'local-only';"

# 3. All tables, triggers, grants and RLS
psql -h localhost -U pixorex_owner -d pixorex -f api/migrations/baseline/run_all.sql
```

To start again from empty: `DROP DATABASE pixorex;` as postgres, then steps 1 and 3.

**Never connect the API as `postgres` or `pixorex_owner`.** The owner and superusers bypass row-level security, so isolation tests run as them would pass even if a policy were wrong. The API uses `pixorex_app`, the worker `pixorex_worker`.

## How the rules are enforced

| Rule (source) | Enforced by |
|---|---|
| A row never links to another tenant's row (model, Overview) | Composite FKs `(tenant_id, x) → (tenant_id, id)` |
| Tenant and unit isolation (CONSTITUTION §2.1–2.2) | RLS policies reading `app.tenant_id`, `app.bu_ids`, `app.is_ea`, `app.user_id`, set by the API with `SET LOCAL` per transaction |
| Locations frozen after publish (model, Domain 2) | Trigger → SQLSTATE `PX001` |
| Fields frozen after the type is published (model, Domain 3) | Trigger → `PX001` |
| Nobody decides their own scan (model, Domain 5) | Trigger → `PX002` |
| ai_field_value, revision, audit_log insert-only (CONSTITUTION §2.4) | Trigger → `PX003`, and no UPDATE/DELETE grant |
| One active BU Admin per unit, one primary unit per user, one current decision per revision, one open assignment per scan | Partial unique indexes |
| Repeated upload returns the same scan | `UNIQUE (tenant_id, client_capture_id)` |

The API maps the custom SQLSTATEs to its problem types: `PX001` → 409 `locked-after-publish`, `PX002` → 403 `own-scan`. `PX003` is never expected; it means a bug.

## Choices we made (not stated in the model)

Review these; each is a sensible default, not a documented rule.

- **IDs** default to `uuidv7()` (PostgreSQL 18): time-ordered, so indexes stay compact.
- **Email** uniqueness per tenant is case-insensitive (`lower(email)`).
- **NOT NULL** is applied wherever a value is always required by the flows; nullable only where the model or flows allow empty.
- **Uniqueness the contracts imply:** unit name per tenant (contract 1.13), field label and field_key per type (2.15), revision_no per scan, one AI value per field per attempt, one live session per user and device, one open escalation per scan and reason.
- **Checks the contracts imply:** reject needs a category (3.5), unreadable needs a reason and "other" needs a note (3.2), attempt 1 is always trigger `first`, `flag_below_confidence` between 0 and 1 (2.15).
- **Cascades:** deleting a location node removes its subtree (2.6); deleting a not-published type removes its version and fields (2.14). Both are still blocked after publish.
- **Audit partitions** exist up to Dec 2027; a scheduled job must call `create_audit_log_partition(month)` ahead of time.
- **Child tables** without `bu_id` (for example `revision`, `location_node`) are visible only when their parent row is, through an `EXISTS` on the parent.

## Open points for the team and architects

| # | Point | Why it matters |
|---|---|---|
| 1 | **Governance.** Migrations are A1 and RLS/grants are A0 (CONSTITUTION §5). These files overlap tasks PX-04-T01, PX-04-T02 and PX-07-T01 | An architect reviews them before use beyond local development |
| 2 | **`app_user.keycloak_user_id`** is in the model's diagram, but ARCHITECTURE §4.3 says "the frozen model has no Keycloak-ID column" | We followed the model (storage authority). ARCHITECTURE §4.3 needs updating |
| 3 | **Allowed values not in the model:** `tenant.package`, `tenant.status`, `business_unit.status`, `retention_config.data_kind` | Stored as free text with no check until the values are listed |
| 4 | **`record_no` (REC-90141) and `batch_no` (B-15)** generation is not specified | No default; the API must supply them. Decide the format and counter |
| 5 | **`phone_number` is unique across all tenants**, as the model says "unique" without "per tenant" | Confirm; per-tenant would allow one person in two customers |
| 6 | **Invite preview and accept** (contracts 1.6–1.7) run without a token, so there is no tenant context and RLS hides the invite | Needs a reviewed lookup path (A0) |
| 7 | **Retention purge** vs insert-only: triggers block DELETE on revision and ai_field_value | The purge design (BC-11) must account for this; audit_log ages out by dropping partitions |
| 8 | **P-10:** `business_unit.bu_admin_user_id` and the `bu_admin` row in `user_unit_role` are not checked to agree | Open in ARCHITECTURE §14 |
| 9 | **Migration tool:** the Release Plan names Alembic | These files can be the first Alembic revision, or be run as-is |

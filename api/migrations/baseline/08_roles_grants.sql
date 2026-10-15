-- =============================================================================
-- Pixorex V1 database baseline: 08 roles and grants
--
-- DRAFT FOR ARCHITECT REVIEW. DB grants are A0 (CONSTITUTION §5, BC-04):
-- human-written and reviewed by an architect before use beyond local development.
--
-- Roles (ARCHITECTURE §4.4), created once by setup_roles_and_database.sql:
--   pixorex_owner   runs these files, owns the tables, used by migrations only
--   pixorex_app     the API; cannot bypass row-level security
--   pixorex_worker  outbox worker and scheduled jobs; cannot bypass row-level security
-- =============================================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pixorex_app')
     OR NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'pixorex_worker') THEN
    RAISE EXCEPTION 'Roles pixorex_app / pixorex_worker are missing: run setup_roles_and_database.sql first';
  END IF;
END
$$;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO pixorex_app, pixorex_worker;

-- Read-only reference tables.
GRANT SELECT ON tenant, prompt_version TO pixorex_app, pixorex_worker;

-- Ordinary tables: full row access, limited by row-level security (09_rls.sql).
GRANT SELECT, INSERT, UPDATE, DELETE ON
  business_unit, business_process, app_user, user_unit_role, invite, user_session,
  location_hierarchy_version, location_level_rule, location_node,
  equipment_type, equipment_type_version, field_definition, extraction_contract,
  scan, scan_photo, extraction_attempt,
  revision_field, review_batch, review_decision, review_assignment, escalation,
  notification, export_job, quota_usage, retention_config, outbox_event
TO pixorex_app, pixorex_worker;

-- Insert-only evidence: no UPDATE or DELETE grant for any role (CONSTITUTION §2.4).
GRANT SELECT, INSERT ON ai_field_value, revision, audit_log TO pixorex_app, pixorex_worker;

-- The audit_log partitions are reached only through the parent table, so the
-- parent's row-level security always applies. No grants on audit_log_YYYY_MM.

COMMIT;

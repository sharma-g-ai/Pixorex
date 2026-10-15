-- =============================================================================
-- Pixorex V1 database baseline: 09 row-level security
--
-- DRAFT FOR ARCHITECT REVIEW. RLS policies are A0 (CONSTITUTION §2.1-2.2, §5 BC-04):
-- an architect reviews every policy, and every table needs an isolation test
-- (tenant A cannot see tenant B; unit X cannot see unit Y).
--
-- Model (ARCHITECTURE §4.4-4.5): the API middleware opens the transaction and runs
--   SET LOCAL app.tenant_id = '<uuid>';
--   SET LOCAL app.user_id   = '<uuid>';
--   SET LOCAL app.bu_ids    = '<uuid>,<uuid>';   -- units the caller may read
--   SET LOCAL app.is_ea     = 'true' | 'false';
-- Every tenant-owned table: tenant_id = app.tenant_id.
-- Unit-owned tables also: bu_id in app.bu_ids, unless app.is_ea.
-- Child tables without bu_id: visible only when their parent row is visible
-- (the parent's own policy is applied inside the EXISTS).
-- tenant and prompt_version have no RLS (exceptions named in ARCHITECTURE §4.5).
-- With no context set, every policy returns no rows.
-- =============================================================================

BEGIN;

-- Request context readers. Unset or empty settings read as null / empty / false.
CREATE OR REPLACE FUNCTION app_tenant_id() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.tenant_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION app_user_id() RETURNS uuid
LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

CREATE OR REPLACE FUNCTION app_bu_ids() RETURNS uuid[]
LANGUAGE sql STABLE AS $$
  SELECT coalesce(string_to_array(nullif(current_setting('app.bu_ids', true), ''), ',')::uuid[], '{}')
$$;

CREATE OR REPLACE FUNCTION app_is_ea() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('app.is_ea', true), '')::boolean, false) $$;

GRANT EXECUTE ON FUNCTION app_tenant_id(), app_user_id(), app_bu_ids(), app_is_ea()
  TO pixorex_app, pixorex_worker;

DO $$
DECLARE
  t text;
  -- Tenant-wide tables: tenant check only (who-may-do-what is the API's job).
  tenant_tables text[] := ARRAY['app_user', 'user_unit_role', 'user_session', 'outbox_event'];
  -- Unit-owned tables with a bu_id column.
  unit_tables text[] := ARRAY['business_process', 'invite', 'location_hierarchy_version',
                              'equipment_type', 'scan', 'review_batch', 'escalation',
                              'export_job', 'quota_usage'];
  -- Child tables: {table, fk column, parent table}.
  child_tables text[][] := ARRAY[
    ARRAY['location_level_rule',    'version_id',      'location_hierarchy_version'],
    ARRAY['location_node',          'version_id',      'location_hierarchy_version'],
    ARRAY['equipment_type_version', 'equipment_type_id', 'equipment_type'],
    ARRAY['field_definition',       'type_version_id', 'equipment_type_version'],
    ARRAY['extraction_contract',    'type_version_id', 'equipment_type_version'],
    ARRAY['scan_photo',             'scan_id',         'scan'],
    ARRAY['extraction_attempt',     'scan_id',         'scan'],
    ARRAY['ai_field_value',         'attempt_id',      'extraction_attempt'],
    ARRAY['revision',               'scan_id',         'scan'],
    ARRAY['revision_field',         'revision_id',     'revision'],
    ARRAY['review_decision',        'revision_id',     'revision'],
    ARRAY['review_assignment',      'batch_id',        'review_batch']];
  i int;
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY p_%1$s_tenant ON %1$I
         USING (tenant_id = app_tenant_id())
         WITH CHECK (tenant_id = app_tenant_id())', t);
  END LOOP;

  FOREACH t IN ARRAY unit_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY p_%1$s_unit ON %1$I
         USING (tenant_id = app_tenant_id() AND (app_is_ea() OR bu_id = ANY (app_bu_ids())))
         WITH CHECK (tenant_id = app_tenant_id() AND (app_is_ea() OR bu_id = ANY (app_bu_ids())))', t);
  END LOOP;

  FOR i IN 1 .. array_length(child_tables, 1) LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', child_tables[i][1]);
    EXECUTE format(
      'CREATE POLICY p_%1$s_parent ON %1$I
         USING (tenant_id = app_tenant_id()
                AND EXISTS (SELECT 1 FROM %3$I p WHERE p.id = %1$I.%2$I))
         WITH CHECK (tenant_id = app_tenant_id()
                AND EXISTS (SELECT 1 FROM %3$I p WHERE p.id = %1$I.%2$I))',
      child_tables[i][1], child_tables[i][2], child_tables[i][3]);
  END LOOP;
END
$$;

-- business_unit: the unit is the row itself.
ALTER TABLE business_unit ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_business_unit_unit ON business_unit
  USING (tenant_id = app_tenant_id() AND (app_is_ea() OR id = ANY (app_bu_ids())))
  WITH CHECK (tenant_id = app_tenant_id() AND app_is_ea());     -- only the EA creates or edits units

-- retention_config: tenant defaults (bu_id null) are visible to everyone in the tenant.
ALTER TABLE retention_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_retention_config_unit ON retention_config
  USING (tenant_id = app_tenant_id() AND (app_is_ea() OR bu_id IS NULL OR bu_id = ANY (app_bu_ids())))
  WITH CHECK (tenant_id = app_tenant_id() AND app_is_ea());

-- notification: each person reads and marks only their own; anyone in the tenant
-- (the API acting for a user, or the worker) may create one.
ALTER TABLE notification ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_notification_read ON notification FOR SELECT
  USING (tenant_id = app_tenant_id() AND recipient_user_id = app_user_id());
CREATE POLICY p_notification_update ON notification FOR UPDATE
  USING (tenant_id = app_tenant_id() AND recipient_user_id = app_user_id())
  WITH CHECK (tenant_id = app_tenant_id() AND recipient_user_id = app_user_id());
CREATE POLICY p_notification_insert ON notification FOR INSERT
  WITH CHECK (tenant_id = app_tenant_id());

-- audit_log: insert within the tenant; read per decision D-06 (EA every unit,
-- BU Admin the units they run). Tenant-wide rows (bu_id null) are EA only.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_audit_log_insert ON audit_log FOR INSERT
  WITH CHECK (tenant_id = app_tenant_id());
CREATE POLICY p_audit_log_read ON audit_log FOR SELECT
  USING (tenant_id = app_tenant_id() AND (app_is_ea() OR bu_id = ANY (app_bu_ids())));

-- The outbox worker claims events of every tenant, then sets the event's tenant
-- context before doing the work.
CREATE POLICY p_outbox_event_worker ON outbox_event TO pixorex_worker
  USING (true) WITH CHECK (true);

COMMIT;

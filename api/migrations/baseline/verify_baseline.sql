-- Behaviour checks for the baseline: isolation, freezes, own-scan block, insert-only.
-- INSERTS SYNTHETIC TEST DATA. Run ONLY on a throwaway database that has just had
-- setup_roles_and_database.sql + run_all.sql applied, never on a shared one.
-- Run as a superuser:  psql -U postgres -d <throwaway db> -f verify_baseline.sql
-- Every line printed must say PASS; the script stops at the first FAIL.
\set ON_ERROR_STOP on
SET client_min_messages = warning;

-- ---------- seed (as superuser, RLS not applied) ----------
INSERT INTO tenant (id, name, package, status) VALUES
 ('00000000-0000-0000-0000-00000000000a', 'Tenant A', 'standard', 'active'),
 ('00000000-0000-0000-0000-00000000000b', 'Tenant B', 'standard', 'active');
INSERT INTO business_unit (id, tenant_id, name, facility_name, status) VALUES
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Plant 04', 'F4', 'active'),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Plant 05', 'F5', 'active'),
 ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000b', 'Plant 99', 'F9', 'active');
INSERT INTO business_process (id, tenant_id, bu_id, name, is_default) VALUES
 ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'Default', true);
INSERT INTO app_user (id, tenant_id, email, full_name, status, phone_number) VALUES
 ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'ea@a.test',   'EA',     'active', NULL),
 ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'bu@a.test',   'BU',     'active', NULL),
 ('30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'tech@a.test', 'Tech',   'active', '+15550000001'),
 ('30000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000a', 'rev@a.test',  'Rev',    'active', '+15550000002');
INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role) VALUES
 ('00000000-0000-0000-0000-00000000000a', '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'bu_admin');
INSERT INTO location_hierarchy_version (id, tenant_id, bu_id) VALUES
 ('40000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001');
INSERT INTO location_level_rule (id, tenant_id, version_id, level_name, level_order, requirement) VALUES
 ('41000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000001', 'Facility', 1, 'required');
INSERT INTO location_node (id, tenant_id, version_id, level_rule_id, name, path) VALUES
 ('42000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '40000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000001', 'F4', '42000000-0000-0000-0000-000000000001');
UPDATE location_hierarchy_version SET status = 'published', tree_snapshot = '{}', published_by = '30000000-0000-0000-0000-000000000001', published_at = now()
 WHERE id = '40000000-0000-0000-0000-000000000001';
INSERT INTO equipment_type (id, tenant_id, bu_id, process_id, name, created_via) VALUES
 ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Motor', 'blank');
INSERT INTO equipment_type_version (id, tenant_id, equipment_type_id) VALUES
 ('51000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '50000000-0000-0000-0000-000000000001');
INSERT INTO field_definition (id, tenant_id, type_version_id, field_key, label, data_type, sort_order) VALUES
 ('52000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '51000000-0000-0000-0000-000000000001', 'serial', 'Serial', 'text', 1);
UPDATE equipment_type_version SET published_by = '30000000-0000-0000-0000-000000000002', published_at = now() WHERE id = '51000000-0000-0000-0000-000000000001';
UPDATE equipment_type SET status = 'published' WHERE id = '50000000-0000-0000-0000-000000000001';
INSERT INTO prompt_version (id, model_name, instructions) VALUES ('53000000-0000-0000-0000-000000000001', 'model-x', 'synthetic');
INSERT INTO extraction_contract (id, tenant_id, type_version_id, prompt_version_id) VALUES
 ('54000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '51000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000001');
INSERT INTO scan (id, tenant_id, bu_id, process_id, record_no, client_capture_id, technician_id, equipment_type_id, contract_id, location_node_id, location_path_snapshot, captured_at) VALUES
 ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'REC-1', '61000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001', 'F4', now());
INSERT INTO revision (id, tenant_id, scan_id, revision_no, origin, values_json, submitted_by) VALUES
 ('70000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '60000000-0000-0000-0000-000000000001', 1, 'technician_review', '{"serial":"X1"}', '30000000-0000-0000-0000-000000000003');
INSERT INTO audit_log (tenant_id, bu_id, actor_type, category, action, summary) VALUES
 ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', 'system', 'review', 'seed', 'Seed row for the baseline checks');

-- ---------- helper ----------
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql text, p_state text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FAIL %: no error raised', p_label;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE LIKE 'P0001' AND SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  IF p_state IS NOT NULL AND SQLSTATE <> p_state THEN
    RAISE EXCEPTION 'FAIL %: expected %, got % (%)', p_label, p_state, SQLSTATE, SQLERRM;
  END IF;
  RAISE NOTICE 'PASS %  [% %]', p_label, SQLSTATE, SQLERRM;
END $$;
SET client_min_messages = notice;

-- ---------- database rules (as superuser) ----------
SELECT pg_temp.expect_error($$INSERT INTO location_node (tenant_id, version_id, level_rule_id, name, path) VALUES ('00000000-0000-0000-0000-00000000000a','40000000-0000-0000-0000-000000000001','41000000-0000-0000-0000-000000000001','New','x')$$, 'PX001', 'location node insert blocked after publish');
SELECT pg_temp.expect_error($$UPDATE location_node SET name = 'Renamed'$$, 'PX001', 'location node rename blocked after publish');
SELECT pg_temp.expect_error($$UPDATE location_hierarchy_version SET tree_snapshot = '{"x":1}'$$, 'PX001', 'published snapshot frozen');
SELECT pg_temp.expect_error($$UPDATE field_definition SET label = 'S/N'$$, 'PX001', 'field edit blocked after type publish');
SELECT pg_temp.expect_error($$INSERT INTO review_decision (tenant_id, revision_id, decided_by, decider_role, decision) VALUES ('00000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','delegated_technician','approved')$$, 'PX002', 'own scan cannot be decided');
SELECT pg_temp.expect_error($$UPDATE revision SET values_json = '{}'$$, 'PX003', 'revision is insert-only');
SELECT pg_temp.expect_error($$DELETE FROM audit_log$$, 'PX003', 'audit_log is insert-only');
SELECT pg_temp.expect_error($$INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role) VALUES ('00000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','bu_admin')$$, '23505', 'one active BU Admin per unit');
SELECT pg_temp.expect_error($$INSERT INTO scan (tenant_id, bu_id, process_id, record_no, client_capture_id, technician_id, equipment_type_id, contract_id, location_node_id, location_path_snapshot, captured_at) VALUES ('00000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','REC-2','61000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000001','54000000-0000-0000-0000-000000000001','42000000-0000-0000-0000-000000000001','F4',now())$$, '23505', 'client_capture_id is idempotent per tenant');
SELECT pg_temp.expect_error($$INSERT INTO app_user (tenant_id, email, full_name) VALUES ('00000000-0000-0000-0000-00000000000a','EA@A.TEST','Dup')$$, '23505', 'email unique per tenant, case-insensitive');
SELECT pg_temp.expect_error($$INSERT INTO user_unit_role (tenant_id, user_id, bu_id, role) VALUES ('00000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','field_technician')$$, '23503', 'cross-tenant link impossible (composite FK)');
SELECT pg_temp.expect_error($$INSERT INTO field_definition (tenant_id, type_version_id, field_key, label, data_type, options, sort_order) VALUES ('00000000-0000-0000-0000-00000000000a','51000000-0000-0000-0000-000000000001','k','K','dropdown','["one"]',2)$$, NULL, 'dropdown needs 2+ options (or freeze)');
SELECT pg_temp.expect_error($$INSERT INTO review_decision (tenant_id, revision_id, decided_by, decider_role, decision) VALUES ('00000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','bu_admin','rejected')$$, '23514', 'reject needs a category');

-- ---------- row-level security (as pixorex_app) ----------
SET ROLE pixorex_app;
DO $$ BEGIN
  IF (SELECT count(*) FROM scan) <> 0 THEN RAISE EXCEPTION 'FAIL no context must see nothing'; END IF;
  RAISE NOTICE 'PASS no context sees no rows';
END $$;

BEGIN;
SET LOCAL app.tenant_id = '00000000-0000-0000-0000-00000000000b';
SET LOCAL app.is_ea = 'true';
DO $$ BEGIN
  IF (SELECT count(*) FROM scan) + (SELECT count(*) FROM revision) + (SELECT count(*) FROM audit_log)
     + (SELECT count(*) FROM business_unit WHERE tenant_id <> app_tenant_id()) <> 0 THEN
    RAISE EXCEPTION 'FAIL tenant B sees tenant A data'; END IF;
  RAISE NOTICE 'PASS tenant B EA cannot see tenant A scans, revisions, audit or units';
END $$;
COMMIT;

BEGIN;
SET LOCAL app.tenant_id = '00000000-0000-0000-0000-00000000000a';
SET LOCAL app.bu_ids = '10000000-0000-0000-0000-000000000002';   -- Plant 05 only
SET LOCAL app.is_ea = 'false';
DO $$ BEGIN
  IF (SELECT count(*) FROM scan) <> 0 OR (SELECT count(*) FROM revision) <> 0
     OR (SELECT count(*) FROM audit_log) <> 0 OR (SELECT count(*) FROM location_node) <> 0 THEN
    RAISE EXCEPTION 'FAIL Plant 05 user sees Plant 04 data'; END IF;
  RAISE NOTICE 'PASS unit X cannot see unit Y (scans, revisions, audit, locations)';
END $$;
SELECT pg_temp.expect_error($$INSERT INTO invite (tenant_id, bu_id, email, role, token_hash, invited_by, expires_at) VALUES ('00000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-000000000001','x@a.test','field_technician','h','30000000-0000-0000-0000-000000000002', now() + interval '1 day')$$, '42501', 'cannot write into a unit you do not hold');
COMMIT;

BEGIN;
SET LOCAL app.tenant_id = '00000000-0000-0000-0000-00000000000a';
SET LOCAL app.bu_ids = '10000000-0000-0000-0000-000000000001';   -- Plant 04
SET LOCAL app.is_ea = 'false';
DO $$ BEGIN
  IF (SELECT count(*) FROM scan) <> 1 OR (SELECT count(*) FROM revision) <> 1 OR (SELECT count(*) FROM audit_log) <> 1 THEN
    RAISE EXCEPTION 'FAIL Plant 04 user cannot see own unit data'; END IF;
  RAISE NOTICE 'PASS unit user sees own unit scans, revisions and audit';
END $$;
SELECT pg_temp.expect_error($$UPDATE ai_field_value SET value = 'x'$$, '42501', 'app role has no UPDATE on ai_field_value');
COMMIT;
RESET ROLE;

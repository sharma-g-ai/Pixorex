-- =============================================================================
-- Pixorex V1 database baseline: 07 triggers
--
-- Rules the data model says are enforced in the database:
--   1. updated_at kept current on every tenant-owned table
--   2. published locations are frozen (location_node: "A trigger blocks INSERT,
--      UPDATE and DELETE once the unit is published")
--   3. published equipment type fields are read-only ("Read-only once the type
--      is published (trigger)")
--   4. nobody decides their own scan ("decided_by <> scan's technician (trigger)")
--   5. insert-only evidence: ai_field_value, revision, audit_log (CONSTITUTION §2.4)
--
-- Errors use custom SQLSTATEs so the API can map them to its problem types:
--   PX001 -> 409 /problems/locked-after-publish
--   PX002 -> 403 /problems/own-scan
--   PX003 -> insert-only table changed (a bug, never expected from the API)
--
-- Trigger functions that read other tables are SECURITY DEFINER so row-level
-- security can never hide the row they check (a hidden row would let a change
-- through). They read only, and pin search_path.
-- =============================================================================

BEGIN;

-- 1. updated_at on every table that has the column (audit_log excluded: insert-only).
DO $$
DECLARE t text;
BEGIN
  FOR t IN
    SELECT c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables tb
      ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name
    WHERE c.table_schema = 'public'
      AND c.column_name = 'updated_at'
      AND tb.table_type = 'BASE TABLE'
      AND c.table_name NOT LIKE 'audit_log%'
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_updated_at BEFORE UPDATE ON %1$I
         FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t);
  END LOOP;
END
$$;

-- 2. Locations freeze at publish.
CREATE OR REPLACE FUNCTION block_location_change_after_publish() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM location_hierarchy_version v
    WHERE v.status = 'published'
      AND v.id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.version_id END,
                   CASE WHEN TG_OP <> 'DELETE' THEN NEW.version_id END)
  ) THEN
    RAISE EXCEPTION 'locations are locked after publish'
      USING ERRCODE = 'PX001', HINT = 'locked-after-publish';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

CREATE TRIGGER trg_location_node_freeze
  BEFORE INSERT OR UPDATE OR DELETE ON location_node
  FOR EACH ROW EXECUTE FUNCTION block_location_change_after_publish();
CREATE TRIGGER trg_location_level_rule_freeze
  BEFORE INSERT OR UPDATE OR DELETE ON location_level_rule
  FOR EACH ROW EXECUTE FUNCTION block_location_change_after_publish();

-- The published version itself: the snapshot is frozen and publish is one-way.
CREATE OR REPLACE FUNCTION block_published_location_version() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'published' THEN
    RAISE EXCEPTION 'locations are locked after publish'
      USING ERRCODE = 'PX001', HINT = 'locked-after-publish';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

CREATE TRIGGER trg_location_hierarchy_version_freeze
  BEFORE UPDATE OR DELETE ON location_hierarchy_version
  FOR EACH ROW EXECUTE FUNCTION block_published_location_version();

-- 3. Fields of a published equipment type are read-only.
CREATE OR REPLACE FUNCTION block_field_change_after_publish() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM equipment_type_version v
    WHERE v.published_at IS NOT NULL
      AND v.id IN (CASE WHEN TG_OP <> 'INSERT' THEN OLD.type_version_id END,
                   CASE WHEN TG_OP <> 'DELETE' THEN NEW.type_version_id END)
  ) THEN
    RAISE EXCEPTION 'equipment type fields are locked after publish'
      USING ERRCODE = 'PX001', HINT = 'locked-after-publish';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

CREATE TRIGGER trg_field_definition_freeze
  BEFORE INSERT OR UPDATE OR DELETE ON field_definition
  FOR EACH ROW EXECUTE FUNCTION block_field_change_after_publish();

-- 4. Nobody reviews their own scan.
CREATE OR REPLACE FUNCTION block_self_decision() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM revision r
    JOIN scan s ON s.id = r.scan_id
    WHERE r.id = NEW.revision_id
      AND s.technician_id = NEW.decided_by
  ) THEN
    RAISE EXCEPTION 'nobody reviews their own scan'
      USING ERRCODE = 'PX002', HINT = 'own-scan';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_review_decision_not_own_scan
  BEFORE INSERT OR UPDATE OF decided_by, revision_id ON review_decision
  FOR EACH ROW EXECUTE FUNCTION block_self_decision();

-- 5. Insert-only evidence tables.
CREATE OR REPLACE FUNCTION block_insert_only_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is insert-only', TG_TABLE_NAME
    USING ERRCODE = 'PX003', HINT = 'insert-only';
END
$$;

CREATE TRIGGER trg_ai_field_value_insert_only
  BEFORE UPDATE OR DELETE ON ai_field_value
  FOR EACH ROW EXECUTE FUNCTION block_insert_only_change();
CREATE TRIGGER trg_revision_insert_only
  BEFORE UPDATE OR DELETE ON revision
  FOR EACH ROW EXECUTE FUNCTION block_insert_only_change();
-- On the partitioned parent; applies to every partition.
CREATE TRIGGER trg_audit_log_insert_only
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION block_insert_only_change();

COMMIT;

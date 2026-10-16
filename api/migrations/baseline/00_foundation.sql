-- =============================================================================
-- Pixorex V1 database baseline: 00 foundation
-- Source: Pixorex V3 Data Models (31 tables, 6 domains, 13 Oct 2026)
-- Target: PostgreSQL 18 (uses the built-in uuidv7()). Run as the owner role.
-- =============================================================================

BEGIN;

-- Every tenant-owned table carries created_at and updated_at (data model, Overview).
-- This keeps updated_at current; triggers are attached in 07_triggers.sql.
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;

COMMIT;

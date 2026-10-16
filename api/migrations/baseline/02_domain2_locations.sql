-- =============================================================================
-- Pixorex V1 database baseline: 02 Domain 2, locations (3 tables)
-- location_hierarchy_version, location_level_rule, location_node
--
-- One self-referencing tree per unit, managed by the Enterprise Admin. Publishing
-- freezes the tree; the freeze triggers are in 07_triggers.sql.
-- =============================================================================

BEGIN;

-- A unit's location setup and its published snapshot. One row per unit.
CREATE TABLE location_hierarchy_version (
  id            uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id     uuid NOT NULL REFERENCES tenant (id),
  bu_id         uuid NOT NULL UNIQUE,          -- one per unit
  version_no    integer NOT NULL DEFAULT 1 CHECK (version_no = 1),
  status        text NOT NULL DEFAULT 'not_published'
                CHECK (status IN ('not_published', 'published')),
  tree_snapshot jsonb,                         -- frozen at publish; the phone caches it
  published_by  uuid,
  published_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id)        REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, published_by) REFERENCES app_user (tenant_id, id),
  CHECK (status = 'not_published'
         OR (tree_snapshot IS NOT NULL AND published_by IS NOT NULL AND published_at IS NOT NULL))
);

-- One level the EA defines (Facility, Building, Shop, Bin, Sub-bin, ...).
CREATE TABLE location_level_rule (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id   uuid NOT NULL REFERENCES tenant (id),
  version_id  uuid NOT NULL,
  level_name  text NOT NULL,
  level_order integer NOT NULL CHECK (level_order >= 1),   -- 1 = top
  requirement text NOT NULL CHECK (requirement IN ('required', 'optional', 'off')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (version_id, level_order),
  FOREIGN KEY (tenant_id, version_id) REFERENCES location_hierarchy_version (tenant_id, id),
  CHECK (level_order <> 1 OR requirement = 'required')     -- top level always required
);

-- One place at one level. parent_id is the same table.
CREATE TABLE location_node (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id      uuid NOT NULL REFERENCES tenant (id),
  version_id     uuid NOT NULL,
  level_rule_id  uuid NOT NULL,
  parent_id      uuid,                         -- null = top level
  name           text NOT NULL,
  path           text NOT NULL,                -- materialised ID path
  is_placeholder boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, version_id)    REFERENCES location_hierarchy_version (tenant_id, id),
  FOREIGN KEY (tenant_id, level_rule_id) REFERENCES location_level_rule (tenant_id, id),
  FOREIGN KEY (tenant_id, parent_id)     REFERENCES location_node (tenant_id, id)
    ON DELETE CASCADE                          -- contract 2.6: deletes the node and everything inside it
);
-- Name unique among siblings (top-level nodes count as siblings of each other).
CREATE UNIQUE INDEX uq_location_node_sibling_name
  ON location_node (version_id, parent_id, name) NULLS NOT DISTINCT;
CREATE INDEX ix_location_node_parent ON location_node (parent_id);
CREATE INDEX ix_location_node_path ON location_node (path text_pattern_ops);

COMMIT;

-- =============================================================================
-- Pixorex V1 database baseline: 03 Domain 3, equipment types and extraction contracts (5 tables)
-- equipment_type, equipment_type_version, field_definition, prompt_version, extraction_contract
--
-- A type is edited while not published; publishing locks it and creates the
-- extraction contract (type version + prompt version) that every scan pins.
-- The field freeze trigger is in 07_triggers.sql.
-- =============================================================================

BEGIN;

-- A kind of label a unit can scan (Motor Nameplate, Control Valve).
CREATE TABLE equipment_type (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id           uuid NOT NULL REFERENCES tenant (id),
  bu_id               uuid NOT NULL,
  process_id          uuid NOT NULL,           -- the unit's default process
  name                text NOT NULL,
  status              text NOT NULL DEFAULT 'not_published'
                      CHECK (status IN ('not_published', 'published')),
  created_via         text NOT NULL CHECK (created_via IN ('blank', 'copy', 'ai_assist')),
  copied_from_type_id uuid,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (bu_id, name),                        -- name unique per unit
  FOREIGN KEY (tenant_id, bu_id)               REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, process_id)          REFERENCES business_process (tenant_id, id),
  FOREIGN KEY (tenant_id, copied_from_type_id) REFERENCES equipment_type (tenant_id, id)
    ON DELETE SET NULL (copied_from_type_id),  -- deleting a draft source keeps the copy
  CHECK (created_via = 'copy' OR copied_from_type_id IS NULL)
);

-- The field list of a type, frozen at publish. One row per type for now (version 1).
CREATE TABLE equipment_type_version (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id         uuid NOT NULL REFERENCES tenant (id),
  equipment_type_id uuid NOT NULL UNIQUE,      -- "unique for now"
  version_no        integer NOT NULL DEFAULT 1 CHECK (version_no = 1),
  published_by      uuid,
  published_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, equipment_type_id) REFERENCES equipment_type (tenant_id, id)
    ON DELETE CASCADE,                         -- contract 2.14: deleting a not-published type
  FOREIGN KEY (tenant_id, published_by)      REFERENCES app_user (tenant_id, id),
  CHECK ((published_by IS NULL) = (published_at IS NULL))
);

-- One field of a type version. Read-only once the type is published (trigger).
CREATE TABLE field_definition (
  id                    uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id             uuid NOT NULL REFERENCES tenant (id),
  type_version_id       uuid NOT NULL,
  field_key             text NOT NULL,         -- key in revision.values_json
  label                 text NOT NULL,
  data_type             text NOT NULL
                        CHECK (data_type IN ('text', 'number', 'date', 'dropdown', 'boolean')),
  options               jsonb,                 -- choices for a dropdown
  is_required           boolean NOT NULL DEFAULT false,
  is_critical           boolean NOT NULL DEFAULT false,
  sort_order            integer NOT NULL,
  format_rule           text,
  is_unique_in_unit     boolean NOT NULL DEFAULT false,
  flag_below_confidence numeric(4,3) NOT NULL DEFAULT 0.85
                        CHECK (flag_below_confidence BETWEEN 0 AND 1),
  origin                text NOT NULL DEFAULT 'manual' CHECK (origin IN ('manual', 'ai_suggested')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (type_version_id, field_key),
  UNIQUE (type_version_id, label),             -- contract 2.15: label unique in the type
  FOREIGN KEY (tenant_id, type_version_id) REFERENCES equipment_type_version (tenant_id, id)
    ON DELETE CASCADE,
  -- A dropdown holds 2 or more choices (check constraint named in the model).
  CONSTRAINT ck_field_definition_dropdown_options CHECK (
    data_type <> 'dropdown'
    OR (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) >= 2)
  )
);
CREATE INDEX ix_field_definition_order ON field_definition (type_version_id, sort_order);

-- Platform-owned AI instructions and model name. Global (no tenant), managed by
-- Amzur, never edited after use, never contains client data.
-- Columns exactly as the model: created_at only.
CREATE TABLE prompt_version (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  model_name   text NOT NULL,
  instructions text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Frozen pair: one published type version + one prompt version.
CREATE TABLE extraction_contract (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id         uuid NOT NULL REFERENCES tenant (id),
  type_version_id   uuid NOT NULL,
  prompt_version_id uuid NOT NULL REFERENCES prompt_version (id),
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'retired')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (type_version_id, prompt_version_id),
  FOREIGN KEY (tenant_id, type_version_id) REFERENCES equipment_type_version (tenant_id, id)
);

COMMIT;

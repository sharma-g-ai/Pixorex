-- =============================================================================
-- Pixorex V1 database baseline: 01 Domain 1, tenancy, users and sign-in (7 tables)
-- tenant, business_unit, business_process, app_user, user_unit_role, invite, user_session
--
-- Foreign keys between tenant-owned tables include tenant_id, so a row can never
-- link to a row in another tenant (data model, Overview; US-024). Every
-- tenant-owned table therefore has UNIQUE (tenant_id, id) as a FK target.
-- =============================================================================

BEGIN;

-- The customer company and its package. Not tenant-scoped; root of every RLS policy.
-- Columns exactly as the model: no created_at / updated_at on this table.
CREATE TABLE tenant (
  id      uuid PRIMARY KEY DEFAULT uuidv7(),
  name    text NOT NULL,
  package text NOT NULL,                       -- values not listed in the model
  status  text NOT NULL                        -- values not listed in the model
);

-- A plant or division. bu_admin_user_id null = "No BU Admin".
CREATE TABLE business_unit (
  id               uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id        uuid NOT NULL REFERENCES tenant (id),
  name             text NOT NULL,
  facility_name    text NOT NULL,
  bu_admin_user_id uuid,                       -- FK to app_user added below (circular)
  status           text NOT NULL,              -- values not listed in the model
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, name)                     -- contract 1.13: 409 duplicate-name
);

-- BRD process level. One is_default = true row per unit; no process picker in the UI.
CREATE TABLE business_process (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id  uuid NOT NULL REFERENCES tenant (id),
  bu_id      uuid NOT NULL,
  name       text NOT NULL,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id) REFERENCES business_unit (tenant_id, id)
);
CREATE UNIQUE INDEX uq_business_process_one_default
  ON business_process (bu_id) WHERE is_default;

-- One person, linked to Keycloak.
CREATE TABLE app_user (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id         uuid NOT NULL REFERENCES tenant (id),
  keycloak_user_id  text UNIQUE,               -- set once the Keycloak user exists
  email             text NOT NULL,
  full_name         text NOT NULL,
  phone_number      text UNIQUE                -- E.164; technicians only, admins have none
                    CHECK (phone_number ~ '^\+[1-9][0-9]{1,14}$'),
  phone_verified_at timestamptz,
  status            text NOT NULL DEFAULT 'invited'
                    CHECK (status IN ('invited', 'active', 'removed')),
  last_bu_id        uuid,                      -- unit opened at next sign-in
  last_active_at    timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, last_bu_id) REFERENCES business_unit (tenant_id, id)
);
-- Email unique per tenant, compared case-insensitively.
CREATE UNIQUE INDEX uq_app_user_email ON app_user (tenant_id, lower(email));

ALTER TABLE business_unit
  ADD FOREIGN KEY (tenant_id, bu_admin_user_id) REFERENCES app_user (tenant_id, id);

-- Role of a user in one unit. enterprise_admin has bu_id null.
CREATE TABLE user_unit_role (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id           uuid NOT NULL REFERENCES tenant (id),
  user_id             uuid NOT NULL,
  bu_id               uuid,
  role                text NOT NULL
                      CHECK (role IN ('enterprise_admin', 'bu_admin', 'field_technician')),
  is_trusted_reviewer boolean NOT NULL DEFAULT false,
  is_primary          boolean NOT NULL DEFAULT false,
  assigned_by         uuid,
  removed_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, user_id)     REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id)       REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, assigned_by) REFERENCES app_user (tenant_id, id),
  CHECK ((role = 'enterprise_admin') = (bu_id IS NULL))
);
-- One active bu_admin per unit (partial unique index, as the model says).
CREATE UNIQUE INDEX uq_user_unit_role_one_bu_admin
  ON user_unit_role (bu_id) WHERE role = 'bu_admin' AND removed_at IS NULL;
-- is_primary: one per user.
CREATE UNIQUE INDEX uq_user_unit_role_one_primary
  ON user_unit_role (user_id) WHERE is_primary AND removed_at IS NULL;
-- One active role row per user per unit (EA rows: one per user).
CREATE UNIQUE INDEX uq_user_unit_role_active
  ON user_unit_role (user_id, bu_id) NULLS NOT DISTINCT WHERE removed_at IS NULL;
CREATE INDEX ix_user_unit_role_bu ON user_unit_role (bu_id) WHERE removed_at IS NULL;

-- Magic-link invite for a BU Admin or technician. A multi-unit invite is one row
-- per unit with the same token_hash. Only the hash is stored; single use; 24 h.
CREATE TABLE invite (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id   uuid NOT NULL REFERENCES tenant (id),
  bu_id       uuid NOT NULL,
  email       text NOT NULL,
  role        text NOT NULL CHECK (role IN ('bu_admin', 'field_technician')),
  token_hash  text NOT NULL,
  invited_by  uuid NOT NULL,
  status      text NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'accepted', 'expired', 'cancelled')),
  expires_at  timestamptz NOT NULL,            -- sent + 24 h
  accepted_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (token_hash, bu_id),
  FOREIGN KEY (tenant_id, bu_id)      REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, invited_by) REFERENCES app_user (tenant_id, id)
);
CREATE INDEX ix_invite_token_hash ON invite (token_hash);
CREATE INDEX ix_invite_bu_status ON invite (bu_id, status);

-- Which unit the user is working in, per device. revoked_at checked within 60 s.
CREATE TABLE user_session (
  id           uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id    uuid NOT NULL REFERENCES tenant (id),
  user_id      uuid NOT NULL,
  device_id    text NOT NULL,                  -- X-Device-Id
  active_bu_id uuid,
  last_seen_at timestamptz,
  revoked_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, user_id)      REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, active_bu_id) REFERENCES business_unit (tenant_id, id)
);
-- One live session per user and device.
CREATE UNIQUE INDEX uq_user_session_live
  ON user_session (user_id, device_id) WHERE revoked_at IS NULL;

COMMIT;

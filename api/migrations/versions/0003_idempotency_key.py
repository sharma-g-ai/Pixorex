"""Stored Idempotency-Keys, so a repeated create returns the first answer (contract
"Repeat-safe create"; approved by the lead, 19 Oct 2026).

A new table, outside the V3 data model until the model document adds it. One row per
(tenant, user, key) for 24 hours: which endpoint, a SHA-256 of the request, and the answer
given. Same key + same request -> that answer again; same key + another request -> 409
idempotency-conflict. Scans keep their own key, scan.client_capture_id (CONSTITUTION).

Revision ID: 0003
Revises: 0002
"""

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

SQL = """
CREATE TABLE idempotency_key (
  tenant_id     uuid NOT NULL REFERENCES tenant (id),
  user_id       uuid NOT NULL,
  key           uuid NOT NULL,
  operation     text NOT NULL,                 -- the endpoint's operationId
  request_hash  text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  status_code   integer NOT NULL CHECK (status_code BETWEEN 200 AND 299),
  headers       jsonb NOT NULL DEFAULT '{}',   -- content-type, content-disposition
  body          bytea NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, user_id, key),
  FOREIGN KEY (tenant_id, user_id) REFERENCES app_user (tenant_id, id),
  CHECK (expires_at > created_at)
);
CREATE INDEX ix_idempotency_key_expires ON idempotency_key (expires_at);

ALTER TABLE idempotency_key ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_idempotency_key_tenant ON idempotency_key
  USING (tenant_id = app_tenant_id())
  WITH CHECK (tenant_id = app_tenant_id());

GRANT SELECT, INSERT, DELETE ON idempotency_key TO pixorex_app, pixorex_worker;
"""


def upgrade() -> None:
    op.get_bind().connection.driver_connection.execute(SQL)


def downgrade() -> None:
    raise NotImplementedError("Forward-only.")

-- =============================================================================
-- Pixorex V1 database baseline: 06 Domain 6, audit, notifications, exports, quota,
-- retention (6 tables)
-- audit_log, notification, export_job, quota_usage, retention_config, outbox_event
-- =============================================================================

BEGIN;

-- Who did what, when, in which unit. Insert-only, partitioned by month on
-- occurred_at; kept 1 year online and 3 years archived (US-044, US-046).
-- The partition key must be part of the primary key.
CREATE TABLE audit_log (
  id            uuid NOT NULL DEFAULT uuidv7(),
  tenant_id     uuid NOT NULL REFERENCES tenant (id),
  bu_id         uuid,                          -- null for tenant-wide events (e.g. sign-in)
  actor_type    text NOT NULL CHECK (actor_type IN ('user', 'system')),
  actor_user_id uuid,
  category      text NOT NULL
                CHECK (category IN ('sign_in', 'users', 'locations', 'equipment_types', 'review',
                                    'override', 'escalation', 'export', 'retention')),
  action        text NOT NULL,
  object_type   text,
  object_id     uuid,
  details       jsonb,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, occurred_at),
  FOREIGN KEY (tenant_id, bu_id)         REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, actor_user_id) REFERENCES app_user (tenant_id, id)
) PARTITION BY RANGE (occurred_at);
CREATE INDEX ix_audit_log_tenant_time ON audit_log (tenant_id, occurred_at DESC);
CREATE INDEX ix_audit_log_bu_category ON audit_log (bu_id, category, occurred_at DESC);

-- Creates the monthly partition that holds p_month. A scheduled job must call
-- this ahead of time; an insert with no matching partition fails.
CREATE OR REPLACE FUNCTION create_audit_log_partition(p_month date) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end   date := (date_trunc('month', p_month) + interval '1 month')::date;
BEGIN
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log FOR VALUES FROM (%L) TO (%L)',
    'audit_log_' || to_char(v_start, 'YYYY_MM'), v_start, v_end);
END
$$;

-- Partitions from the start of the project to the end of 2027.
DO $$
DECLARE m date;
BEGIN
  FOR m IN SELECT generate_series(date '2026-10-01', date '2027-12-01', interval '1 month')::date LOOP
    PERFORM create_audit_log_partition(m);
  END LOOP;
END
$$;

-- One alert to one admin or technician. Bell panel and email; no push.
CREATE TABLE notification (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id         uuid NOT NULL REFERENCES tenant (id),
  recipient_user_id uuid NOT NULL,
  bu_id             uuid,
  kind              text NOT NULL CHECK (kind IN (
                      'scan_waiting_1d', 'scan_waiting_1w', 'scans_escalated', 'unit_no_bu_admin',
                      'escalation_reminder', 'batch_delegated', 'batch_no_progress', 'batch_reminder',
                      'batch_reassigned', 'batch_taken_back', 'scan_removed_from_batch',
                      'scan_approved', 'scan_rejected', 'decision_overridden',
                      'ea_delegated_in_unit', 'invite_expired', 'export_ready')),
  object_type       text,
  object_id         uuid,
  title             text NOT NULL,
  read_at           timestamptz,
  emailed_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, recipient_user_id) REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id)             REFERENCES business_unit (tenant_id, id)
);
CREATE INDEX ix_notification_recipient ON notification (recipient_user_id, created_at DESC);
CREATE INDEX ix_notification_unread ON notification (recipient_user_id) WHERE read_at IS NULL;

-- A CSV export request. Up to 1,000 rows are answered in the request; above
-- that queued -> ready, file in MinIO, link valid 1 h.
CREATE TABLE export_job (
  id              uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id       uuid NOT NULL REFERENCES tenant (id),
  bu_id           uuid,                        -- null for a tenant-wide EA export
  requested_by    uuid NOT NULL,
  export_kind     text NOT NULL CHECK (export_kind IN ('scans', 'audit_log')),
  filters_json    jsonb NOT NULL DEFAULT '{}', -- unit, status, dates
  options_json    jsonb NOT NULL DEFAULT '{}', -- columns, photo links
  row_count       integer CHECK (row_count >= 0),
  status          text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'ready', 'failed')),
  file_key        text,
  link_expires_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id)        REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, requested_by) REFERENCES app_user (tenant_id, id),
  CHECK (status <> 'ready' OR (file_key IS NOT NULL AND link_expires_at IS NOT NULL))
);
CREATE INDEX ix_export_job_requester ON export_job (requested_by, created_at DESC);

-- Scans used per unit per month.
CREATE TABLE quota_usage (
  id               uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id        uuid NOT NULL REFERENCES tenant (id),
  bu_id            uuid NOT NULL,
  period_month     date NOT NULL CHECK (extract(day FROM period_month) = 1),   -- first day of the month
  scans_used       integer NOT NULL DEFAULT 0 CHECK (scans_used >= 0),
  alert_level_sent integer NOT NULL DEFAULT 0 CHECK (alert_level_sent IN (0, 80, 95, 100)),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (bu_id, period_month),
  FOREIGN KEY (tenant_id, bu_id) REFERENCES business_unit (tenant_id, id)
);

-- How long each kind of data is kept. bu_id null = tenant default. The API
-- rejects values below the floor (HTTP 400).
CREATE TABLE retention_config (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id  uuid NOT NULL REFERENCES tenant (id),
  bu_id      uuid,
  data_kind  text NOT NULL,                    -- values per BRD US-046b, not listed in the model
  keep_days  integer NOT NULL CHECK (keep_days > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id) REFERENCES business_unit (tenant_id, id)
);
CREATE UNIQUE INDEX uq_retention_config_kind
  ON retention_config (tenant_id, bu_id, data_kind) NULLS NOT DISTINCT;

-- Work to run after a transaction commits: emails, texts, AI calls, exports.
-- Written in the same transaction as the change and its audit row.
CREATE TABLE outbox_event (
  id          uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id   uuid NOT NULL REFERENCES tenant (id),
  event_type  text NOT NULL,
  payload     jsonb NOT NULL,
  status      text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'failed')),
  attempts    integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_run_at timestamptz NOT NULL DEFAULT now(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id)
);
-- The worker claims due rows with FOR UPDATE SKIP LOCKED.
CREATE INDEX ix_outbox_event_due ON outbox_event (next_run_at) WHERE status = 'pending';

COMMIT;

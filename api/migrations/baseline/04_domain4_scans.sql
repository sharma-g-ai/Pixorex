-- =============================================================================
-- Pixorex V1 database baseline: 04 Domain 4, scans, photos and extraction (4 tables)
-- scan, scan_photo, extraction_attempt, ai_field_value
--
-- A scan carries two independent statuses: processing (upload and AI) and review
-- (business approval). At most 3 extraction attempts per scan in total.
-- =============================================================================

BEGIN;

-- One capture of one piece of equipment (REC-90141).
CREATE TABLE scan (
  id                     uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id              uuid NOT NULL REFERENCES tenant (id),
  bu_id                  uuid NOT NULL,        -- unit active when captured
  process_id             uuid NOT NULL,
  record_no              text NOT NULL,        -- display number, e.g. REC-90141
  client_capture_id      uuid NOT NULL,        -- generated on the phone; makes uploads idempotent
  technician_id          uuid NOT NULL,
  equipment_type_id      uuid NOT NULL,        -- changes only on a re-extract
  contract_id            uuid NOT NULL,        -- changes only on a re-extract
  location_node_id       uuid NOT NULL,
  location_path_snapshot text NOT NULL,        -- full path as it was at capture
  processing_status      text NOT NULL DEFAULT 'uploading'
                         CHECK (processing_status IN ('queued_on_phone', 'uploading', 'extracting',
                                                      'ready_to_review', 'failed', 'retake_required')),
  review_status          text NOT NULL DEFAULT 'draft'
                         CHECK (review_status IN ('draft', 'waiting_for_approval', 'approved',
                                                  'rejected', 'closed', 'discarded')),
  retake_of_scan_id      uuid,                 -- links a retake to the closed original
  captured_at            timestamptz NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, record_no),
  UNIQUE (tenant_id, client_capture_id),       -- a repeated upload returns the existing scan
  FOREIGN KEY (tenant_id, bu_id)             REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, process_id)        REFERENCES business_process (tenant_id, id),
  FOREIGN KEY (tenant_id, technician_id)     REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, equipment_type_id) REFERENCES equipment_type (tenant_id, id),
  FOREIGN KEY (tenant_id, contract_id)       REFERENCES extraction_contract (tenant_id, id),
  FOREIGN KEY (tenant_id, location_node_id)  REFERENCES location_node (tenant_id, id),
  FOREIGN KEY (tenant_id, retake_of_scan_id) REFERENCES scan (tenant_id, id),
  CHECK (retake_of_scan_id IS NULL OR retake_of_scan_id <> id)
);
CREATE INDEX ix_scan_bu_review ON scan (bu_id, review_status);
CREATE INDEX ix_scan_technician ON scan (technician_id, updated_at DESC);
CREATE INDEX ix_scan_retake_of ON scan (retake_of_scan_id) WHERE retake_of_scan_id IS NOT NULL;

-- 1 to 4 photos of a scan. Bytes in MinIO at /{tenant}/{bu}/{scan}/{photo_no};
-- only the key and SHA-256 are stored.
CREATE TABLE scan_photo (
  id         uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id  uuid NOT NULL REFERENCES tenant (id),
  scan_id    uuid NOT NULL,
  photo_no   integer NOT NULL CHECK (photo_no BETWEEN 1 AND 4),
  object_key text NOT NULL,
  sha256     text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (scan_id, photo_no),
  FOREIGN KEY (tenant_id, scan_id) REFERENCES scan (tenant_id, id)
);

-- One call through the AI Inference Proxy. attempt_no 1 to 3 per scan across
-- all types, then retake only.
CREATE TABLE extraction_attempt (
  id                    uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id             uuid NOT NULL REFERENCES tenant (id),
  scan_id               uuid NOT NULL,
  attempt_no            integer NOT NULL CHECK (attempt_no BETWEEN 1 AND 3),
  contract_id           uuid NOT NULL,         -- the contract this attempt used
  trigger               text NOT NULL CHECK (trigger IN ('first', 'retry', 're_extract')),
  status                text NOT NULL DEFAULT 'queued'
                        CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'timed_out')),
  detected_label        text,                  -- drives the Type mismatch screen
  suggested_type_id     uuid,
  suggestion_confidence numeric(4,3),
  tokens_in             integer CHECK (tokens_in >= 0),     -- billing (US-018b)
  tokens_out            integer CHECK (tokens_out >= 0),
  cost                  numeric(12,6) CHECK (cost >= 0),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (scan_id, attempt_no),
  FOREIGN KEY (tenant_id, scan_id)           REFERENCES scan (tenant_id, id),
  FOREIGN KEY (tenant_id, contract_id)       REFERENCES extraction_contract (tenant_id, id),
  FOREIGN KEY (tenant_id, suggested_type_id) REFERENCES equipment_type (tenant_id, id),
  CHECK ((attempt_no = 1) = (trigger = 'first'))
);
CREATE INDEX ix_extraction_attempt_status ON extraction_attempt (status)
  WHERE status IN ('queued', 'running');

-- The AI's answer for one field, never edited (insert-only, see 07_triggers.sql).
CREATE TABLE ai_field_value (
  id                  uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id           uuid NOT NULL REFERENCES tenant (id),
  attempt_id          uuid NOT NULL,
  field_definition_id uuid NOT NULL,
  value               text,
  confidence          numeric(4,3),            -- null when the model gives no score
  flag_reasons        text[] NOT NULL DEFAULT '{}'
                      CHECK (flag_reasons <@ ARRAY['low_confidence', 'format_failed', 'no_confidence',
                                                   'missing_required', 'critical_not_found']::text[]),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (attempt_id, field_definition_id),
  FOREIGN KEY (tenant_id, attempt_id)          REFERENCES extraction_attempt (tenant_id, id),
  FOREIGN KEY (tenant_id, field_definition_id) REFERENCES field_definition (tenant_id, id)
);

COMMIT;

-- =============================================================================
-- Pixorex V1 database baseline: 05 Domain 5, review, delegation and escalation (6 tables)
-- revision, revision_field, review_batch, review_decision, review_assignment, escalation
--
-- Every technician check is an immutable revision; every approve or reject is a
-- decision on one exact revision. Delegation, reassignment, take-back, override
-- and escalation are rows, never overwritten statuses.
-- The self-decision and insert-only triggers are in 07_triggers.sql.
-- =============================================================================

BEGIN;

-- A frozen set of values a technician sends for approval. Insert-only.
CREATE TABLE revision (
  id                    uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id             uuid NOT NULL REFERENCES tenant (id),
  scan_id               uuid NOT NULL,
  revision_no           integer NOT NULL CHECK (revision_no >= 1),
  origin                text NOT NULL CHECK (origin IN ('technician_review', 'rejection_fix')),
  values_json           jsonb NOT NULL,        -- final values by field_key
  empty_required_fields text[] NOT NULL DEFAULT '{}',   -- "Submit anyway"
  submitted_by          uuid NOT NULL,         -- the scan's own technician
  resubmit_to_user_id   uuid,                  -- reviewer a fixed scan goes back to
  submitted_at          timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (scan_id, revision_no),
  FOREIGN KEY (tenant_id, scan_id)             REFERENCES scan (tenant_id, id),
  FOREIGN KEY (tenant_id, submitted_by)        REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, resubmit_to_user_id) REFERENCES app_user (tenant_id, id),
  CHECK (jsonb_typeof(values_json) = 'object')
);

-- The technician's verdict on one field.
CREATE TABLE revision_field (
  id                 uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id          uuid NOT NULL REFERENCES tenant (id),
  revision_id        uuid NOT NULL,
  ai_field_value_id  uuid,                     -- links to the untouched AI value
  field_key          text NOT NULL,
  value              text,
  verification_state text NOT NULL
                     CHECK (verification_state IN ('accepted', 'corrected', 'unreadable', 'left_empty')),
  unreadable_reason  text CHECK (unreadable_reason IN ('label_worn', 'not_on_nameplate',
                                                        'covered_or_unreachable', 'other')),
  note               text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (revision_id, field_key),
  FOREIGN KEY (tenant_id, revision_id)       REFERENCES revision (tenant_id, id),
  FOREIGN KEY (tenant_id, ai_field_value_id) REFERENCES ai_field_value (tenant_id, id),
  -- unreadable needs a reason; "other" needs a note (contract 3.2)
  CHECK ((verification_state = 'unreadable') = (unreadable_reason IS NOT NULL)),
  CHECK (unreadable_reason IS DISTINCT FROM 'other' OR nullif(btrim(note), '') IS NOT NULL)
);

-- A delegated batch (B-15) given to one trusted technician. 1 to 50 scans.
CREATE TABLE review_batch (
  id                uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id         uuid NOT NULL REFERENCES tenant (id),
  bu_id             uuid NOT NULL,
  batch_no          text NOT NULL,             -- display number, e.g. B-15
  assigned_to       uuid NOT NULL,             -- one technician
  created_by        uuid NOT NULL,             -- BU Admin or EA
  status            text NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'completed', 'taken_back')),
  reminded_at       timestamptz,
  take_back_message text,
  alert_1d_at       timestamptz,               -- stop repeat no-progress alerts
  alert_1w_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  UNIQUE (tenant_id, batch_no),
  FOREIGN KEY (tenant_id, bu_id)       REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, assigned_to) REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, created_by)  REFERENCES app_user (tenant_id, id)
);
CREATE INDEX ix_review_batch_bu_status ON review_batch (bu_id, status);
CREATE INDEX ix_review_batch_assigned ON review_batch (assigned_to) WHERE status = 'active';

-- One approve or reject on one revision. Override inserts a new row.
CREATE TABLE review_decision (
  id                    uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id             uuid NOT NULL REFERENCES tenant (id),
  revision_id           uuid NOT NULL,
  decided_by            uuid NOT NULL,         -- never the scan's technician (trigger)
  decider_role          text NOT NULL
                        CHECK (decider_role IN ('bu_admin', 'enterprise_admin', 'delegated_technician')),
  decision              text NOT NULL CHECK (decision IN ('approved', 'rejected')),
  reject_category       text CHECK (reject_category IN ('image_unclear', 'data_correction_needed',
                                                        'wrong_equipment_type', 'other')),
  note                  text,
  is_current            boolean NOT NULL DEFAULT true,
  overrides_decision_id uuid,
  batch_id              uuid,                  -- set when decided inside a delegated batch
  decided_at            timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, revision_id)           REFERENCES revision (tenant_id, id),
  FOREIGN KEY (tenant_id, decided_by)            REFERENCES app_user (tenant_id, id),
  FOREIGN KEY (tenant_id, overrides_decision_id) REFERENCES review_decision (tenant_id, id),
  FOREIGN KEY (tenant_id, batch_id)              REFERENCES review_batch (tenant_id, id),
  -- reject needs a category; approve has none (contract 3.5)
  CHECK ((decision = 'rejected') = (reject_category IS NOT NULL))
);
-- One current decision per revision: first decider wins.
CREATE UNIQUE INDEX uq_review_decision_current
  ON review_decision (revision_id) WHERE is_current;

-- One scan inside a batch. One assigned row per scan at a time.
CREATE TABLE review_assignment (
  id             uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id      uuid NOT NULL REFERENCES tenant (id),
  batch_id       uuid NOT NULL,
  scan_id        uuid NOT NULL,
  assigned_to    uuid NOT NULL,
  status         text NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'decided', 'removed')),
  removed_reason text CHECK (removed_reason IN ('taken_back', 'reassigned', 'admin_decided', 'user_removed')),
  removed_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, batch_id)    REFERENCES review_batch (tenant_id, id),
  FOREIGN KEY (tenant_id, scan_id)     REFERENCES scan (tenant_id, id),
  FOREIGN KEY (tenant_id, assigned_to) REFERENCES app_user (tenant_id, id),
  CHECK ((status = 'removed') = (removed_reason IS NOT NULL)),
  CHECK ((status = 'removed') = (removed_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_review_assignment_open
  ON review_assignment (scan_id) WHERE status = 'assigned';
CREATE INDEX ix_review_assignment_batch ON review_assignment (batch_id);

-- A scan handed to the Enterprise Admin. Created by the scheduled job once a
-- scan has waited 24 h; resolved by the first decision.
CREATE TABLE escalation (
  id                      uuid PRIMARY KEY DEFAULT uuidv7(),
  tenant_id               uuid NOT NULL REFERENCES tenant (id),
  bu_id                   uuid NOT NULL,
  scan_id                 uuid NOT NULL,
  reason                  text NOT NULL CHECK (reason IN ('not_approved_24h', 'no_bu_admin')),
  escalated_at            timestamptz NOT NULL DEFAULT now(),
  reminded_at             timestamptz,         -- EA pressed Remind
  resolved_by_decision_id uuid,
  resolved_at             timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, id),
  FOREIGN KEY (tenant_id, bu_id)                   REFERENCES business_unit (tenant_id, id),
  FOREIGN KEY (tenant_id, scan_id)                 REFERENCES scan (tenant_id, id),
  FOREIGN KEY (tenant_id, resolved_by_decision_id) REFERENCES review_decision (tenant_id, id),
  CHECK ((resolved_by_decision_id IS NULL) = (resolved_at IS NULL))
);
-- At most one open escalation per scan and reason (a resubmitted scan can escalate again).
CREATE UNIQUE INDEX uq_escalation_open_scan_reason
  ON escalation (scan_id, reason) WHERE resolved_at IS NULL;
CREATE INDEX ix_escalation_open ON escalation (bu_id) WHERE resolved_at IS NULL;

COMMIT;

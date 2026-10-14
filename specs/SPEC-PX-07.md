# SPEC-PX-07 — Audit, outbox & notifications

| Field | Value |
|---|---|
| Bounded context | BC-07 |
| Grade | A1 (audit write path, grants and partitioning human-reviewed) |
| PRD | FR-6.1, FR-6.2, FR-6.3 |
| Contracts | 3.19–3.22 (S4) |
| Release tests | AT-15 |
| Sprint | **S2: REQ-07.01–07.04 (foundation)** · S4: REQ-07.05–07.06 |
| Status | Draft — awaiting G1 |

Sprint 2 needs only the foundation: every Slice 1 write must audit, and invite emails go through the outbox.

---

## Requirements

### REQ-07.01 audit_log table (A1) — FR-6.1
Created per the Data Models document, partitioned by month, with categories `sign_in, users, locations, equipment_types, review, override, escalation, export, retention` and actor type `user` or `system`.
- GIVEN the API role WHEN it tries UPDATE or DELETE on `audit_log` THEN the database refuses (no grant).
- GIVEN a write in a month with no partition THEN it succeeds (partitions created ahead by migration or job).
- RLS: tenant-scoped; readable by EA only (enforced at the API in S4, by policy now).

### REQ-07.02 Audit writer (A1)
One service function `audit.record(category, action, object_type, object_id, details)` that uses the current transaction and request context.
- GIVEN a service write marked *Audit* WHEN the transaction commits THEN exactly one audit row exists for it.
- GIVEN the business write fails and rolls back THEN no audit row exists.
- GIVEN `details` THEN it never contains tokens, codes, secrets or invite tokens (test with a denylist).

### REQ-07.03 outbox_event + enqueue (A1) — FR-6.2
- GIVEN a service that needs an external effect WHEN it calls `outbox.enqueue(kind, payload, correlation_id)` THEN the row is written in the same transaction as the change and its audit row.
- GIVEN a rollback THEN no outbox row exists and nothing is sent.

### REQ-07.04 Outbox worker + email adapter (A2) — FR-6.2, AT-15
- GIVEN a pending event WHEN the worker runs THEN it claims it with `FOR UPDATE SKIP LOCKED`, executes it and records success with the correlation id.
- GIVEN a transient failure (e.g. SMTP timeout) THEN it retries with exponential backoff up to **[TBD: 8]** times, then marks the event failed and logs it.
- GIVEN two workers THEN no event is executed twice concurrently; handlers are idempotent on the event id.
- GIVEN an `invite_email` event locally THEN the email arrives in Mailpit with the magic link.

### REQ-07.05 Notifications (S4) — FR-6.3, contracts 3.19–3.21
17 kinds, bell panel + email, no push. Specified at S4 G1.

### REQ-07.06 Audit log read (S4) — contract 3.22
Specified at S4 G1.

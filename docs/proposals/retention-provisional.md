# Retention: provisional values (proposal, 21 Oct 2026)

For the lead to confirm or change. Nothing is built until it is agreed. Sources: PRD FR-6.1, FR-6.6, AT-16, MOB-04, open item 2; data model "Pixorex V1 — Data Model Implementation" (`retention_config`).

## 1. What is kept, and for how long

The **default** is from the PRD. The **minimum** (floor) is a proposal: a unit or company can keep data longer, never shorter (a lower value → HTTP 400).

| Data class | Default (PRD) | Proposed minimum | What happens when it expires |
|---|---|---|---|
| `source_images` (scan photos) | 30 days | 30 days | Photo files deleted from storage. The scan and its values stay. |
| `ai_attempts` (raw AI answers, tokens, cost) | 90 days | 90 days | See question 3: today the database can't delete them. |
| `approved_records` (scan, revisions, decisions) | 7 years | 7 years | Deleted, unless under legal hold. |
| `revision_history` | 7 years | 7 years | Deleted with its record. |
| `user_accounts` (after removal) | 90 days | 90 days | Name, email and phone replaced by "Removed user"; the id stays so history still adds up. |
| `audit_logs` | 1 year online + 3 years archived | Same (PRD: can't be lowered) | Moved to archive after 1 year, deleted after 4. |
| `mobile_queue` (on the phone) | — | Never deleted automatically | MOB-04: no silent deletion by age. |

## 2. How it runs

- One job, once a day, in the existing worker.
- Records under **legal hold** are skipped, whatever their age (AT-16).
- Every purge writes an audit row (category `retention`), e.g. "Deleted 12 photos older than 30 days".

## 3. Questions to confirm

1. **Legal hold:** add a flag on a scan (`legal_hold`, with who set it, when and why). Only the Enterprise Admin can set or clear it. OK?
2. **Table shape:** our database has `retention_config(data_kind, keep_days)`; the data model document has `data_class, retention_value, retention_unit, purge_mode, floor_value, floor_unit`. We propose to follow the data model document. OK?
3. **AI attempts:** the raw AI answers are linked to the technician's verified values, and the database forbids deleting them (insert-only evidence). Option A: keep them for the life of the record (7 years). Option B: change the data model so they can be deleted after 90 days. Which one?
4. **When the 30-day photo clock starts** (PRD open item 2): we propose from approval, so reviewers always have the photo while a scan is waiting. Photo links in an export made before deletion stop working after deletion.
5. **Approved records after 7 years:** delete fully (proposed), or keep the values and remove only personal details?

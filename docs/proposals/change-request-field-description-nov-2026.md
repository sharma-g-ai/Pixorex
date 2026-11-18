# Change request: field description replaces "format check" and "critical"

| | |
|---|---|
| Date | 18 Nov 2026 |
| Status | **Draft, waiting for approval. No work on the database, contracts or code starts before this is approved.** |
| Raised by | Divya Amrutha Yalla, from the 18 Nov 2026 stand-up |
| Needs approval from | The owner and the Technical Architects (Geetashish Sharma, Suchith Veeramalla), per CONSTITUTION rule 3 |
| Affects | Table `field_definition` (BC-06 Equipment types), the extraction prompt (BC-03, A1), the S3 contract, web and mobile |

## 1. What is asked

Change one table, `field_definition`:

| Column | Change |
|---|---|
| `format_rule` (text, null) | **Drop** |
| `is_critical` (boolean, not null, default false) | **Drop** |
| `description` (text, null) | **Add.** Plain text, optional, at most 500 characters |

No new table. No change to any other table.

## 2. Why

Agreed at the 18 Nov 2026 stand-up (Geetashish approved, pending Suchith's review):

- **Critical** adds almost nothing. Every field whose AI confidence is below its "Flag below confidence" number is already flagged, critical or not. Critical only added a second flag when an *optional* field came back empty.
- **Format check** is free text that is only passed to the AI as a hint. Nothing in the system enforces it, and the hint is easy to mis-read ("UN + 4 digits").
- A **description** says in plain words what the field is ("Purchase order number printed on the label"). It does the same job as the format hint, helps the AI find the right value, and is easier for a BU Admin to write.

## 3. What does not change

- No RLS policy, grant or role changes (A0 files untouched). `field_definition` keeps its existing policy.
- The freeze trigger `trg_field_definition_freeze` stays as it is. DDL (add or drop a column) does not fire it.
- The flag reasons `critical_not_found` and `format_failed` stay in the allowed values of `ai_field_value.flag_reasons`. Stored scans use them. New scans stop getting `critical_not_found`; `format_failed` still means "the value does not fit the field type (number, date, and so on)".
- Published types keep working. Their fields simply lose the two old columns.

## 4. Data impact

Values in `format_rule` and `is_critical` are lost when the columns are dropped. Before the drop, run:

```sql
SELECT count(*) FILTER (WHERE is_critical)          AS critical_fields,
       count(*) FILTER (WHERE format_rule IS NOT NULL) AS fields_with_format_rule
FROM field_definition;
```

No backfill of `format_rule` into `description` is proposed. Fields of published types are protected by the freeze trigger, so an UPDATE would fail, and disabling that trigger inside a migration is not worth it. If anyone needs the old texts, export them before the drop.

## 5. Migration plan (expand, then contract)

Forward-only, plain SQL, run as `pixorex_owner` (project rule). The next free number is `0007` (latest today is `0006`).

1. **`0007` (expand):** `ALTER TABLE field_definition ADD COLUMN description text CHECK (char_length(description) <= 500);` In the same release, API and worker stop reading `format_rule` and `is_critical`, and the API keeps returning `is_critical: false` (marked deprecated in the contract) so older mobile builds keep working.
2. **Ship web and mobile** that no longer use the two old fields.
3. **`0008` (contract):** `ALTER TABLE field_definition DROP COLUMN format_rule, DROP COLUMN is_critical;` The API stops returning `is_critical`.

There is no down migration. Rollback means restoring from backup. Do step 3 only after step 2 is live everywhere.

## 6. Code and contracts affected

- **Database:** migrations `0007` and `0008`. `migrations/baseline/` is not edited (a fresh database gets the baseline, then the migrations). `verify_baseline.sql` to be checked for references.
- **Contract S3** (`contracts/slice-s3-capture-extraction.yaml`) and `docs/api-contracts.md`: remove `is_critical` and `format_rule` from the field schemas and the scan review field, add `description`. Then `npm run api:types`.
- **API:** `services/equipment_types.py`, `repositories/equipment_types.py`, `services/scans.py`, `repositories/scans.py`, `services/ai_proxy.py`, `workers/extraction.py`, and their tests.
- **Extraction prompt (BC-03, A1, needs human review):** send `description` instead of `format_rule`; remove the `format_ok` answer. The description is text written by a BU Admin and goes into the prompt as data, so it is length-capped and treated as data like the photos.
- **AI assisted schema discovery (contract 2.20):** each suggested field also returns a `description`, written by the AI. `SUGGEST_PROMPT` asks for it: what the field is and where it sits on the label, in general words, never the value read from that photo (so one photo does not bias later scans). The BU Admin can edit it before the type is created; it is saved in `field_definition.description`. This prompt is also BC-03, A1.
- **Web:** Add field popup, field table, field rules and tests; the "Format check failed" wording becomes "Doesn't match the field type".
- **Mobile:** `capture_models.dart` and `scan_models.dart` read `is_critical` as required. They must stop reading it **before** step 3, or every scan screen fails to parse. The "Format check failed" label in `review_model.dart` changes too.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Old mobile build breaks when `is_critical` disappears | Step 1 keeps `is_critical: false`; step 3 only after mobile ships |
| API, worker and migration deployed out of order | Expand then contract: code stops using old columns before they are dropped |
| Old format rules or critical flags are wanted later | Export before step 3 (section 4) |
| Prompt change lowers extraction quality | A1 review by Geetashish and Suchith; test on real nameplates before release |

## 8. Verification

- **Fields API:** create, update, copy and AI-assist save and return `description`; empty becomes null; over 500 characters is refused; the old fields are gone.
- **Suggest fields:** with a mocked provider, every suggested field has a description and it does not contain the value printed on the photo; a missing or odd description is cleaned up, not an error.
- **Extraction request:** with a mocked provider, the request sent to the AI carries each field's description and no format rule.
- **Flags against the threshold** (unit test of `flags_for`, then end to end through the worker): thresholds 0%, 50%, 85% and 100% against confidences just below, equal to and above each; below is flagged `low_confidence`, equal or above is not; no confidence gives `no_confidence`; an empty required field gives `missing_required`; a value that does not fit its type gives `format_failed`; `critical_not_found` never appears on new scans.
- **Stored data:** after a scan, `ai_field_value` holds the value, confidence and flag reasons exactly as the worker decided them, insert-only.
- **Shown data:** the scan review API returns the same values, confidence and flags, and the web scan page and the mobile review screen render them (component tests on both).
- **Live check** on the local stack with the OpenAI key: create a type with AI assisted schema discovery from a real label photo, publish it, scan two other labels of the same kind, and compare values, confidence and flags with the database and both screens.
- Contract lint (spectral baseline unchanged), web vitest, `flutter test`.

## 9. Approvals

- [ ] Owner
- [ ] Technical Architect: Geetashish Sharma
- [ ] Technical Architect: Suchith Veeramalla

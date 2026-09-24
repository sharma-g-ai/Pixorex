# Supabase Storage & Data Architecture

This design is for a **central repository accessible to the client** after extraction and review. It supports both:
- industrial equipment records such as nameplates / data plates
- grouped product-label records such as paint cans with `1 to 3` images per logical item

## Why Move from Sheets

Google Sheets is currently acting as file tracker, staging DB, review tool, and final repository. That's too many jobs for one tool. Supabase separates these cleanly:

| Concern | Sheets (current) | Supabase (proposed) |
|---------|:-:|:-:|
| Image storage | External (local/drive) | **Supabase Storage** with CDN + signed URLs |
| Extraction history | Overwritten each run | **extraction_runs** table — every model call preserved |
| Current machine output | One sheet, latest only | **record_current** — staging, flagged for review |
| Approved client data | Same sheet | **record_approved** — separate, clean, read-only |
| Multi-image grouping | Manual naming | **record_images** — 1:N relationship |
| Audit trail | None | **field_reviews** — per-field approval history |
| Client access | Share link | **RLS-protected views** or API |

---

## Data Model

### Bronze / Silver / Gold Layers

```
Bronze (raw)          Silver (machine)         Gold (approved)
─────────────         ────────────────         ───────────────
Storage: scans/       record_current           record_approved
extraction_runs       ├ fields jsonb           ├ approved_fields jsonb
├ raw_output_text     ├ extra_fields jsonb     ├ approved_by
├ parsed_output       └ review_required        └ approved_at
└ normalized_output
```

---

## Tables

### 1. `records`

One row per logical item (one nameplate, one label, one can group).

```sql
create table records (
    id              uuid primary key default gen_random_uuid(),
    client_id       uuid not null,        -- tenant / customer owning the record
    record_type     text not null,        -- 'nameplate', 'product_label', 'equipment_label', 'hvac_chiller'
    schema_name     text not null,        -- 'universal_v2.1', 'product_label_v1', etc.
    schema_version  text not null,        -- '2.1', '1.0', etc.
    source          text default 'upload', -- 'upload', 'api', 'google_sheet', 'mobile_capture'
    source_ref      text,                  -- original filename, sheet row, external ID
    status          text not null default 'uploaded'
                    check (status in ('uploaded', 'extracting', 'extracted', 'review_required', 'approved', 'rejected')),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index idx_records_client_type_status on records(client_id, record_type, status);
create index idx_records_created on records(created_at desc);
```

### 2. `record_images`

One row per image in the group. A motor nameplate might have 1 image. A product can might have 3 (front, back, side).

```sql
create table record_images (
    id              uuid primary key default gen_random_uuid(),
    record_id       uuid not null references records(id) on delete cascade,
    image_order     int not null default 1,
    panel_hint      text default 'unknown',  -- 'front', 'back', 'side', 'closeup', 'unknown'
    storage_path    text not null,            -- path in Supabase Storage: 'scans/{record_id}/{filename}'
    public_url      text,                     -- signed or public CDN URL
    sha256          text,
    width_px        int,
    height_px       int,
    quality_metrics jsonb,                    -- laplacian, dynamic_range, glare, warnings from preprocessing
    created_at      timestamptz not null default now()
);

create index idx_record_images_record on record_images(record_id, image_order);
```

### 3. `extraction_runs`

Every model call is stored. Never overwritten. This is the audit trail.

```sql
create table extraction_runs (
    id                  uuid primary key default gen_random_uuid(),
    record_id           uuid not null references records(id) on delete cascade,
    image_id            uuid references record_images(id),  -- which image was sent (null = grouped)

    -- Model details
    provider            text not null,          -- 'openai', 'openrouter', 'local_ocr'
    model               text not null,          -- 'gpt-5.4', 'gpt-4.1', 'rapidocr', 'paddleocr'
    method              text not null,          -- 'vision_direct', 'ocr_rule_mapping', 'ocr_llm_mapping', 'tatr_cell_ocr'
    prompt_name         text,                   -- 'poc_production_prompt_v3'
    prompt_hash         text,                   -- sha256 of prompt text for reproducibility
    schema_name         text,                   -- schema used for this run
    schema_version      text,                   -- version used for this run
    input_image_count   int not null default 1, -- supports grouped 1..3 image records

    -- Outputs
    raw_output_text     text,                   -- raw model response
    parsed_output       jsonb,                  -- schema-parsed extraction
    normalized_output   jsonb,                  -- cleaned/normalized version

    -- Metadata
    preprocessing       text,                   -- which variant: 'original', 'flattened', 'inverted_clahe'
    response_id         text,                   -- OpenAI response ID
    latency_ms          int,
    token_count         int,
    cost_usd            numeric(8,6),
    error               text,

    created_at          timestamptz not null default now()
);

create index idx_extraction_runs_record on extraction_runs(record_id, created_at desc);
create index idx_extraction_runs_model on extraction_runs(model, method);
```

### 4. `record_current`

Latest working extraction result. One row per record. This is the Silver layer — machine output ready for review.

```sql
create table record_current (
    record_id           uuid primary key references records(id) on delete cascade,
    extraction_run_id   uuid references extraction_runs(id),  -- which run produced this

    -- Extracted fields (schema-specific)
    fields              jsonb not null default '{}',        -- fixed fields for the active schema
    extra_fields        jsonb not null default '{}',        -- dynamic overflow fields

    -- Review state
    filled_field_count  int not null default 0,            -- maintained by app or trigger
    review_required     boolean not null default true,
    review_notes        text,
    confidence_score    numeric(5,3),                       -- composite: ocr_confidence + field_validation + cross_method_agreement

    updated_at          timestamptz not null default now()
);

-- Fast lookup for fields
create index idx_record_current_fields_gin on record_current using gin(fields);
create index idx_record_current_manufacturer on record_current ((fields->>'manufacturer'));
create index idx_record_current_serial on record_current ((fields->>'serial_no'));
create index idx_record_current_model on record_current ((fields->>'model_no'));
```

### 5. `record_approved`

Gold layer. Only human-reviewed, approved data lives here. This is what the client sees.

```sql
create table record_approved (
    record_id               uuid primary key references records(id) on delete cascade,
    approved_fields         jsonb not null default '{}',
    approved_extra_fields   jsonb not null default '{}',
    approved_by             text,
    approved_at             timestamptz,
    approval_notes          text
);

create index idx_record_approved_gin on record_approved using gin(approved_fields);
```

### 6. `field_reviews` (optional — per-field audit trail)

For cases where a human corrects individual fields rather than approving the whole record.

```sql
create table field_reviews (
    id              uuid primary key default gen_random_uuid(),
    record_id       uuid not null references records(id) on delete cascade,
    field_name      text not null,
    extracted_value text,
    approved_value  text,
    status          text not null default 'pending'
                    check (status in ('pending', 'approved', 'corrected', 'rejected')),
    reason          text,
    reviewed_by     text,
    reviewed_at     timestamptz default now()
);

create index idx_field_reviews_record on field_reviews(record_id, field_name);
```

---

## Storage Layout

```
supabase-storage/
  scans/
    {record_id}/
      original.jpg              -- raw upload
      preprocessed/
        00_original.png
        03_flattened.png
        04_clahe.png
        11_inverted_clahe.png
      tatr/
        structure.json          -- TATR row/col/cell bounding boxes
        structure_overlay.png   -- visualization
```

Storage policies:
- `scans` bucket: authenticated upload, signed URL read
- Retain originals indefinitely
- Preprocessed variants can be regenerated — keep 90 days then archive

---

## Client-Facing Views

```sql
-- Generic approved records view
create view approved_records as
select
    r.id as record_id,
    r.client_id,
    r.record_type,
    r.schema_name,
    r.schema_version,
    r.created_at,
    a.approved_fields,
    a.approved_extra_fields,
    a.approved_by,
    a.approved_at
from records r
join record_approved a on a.record_id = r.id
where r.status = 'approved';

-- Nameplate-oriented view
create view approved_nameplates as
select
    r.id as record_id,
    r.client_id,
    r.created_at,
    a.approved_fields->>'manufacturer' as manufacturer,
    a.approved_fields->>'model_no' as model_no,
    a.approved_fields->>'serial_no' as serial_no,
    a.approved_fields->>'volts' as volts,
    a.approved_fields->>'hp' as hp,
    a.approved_fields->>'rpm' as rpm,
    a.approved_fields->>'hz' as hz,
    a.approved_fields->>'amps' as amps,
    a.approved_fields->>'equipment_type_guess' as equipment_type,
    a.approved_fields,
    a.approved_extra_fields,
    a.approved_by,
    a.approved_at
from records r
join record_approved a on a.record_id = r.id
where r.status = 'approved'
  and r.record_type in ('nameplate', 'equipment_label', 'hvac_chiller');

-- Product-label view
create view approved_product_labels as
select
    r.id as record_id,
    r.client_id,
    r.created_at,
    a.approved_fields->>'product_name' as product_name,
    a.approved_fields->>'product_code' as product_code,
    a.approved_fields->>'product_type' as product_type,
    a.approved_fields->>'manufacturer' as manufacturer,
    a.approved_fields->>'brand' as brand,
    a.approved_fields->>'size' as size,
    a.approved_fields->>'batch_number' as batch_number,
    a.approved_fields->>'manufacturing_date' as manufacturing_date,
    a.approved_fields->>'expiry_date' as expiry_date,
    a.approved_fields->>'specification' as specification,
    a.approved_fields,
    a.approved_extra_fields,
    a.approved_by,
    a.approved_at
from records r
join record_approved a on a.record_id = r.id
where r.status = 'approved'
  and r.record_type = 'product_label';

-- Review queue — records needing human attention
create view review_queue as
select
    r.id as record_id,
    r.record_type,
    r.source_ref,
    rc.fields,
    rc.extra_fields,
    rc.filled_field_count,
    rc.confidence_score,
    rc.review_notes,
    ri.public_url as primary_image_url,
    r.created_at
from records r
join record_current rc on rc.record_id = r.id
left join record_images ri on ri.record_id = r.id and ri.image_order = 1
where r.status = 'review_required'
order by rc.confidence_score asc;  -- lowest confidence first
```

---

## Row Level Security (RLS)

```sql
-- Enable RLS on all tables
alter table records enable row level security;
alter table record_images enable row level security;
alter table extraction_runs enable row level security;
alter table record_current enable row level security;
alter table record_approved enable row level security;

-- Client can read only their own approved records.
-- Assumes your JWT includes a custom claim: client_id
create policy "Client reads own approved records"
    on record_approved for select
    using (
        exists (
            select 1
            from records r
            where r.id = record_approved.record_id
              and r.client_id::text = auth.jwt() ->> 'client_id'
        )
    );

-- Server-side ingestion / extraction / review should use the service role key.
-- Service role bypasses RLS and should not be used in client apps.
```

---

## Extraction Pipeline Flow

```
1. UPLOAD
   ├── 1..3 images → Supabase Storage: scans/{record_id}/
   ├── INSERT records (status = 'uploaded')
   └── INSERT record_images (storage_path, sha256, quality_metrics)

2. EXTRACT
   ├── Load grouped images for the record
   ├── Run single GPT call using the schema-specific prompt
   ├── INSERT extraction_runs (raw_output, parsed_output, normalized_output)
   └── UPDATE records (status = 'extracted' or 'review_required')

3. STAGE
   ├── Use the latest extraction run as default, or pick best if multiple runs exist
   ├── UPSERT record_current (fields, extra_fields, confidence_score)
   ├── Compute review_required:
   │     true if confidence < threshold
   │     true if critical fields are uncertain
   │     true if schema routing is uncertain
   └── UPDATE records (status = 'extracted' or 'review_required')

4. REVIEW (human)
   ├── Load review_queue view
   ├── Show image + extracted fields side-by-side
   ├── Human corrects fields
   ├── INSERT field_reviews (per corrected field)
   ├── UPSERT record_approved (approved_fields)
   └── UPDATE records (status = 'approved')

5. CLIENT ACCESS
   ├── Query approved_nameplates / approved_product_labels / approved_records
   ├── Or call API endpoint backed by approved tables
   └── RLS ensures client sees only their records
```

---

## Confidence Score Design

The proposal doc (Section 2.5) says: _"Do not rely on LLM self-reported confidence. Use a composite score."_

GPT does **not** provide confidence scores. Everything below is computed by us from signals we can measure after GPT returns its JSON.

### PoC Confidence (single GPT call, no OCR)

Available now — uses only the GPT response + image quality metrics.

```python
# PoC confidence — computed from one GPT extraction run
def poc_confidence(fields: dict, quality_metrics: dict, record_type: str) -> float:
    """Score 0.0–1.0 from signals available in a single-GPT-call PoC."""

    # 1. Field validation: do extracted values match expected patterns?
    #    e.g. volts looks like "230/460", rpm is 3-4 digits, hz is 50 or 60
    validated = sum(field_passes_regex(f, v) for f, v in fields.items() if v)
    attempted = sum(1 for v in fields.values() if v)
    validation_ratio = validated / max(attempted, 1)

    # 2. Filled field ratio: how many of expected fields are populated?
    expected = EXPECTED_FIELD_COUNT.get(record_type, 20)
    filled_ratio = min(attempted / expected, 1.0)

    # 3. Image quality: blur, glare, exposure from preprocessing
    quality = 1.0
    if quality_metrics.get("laplacian_variance", 999) < 80:
        quality -= 0.3  # blurry
    if quality_metrics.get("glare_ratio", 0) > 0.04:
        quality -= 0.2  # heavy glare
    if quality_metrics.get("dynamic_range", 999) < 70:
        quality -= 0.2  # low contrast
    quality = max(quality, 0.0)

    # 4. Hallucination penalty: known risky fields present but unverifiable
    HALLUCINATION_FIELDS = {"rpm", "nom_fl_eff", "model_no", "efficiency"}
    risky_present = sum(1 for f in HALLUCINATION_FIELDS if fields.get(f))
    hallucination_penalty = risky_present * 0.03  # small per-field penalty

    score = (
        0.40 * validation_ratio       # do values look right?
      + 0.30 * filled_ratio           # are enough fields populated?
      + 0.20 * quality                # is the source image good?
      - hallucination_penalty         # discount for known-risky fields
    )
    return round(max(0.0, min(1.0, score)), 3)
```

**What this catches in the PoC:**
- A clean label image with 11/11 valid fields → score ~0.90 → auto-approve
- A motor nameplate with 25/39 fields, good image → score ~0.72 → review_required
- A blurry image with 5/39 fields, half failing regex → score ~0.30 → review_required + recapture flag

**What this cannot catch (single-call limitation):**
- GPT reads `rpm: 1765` — passes regex, looks plausible, but ground truth is `1755`. No way to know without a second extraction method.
- GPT reads `model_no: B0254X1T15A2M` — passes regex, structurally valid, but wrong. The hallucination penalty flags it for review but can't confirm the value.

### Production Confidence (future — multi-method)

When OCR cross-checks or multiple extraction runs are available, add the cross-method agreement signal:

```python
# Production confidence — adds cross-method agreement
def production_confidence(fields: dict, quality_metrics: dict, record_type: str,
                          extraction_runs: list[dict]) -> float:
    """Enhanced score using multiple extraction runs for cross-validation."""

    base = poc_confidence(fields, quality_metrics, record_type)

    if len(extraction_runs) < 2:
        return base  # fall back to PoC score

    # Cross-method agreement: for each field, do multiple methods agree?
    agreement_scores = []
    for field_name in fields:
        if not fields[field_name]:
            continue
        values_from_runs = [
            normalize(run["fields"].get(field_name))
            for run in extraction_runs
            if run["fields"].get(field_name)
        ]
        if len(values_from_runs) >= 2:
            # What fraction of runs agree with the primary value?
            primary = normalize(fields[field_name])
            agree = sum(1 for v in values_from_runs if v == primary)
            agreement_scores.append(agree / len(values_from_runs))

    agreement_ratio = sum(agreement_scores) / max(len(agreement_scores), 1)

    score = (
        0.30 * base                   # PoC signals still matter
      + 0.40 * agreement_ratio        # cross-method agreement is the strongest signal
      + 0.15 * (base * 0.4 / 0.4)    # re-weight validation component
      + 0.15 * (base * 0.3 / 0.3)    # re-weight filled ratio component
    )
    return round(max(0.0, min(1.0, score)), 3)
```

**What this adds:**
- GPT says `rpm: 1765`, PaddleOCR says `rpm: 1755` → disagreement → confidence drops → flagged for review
- GPT says `volts: 230/460`, RapidOCR says `volts: 230/460` → agreement → confidence boost
- Three methods agree on `manufacturer: Toshiba` → high confidence, skip review for that field

### Review Thresholds

| Confidence | Action | Rationale |
|:---:|--------|-----------|
| **>= 0.85** | Auto-approve | High validation + high fill + good image (+ agreement in production) |
| **0.60 – 0.84** | Review required | Some fields uncertain or image quality borderline |
| **< 0.60** | Review + recapture flag | Too many fields missing/failing or poor image quality |

### The `extraction_runs` table enables the transition

The PoC stores one row per record in `extraction_runs`. When you later add OCR or TATR:
- Insert additional rows in `extraction_runs` (same `record_id`, different `method`)
- The confidence function reads all runs for that record
- Cross-method agreement signal becomes available **without changing the schema**

```
PoC:        1 extraction_run  per record  →  poc_confidence()
Future:     3 extraction_runs per record  →  production_confidence()
```

No migration needed. The table is already designed for it.

---

## What Fields Go in JSONB vs SQL Columns

**Rule:** Start with JSONB for all extracted fields. Promote hot fields to real or generated columns only when you need to filter/search on them frequently.

```sql
-- Example: promote manufacturer and serial_no for fast lookups
alter table record_current add column
    manufacturer text generated always as (fields->>'manufacturer') stored;
alter table record_current add column
    serial_no text generated always as (fields->>'serial_no') stored;

create index idx_rc_manufacturer on record_current(manufacturer);
create index idx_rc_serial on record_current(serial_no);
```

This gives you the flexibility of JSONB (39 fields + extras without schema migrations) with the query speed of regular columns where it matters.

---

## Migration Path from Sheets

| Phase | What | How |
|-------|------|-----|
| 1 | Keep Sheets as-is, add Supabase in parallel | Extraction writes to both Sheets AND Supabase |
| 2 | Build review UI against Supabase | Review queue view + simple approval form |
| 3 | Client accesses approved data from Supabase | approved_nameplates view or REST API |
| 4 | Deprecate Sheets | Stop dual-write, archive Sheet data |

---

## PoC Scope (Minimum Viable)

For the immediate PoC, you need only:

```
Storage bucket: scans
Tables: records, record_images, extraction_runs, record_current, record_approved
Views: approved_records, approved_nameplates, approved_product_labels, review_queue
```

You can skip `field_reviews` in the first PoC if approvals are record-level only. Keep the schema simple, keep the JSONB flexible, and only add more tables when you have workflow pressure to justify them.

Do **not** skip `client_id` segregation. If external client access is part of the PoC, enable RLS before exposing the repository.

---

## Alignment with Proposal Doc

The proposal recommended "OCR-first, LLM fallback." Our experiment results showed the opposite — GPT-5.4 vision at 82.9% accuracy is the primary extractor, OCR at 27-33% is the cross-check. The table below maps the proposal's **goals** (not its assumed architecture) to what we actually validated and how Supabase supports it.

| Proposal Goal | What We Validated | Supabase Implementation |
|--------------|-------------------|------------------------|
| Quality gate before extraction | Image quality metrics (blur, glare, exposure) reliably predict extraction difficulty | `record_images.quality_metrics` — stored per image, used in confidence score |
| ROI detection + rectification | ROI crop helps OCR; GPT works fine on original image | Preprocessed variants in `scans/{id}/preprocessed/` — available but not required for GPT |
| Primary extraction | **GPT-5.4 vision is primary** (82.9%), not OCR (27-33%). One call, original image, 39 fields | `extraction_runs` with `method = 'vision_direct'` — the PoC hot path |
| Deterministic validation | Regex field validation + filled ratio + hallucination flagging — all computed post-GPT | `record_current.confidence_score` computed from GPT output, not GPT self-reported |
| Explicit abstain/review | Confidence thresholds route uncertain records to human review | `records.status = 'review_required'` + `review_queue` view |
| OCR cross-validation (future) | PaddleOCR uniquely correct on rpm, RapidOCR on serial_no — complementary to GPT | `extraction_runs` stores OCR runs alongside GPT — enables cross-method agreement when added |
| Don't trust LLM confidence | Composite score from regex + fill ratio + image quality + hallucination penalty | `poc_confidence()` — zero reliance on GPT self-assessment |
| Evaluation harness | Every extraction run preserved with raw output, model, prompt hash | `extraction_runs` is the audit trail — ground truth comparison is a query |

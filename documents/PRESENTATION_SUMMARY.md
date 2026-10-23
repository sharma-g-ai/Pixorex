# PoC Presentation Summary

## PPG Sea Stock receiving refinement — 5 October 2026

The receiving flow is **Capture DN → Review and finalise DN → Scan physical
can article → Exact match to current-DN article → Accept one can → Verify
counts → Save receiving summary locally**.

DN capture establishes expected articles and quantities. Physical can acceptance
records observed quantities. The current DN remains visible on the count and
summary pages; a master match alone cannot make an article eligible for that DN.
Unreadable/conflicting scans add nothing, unexpected articles remain separate,
and repeated receiving rows require a page/row choice. Leading zeros are preserved.

The updated screen specification, validation rules, and review checks are in
[PPG Sea Stock receiving workflow](PPG_SEASTOCK_RECEIVING_WORKFLOW.md).
The [clickable wireframes](../output/seastock-receiving-wireframes.html) simulate
camera observations and cover landing, document summary, scanner, physical
counts, and final receiving summary. They do not demonstrate live-cylinder OCR
or inventory posting.

The remaining sections below describe the earlier industrial nameplate
extraction PoC and its measured results.

## Goal

Evaluate whether industrial nameplates / labels can be extracted into structured fields accurately enough for a proof of concept, and determine the right extraction architecture.

## Evidence Base

- **39 report sections** covering OCR, GPT vision, hybrid, preprocessing, table detection, schema discovery
- **162 final validation runs** (6 images × 9 preprocessing × 3 approaches)
- **9 total images** tested — 3 original + 6 new wikimedia commons
- **9 manufacturers, 8 equipment types, 6 countries**
- **2 code reviews** (13 issues identified and fixed)
- **Ground truth validated** on motor nameplate (27 fields), equipment label (11 fields), HVAC chiller (52 fields)

---

## Final Recommendation

Use **GPT-5.4 vision** as the primary extraction path.

- **Known document types:** fixed schema in prompt + image-type-specific preprocessing
- **New unseen document types:** two-pass auto-discover → auto-map → re-extract, then lock schema
- **Do not use** OCR-only or hybrid OCR-text mapping as the primary PoC path

---

## Results at a Glance

### All 9 Images — GPT-5.4 Predefined Schema

| Image | Type | Manufacturer | Country | Fields | Accuracy | Latency |
|-------|------|-------------|---------|:------:|:--------:|:-------:|
| Motor (Malmbergs) | Induction motor | Malmbergs | Sweden | 13 | **100.0%** | 8.6s |
| Current transformer | Transformer | Zhejiang Sanai | China | 16 | **100.0%** | 6.8s |
| Equipment label | Pump label | Graco | USA | 11 | **90.9%** | 4.1s |
| Wheel loader | Data plate | Liebherr | Austria | 10 | **90.0%** | 4.8s |
| HVAC chiller | Chiller plate | Trane | USA | 52 | **88.5%** | 11.4s |
| AC generator | Generator | Can. Westinghouse | Canada | 16 | **87.5%** | 8.3s |
| Motor (Toshiba) | Motor nameplate | Toshiba | USA | 27 | **81.5%** | 5.9s |
| B-52 data plate | Aircraft | Boeing/USAF | USA | 5 | **80.0%** | 2.5s |
| Outboard motor | Serial plate | Tohatsu | Japan | 10 | **80.0%** | 6.0s |
| | | | | | | |
| **Average** | | **9 manufacturers** | **6 countries** | | **87.8%** | **6.5s** |

### Final Validation: 162 Runs (Section 39)

| Approach | Average Accuracy | Avg Latency | Cost/Image |
|----------|:----------------:|:-----------:|:----------:|
| **GPT Predefined Schema** | **84.0%** | **7.8s** | **$0.01** |
| GPT Two-Pass (auto-discover) | 84.4% | 20.3s | $0.023 |
| Hybrid v2 (OCR + GPT text) | 71.0% | 4.4s | $0.007 |

### Best Preprocessing (averaged across 6 new images)

| Rank | Preprocessing | GPT Predefined Avg | Notes |
|:---:|--------------|:-------------------:|-------|
| 1 | **ROI rectified (homography)** | **92.0%** | +4pp when perspective correction available |
| 2 | **Raw original** | **87.9%** | Safest universal default |
| 3 | CLAHE | 84.6% | Moderate help on some |
| 4 | Sharpened | 84.6% | Same as CLAHE |
| 5-9 | Gray, flattened, inverted, roi_crop | 81-85% | Diminishing returns |

---

## What We Proved

### 1. GPT vision is accurate and stable

- **87.8% average** across 9 diverse industrial images
- **100% on 2 images** (Malmbergs motor, Chinese transformer)
- **Consistent**: <4pp spread on repeated runs (Section 27)
- **Generalizes**: 9 manufacturers, 8 equipment types, 6 countries

### 2. Schema in the prompt is a major accuracy lever

- With predefined schema: **82-88%**
- Without schema (discovery): **65%**
- **Delta: +17-23pp** from including field names in prompt

### 3. Two-pass auto-discovery works for new schemas

- Fully automated: discover → GPT maps field names → re-extract
- **Matches predefined schema accuracy** (84.4% vs 84.0%)
- First image costs $0.023, subsequent images $0.01

### 4. Raw original is the safest preprocessing

- Only 2-4pp below best variant
- No risk of degradation on new image types
- ROI rectification adds +4pp when available

### 5. OCR reads text but can't map fields

- OCR recognition: **81%** of values found in raw text (Section 22)
- OCR mapping: **30-44%** accuracy (Section 22)
- **The bottleneck is mapping, not recognition** — OCR reads characters, GPT reads documents

### 6. Known error pattern

- **I/1 and O/0 confusion** on engraved/stamped text — persistent across all images and all methods
- **RPM hallucination**: GPT sometimes reads plausible-but-wrong RPM values
- These are character-level ambiguities at the physical capture limit

---

## Why Not the Other Paths

| Approach | Accuracy | Latency | Cost | Why Not Primary |
|----------|:--------:|:-------:|:----:|-----------------|
| **OCR-only** | 30-44% | 2.8s | $0 | Too low accuracy; reads text but can't assign to fields |
| **Hybrid v2** (OCR+GPT text) | 71% | 4.4s | $0.007 | 13pp below GPT vision; unstable field swaps on some images |
| **OCR-assisted vision** | +1.8pp motor, -3pp others | 8.6s | $0.01 | Marginal; GPT sometimes trusts wrong OCR readings |
| **BSRGAN + multi-image** | 83.3% motor | 50.6s | $0.02 | Too slow on CPU (31.8s BSRGAN alone); marginal gain |

---

## Cost & Latency

| Scenario | Motor/Label | Chiller | Cost | When |
|----------|:----------:|:-------:|:----:|------|
| **PoC default** (single image GPT) | **4-6s** | **11-16s** | **$0.01-0.02** | Known document type |
| **New schema onboarding** (two-pass first) | **~13s** | **~33s** | **$0.02-0.05** | First image of new type |
| **Subsequent same-type images** | **4-6s** | **11-16s** | **$0.01-0.02** | After schema locked |
| **Maximum accuracy motor** (BSRGAN+multi) | ~51s (CPU) | — | $0.02 | Only if GPU available |

Two-pass breakdown: Pass 1 (vision ~6-16s) + Pass 2 (text ~1.4s) + Pass 3 (vision ~6-16s).
Repeat images skip to Pass 3 only.

| Volume | Daily Cost (motor/label) | Daily Cost (chiller) |
|--------|:--:|:--:|
| 100/day | $1 | $2 |
| 1,000/day | $10 | $20 |
| 10,000/day | $100 | $200 |

---

## PoC Architecture

```
Image arrives
  │
  ├─ Known document type?
  │   ├─ YES → GPT-5.4 vision + locked schema + CoT prompt
  │   │        → Structured JSON output
  │   │        → $0.01, ~7s
  │   │
  │   └─ NO  → Two-pass auto-discover
  │            Pass 1: GPT discovers fields freely ($0.01)
  │            Pass 2: GPT maps discovered→canonical (text-only, $0.003)
  │            Pass 3: GPT re-extracts with locked schema ($0.01)
  │            → Lock schema for future similar images
  │            → $0.023, ~20s (one-time)
  │
  └─ Output: JSON with fields, values, source, review_required
```

---

## What This PoC Can Claim

- GPT-5.4 vision extracts industrial nameplate fields at **87.8% accuracy** across diverse equipment
- Works on **9 manufacturers, 8 equipment types, 6 countries** without per-manufacturer tuning
- **$0.01/image, ~7 seconds** — production-viable cost and latency
- New document types can be onboarded **automatically** without manual schema definition
- **Preprocessing is optional** — raw original achieves 85%+; ROI rectification adds +4pp when available

## What This PoC Cannot Claim

- That 87.8% will hold on all future images (tested on 9 — need 50+ for production baseline)
- That I/1 and O/0 errors are solvable without higher-resolution capture
- That one preprocessing works for all images (variant ranking is image-dependent)
- That the heuristic review signals are calibrated confidence scores

---

## Model Comparison (All Tested)

| Model | Type | Avg Accuracy (9 images) | Latency | Cost/Image |
|-------|------|:---:|:---:|:---:|
| **GPT-5.4** | Cloud API | **88.4%** | **6.5s** | **$0.01** |
| Qwen2.5-VL (7B) | Local (Ollama) | 82.7% | 190s (CPU) | $0 |
| Granite 4.0 (4.5B) | Local (HF) | 78.4% (6 images) | 233s (CPU) | $0 |
| Claude Opus 4.6 | Cloud API (OpenRouter) | 77.9% (7 images) | 13s | ~$0.05 |
| OCR 3-engine ensemble | Local | 44.4% | 3s | $0 |

**GPT-5.4 is the clear winner** — highest accuracy, fastest API latency, lowest cost among cloud models.

Local VLMs (Qwen, Granite) are viable at **$0 cost** but need GPU for practical latency. On CPU they're 30-40x slower than GPT API.

---

## Final PoC Recommendation

### Primary Extraction: GPT-5.4 Vision

GPT-5.4 is the production extraction engine because:
- **88.4% accuracy** across 9 diverse images (highest of all models tested)
- **6.5s latency** (fastest practical option)
- **$0.01/image** ($10/1000 images)
- **Consistent** (<4pp spread on repeated runs)
- **Generalizes** across 9 manufacturers, 8 equipment types, 6 countries
- **Schema-adaptive** via two-pass auto-discovery for new document types

### PoC System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MOBILE APP                            │
│  ┌──────────────────────────────────────────────┐       │
│  │  Camera Capture                               │       │
│  │  - Quality gate (blur, glare, exposure check) │       │
│  │  - Framing overlay for nameplate alignment    │       │
│  │  - Multi-shot option for hard plates          │       │
│  └──────────────────┬───────────────────────────┘       │
│                     │ Upload image                        │
└─────────────────────┼───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   BACKEND API                            │
│                                                          │
│  1. IMAGE INTAKE                                         │
│     └─ Receive image + metadata (equipment type if known)│
│                                                          │
│  2. PREPROCESSING                                        │
│     ├─ Resolution check: if <1000px → BSRGAN x2 (GPU)   │
│     ├─ ROI detection + perspective rectification         │
│     └─ Grayscale variant for OCR cross-check             │
│                                                          │
│  3. SCHEMA ROUTING                                       │
│     ├─ Known type? → Load locked schema                  │
│     └─ New type? → Two-pass auto-discovery               │
│        ├─ Pass 1: GPT-5.4 discovers fields ($0.01)       │
│        ├─ Pass 2: GPT maps to canonical names ($0.003)   │
│        └─ Lock schema for future images of this type     │
│                                                          │
│  4. EXTRACTION (GPT-5.4 Vision)                          │
│     ├─ Send image + predefined schema prompt + CoT       │
│     ├─ Receive structured JSON                           │
│     └─ ~6s latency, ~$0.01 cost                          │
│                                                          │
│  5. STORAGE                                              │
│     ├─ Store extracted fields + source image              │
│     └─ Store schema version per equipment type            │
│                                                          │
│  6. USER REVIEW (the PoC "validation")                   │
│     └─ User sees fields in app → eyeballs → corrects     │
│        → submits → corrections feed back to improve      │
│                                                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                   DATA LAYER                             │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ Extractions  │  │ Schemas      │  │ Images        │  │
│  │ (JSON/DB)   │  │ (per type)   │  │ (blob store)  │  │
│  │             │  │              │  │               │  │
│  │ field_name  │  │ type_id      │  │ image_id      │  │
│  │ value       │  │ field_list   │  │ original_url  │  │
│  │ source      │  │ version      │  │ preprocessed  │  │
│  │ review_req  │  │ locked_date  │  │ metadata      │  │
│  │ image_id    │  │ discovered_by│  │               │  │
│  └─────────────┘  └──────────────┘  └───────────────┘  │
│                                                          │
│  ┌─────────────────────────────────────────────┐        │
│  │ Review Queue                                 │        │
│  │ - Fields flagged review_required             │        │
│  │ - Human corrects → feeds back to schema      │        │
│  └─────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```

### API Endpoints

| Endpoint | Method | Purpose | Latency |
|----------|--------|---------|:-------:|
| `/extract` | POST | Image → extracted fields JSON | ~6-16s |
| `/extract/batch` | POST | Multiple images → batch results | ~6s × N |
| `/schema/list` | GET | List known equipment schemas | <100ms |
| `/schema/discover` | POST | First image of new type → auto-schema | ~13-33s |
| `/review/queue` | GET | Fields needing human review | <100ms |
| `/review/correct` | POST | Human correction → update extraction | <100ms |

### Mobile App Requirements

| Feature | Purpose | Priority |
|---------|---------|:--------:|
| **Camera capture** | Take nameplate photo | P0 |
| **Quality gate** | Check blur/glare/exposure before upload | P0 |
| **Framing overlay** | Guide user to frame the nameplate | P1 |
| **Equipment type selector** | User picks type (or "new") | P0 |
| **Results display** | Show extracted fields in table | P0 |
| **Review/edit** | User corrects wrong fields | P1 |
| **Offline queue** | Queue images when offline, sync later | P2 |
| **Multi-shot** | Take 2-3 photos of same plate for cross-ref | P2 |

### Backend Technology Stack

| Component | Recommendation | Why |
|-----------|---------------|-----|
| **API framework** | FastAPI (Python) | Async, fast, typed |
| **GPT client** | OpenAI SDK | Direct, well-documented |
| **Image storage** | S3/GCS blob store | Scalable, cheap |
| **Extraction DB** | PostgreSQL + JSON columns | Structured + flexible schema |
| **Schema store** | JSON files or DB table | Versioned per equipment type |
| **Queue** | Redis or SQS | For batch/async processing |
| **Preprocessing** | OpenCV (CPU) or BSRGAN (GPU) | Already validated |
| **Hosting** | Cloud Run (CPU) + GPU instance for SR | Per proposal |

### Cost Projection

| Volume | GPT Cost | Storage | Infra | Total |
|--------|:--------:|:-------:|:-----:|:-----:|
| 100/day | $1/day | ~$0 | ~$5/day | **~$6/day** |
| 1,000/day | $10/day | ~$1/day | ~$10/day | **~$21/day** |
| 10,000/day | $100/day | ~$5/day | ~$30/day | **~$135/day** |

### Validation

**Not required for PoC.** The PoC validation is the **human reviewing results in the app** — user sees extracted fields, eyeballs them, corrects if wrong, submits.

Automated validation is a Phase 2 addition. When added, it would be:

| Check | What | When to Add |
|-------|------|-------------|
| Format regex | Does `volts: 230/460` match expected pattern? | Phase 2 — GPT rarely returns invalid formats |
| Critical field flag | Always flag `model_no`, `serial_no`, `bearings` for human review | Phase 2 — just a 4-item hardcoded list |
| OCR cross-check | Does OCR agree with GPT on rpm/serial? | Phase 2 — only if hallucination rate >5% |

**Why not in PoC:** GPT-5.4 with predefined schema returns well-formatted JSON at 88.4% accuracy. The 12% errors are character-level misreads (O/0, I/1), not structural failures. A regex won't catch `95Z00718` vs `95ZOO718` — only a human or OCR cross-check can. For the PoC, let the human be the validator.

---

### Phase 2 Enhancements (After PoC)

| Enhancement | When | Impact |
|-------------|------|--------|
| BSRGAN on GPU server | If low-res images >20% of volume | +11pp on motor-type plates |
| Multi-image prompting | If single-image accuracy <80% on a class | +4pp accuracy |
| OCR cross-check (rpm, serial) | If hallucination rate >5% on critical fields | Catches plausible-but-wrong |
| Local VLM fallback (Qwen) | If offline capability needed | 82.7% at $0, needs GPU |
| Granite 4.0 with VAREX schema | If document KVP extraction needed | Purpose-built for docs |
| Evidence-based confidence | When 50+ images with review outcomes | Calibrated review scoring |

---

## Completed Milestones

1. ~~Expand evaluation to more images~~ **DONE (9 images, 162 runs)**
2. ~~Test across manufacturers~~ **DONE (9 manufacturers, 8 types, 6 countries)**
3. ~~Test preprocessing variants~~ **DONE (9 variants × 6 images)**
4. ~~Validate two-pass auto-discovery~~ **DONE (matches predefined accuracy)**
5. ~~Test local VLMs~~ **DONE (Qwen 82.7%, Granite 78.4%)**
6. ~~Test Claude Opus 4.6~~ **DONE (77.9% via OpenRouter)**
7. ~~CER analysis~~ **DONE (GPT 8.6% CER vs OCR 64.8%)**
8. ~~Latency/cost validation~~ **DONE ($0.01/img, 6.5s avg)**

## Next Steps for PoC Build

1. Build FastAPI backend with `/extract` endpoint
2. Implement schema routing (known type → locked schema, new type → two-pass)
3. Build mobile app with camera capture + quality gate
4. Connect to GPT-5.4 API with predefined schema prompts
5. Add PostgreSQL storage for extractions + images
6. Add review queue for flagged fields
7. Collect 50+ real-world images for production baseline

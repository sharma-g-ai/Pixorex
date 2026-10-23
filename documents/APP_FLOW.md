# LabelReader — End-to-End App Flow

```
USER (Mobile App)
  │
  ├─ 1. CAPTURE
  │    ├─ Open camera with framing overlay (guides nameplate alignment)
  │    ├─ On-device quality gate checks:
  │    │    ├─ Blur detection (Laplacian variance)
  │    │    ├─ Glare/overexposure check
  │    │    └─ Resolution check (reject < 640px)
  │    ├─ If FAIL → show "retake" with specific reason
  │    └─ If PASS → proceed
  │
  ├─ 2. SELECT EQUIPMENT TYPE
  │    ├─ User picks from known types (motor, label, chiller, generator, etc.)
  │    └─ Or selects "New / Unknown" → triggers two-pass discovery
  │
  ├─ 3. UPLOAD
  │    └─ POST image + equipment_type to /extract (or /schema/discover if new)
  │
  │
BACKEND API
  │
  ├─ 4. PREPROCESSING
  │    ├─ Resolution < 1000px? → BSRGAN x2 upscale (GPU)
  │    ├─ ROI detection → perspective rectification (if skewed)
  │    └─ Otherwise → pass raw original through
  │
  ├─ 5. SCHEMA ROUTING
  │    │
  │    ├─── KNOWN TYPE ─────────────────────────────────┐
  │    │    Load locked schema (e.g., 27 motor fields)  │
  │    │    Go to Step 6                                │
  │    │                                                │
  │    └─── NEW TYPE ───────────────────────────────────┤
  │         Pass 1: GPT-5.4 vision discovers fields     │
  │                 freely from image (~6s, $0.01)      │
  │         Pass 2: GPT text-only maps discovered       │
  │                 names → canonical names (~1.4s, $0.003)
  │         Lock new schema in DB                       │
  │         Go to Step 6                                │
  │                                                     │
  ├─ 6. EXTRACTION (GPT-5.4 Vision) ◄──────────────────┘
  │    ├─ Send: image + locked schema + CoT prompt
  │    ├─ Receive: structured JSON with all fields
  │    └─ ~6s motor/label, ~11-16s chiller | $0.01
  │
  ├─ 7. POST-PROCESSING
  │    ├─ Flag review_required = true for:
  │    │    ├─ model_no (always — O/0 ambiguity)
  │    │    ├─ serial_no (always — O/0, I/1 ambiguity)
  │    │    ├─ rpm (GPT hallucination risk)
  │    │    └─ bearings (O/0 ambiguity)
  │    └─ Regex sanity check on structured fields (volts, frame, etc.)
  │
  ├─ 8. STORE
  │    ├─ PostgreSQL: extracted fields + metadata + schema version
  │    ├─ S3/GCS: original image + preprocessed image
  │    └─ Review queue: flagged fields
  │
  │
USER (Mobile App)
  │
  ├─ 9. RESULTS DISPLAY
  │    ├─ Show extracted fields in a table
  │    ├─ Highlight fields marked review_required (yellow)
  │    └─ Show original image alongside for reference
  │
  ├─ 10. REVIEW / EDIT
  │    ├─ User taps any field to correct it
  │    ├─ Corrections POST to /review/correct
  │    └─ Corrected values overwrite extraction in DB
  │
  └─ 11. SUBMIT
       └─ Final confirmed extraction stored as validated record
```

---

## Timing (User Perspective)

| Step | User Sees | Duration |
|------|-----------|----------|
| Capture + quality check | Camera viewfinder | 2-3s |
| Select equipment type | Dropdown picker | 1s |
| Upload + extraction | Loading spinner | ~6-16s (known type) or ~13-33s (new type, one-time) |
| Review + submit | Results table | User-dependent |

For repeat images of the same type: **Capture → Upload → 6s wait → Review → Submit**.

---

## API Endpoints

| Endpoint | Method | Purpose | Latency |
|----------|--------|---------|:-------:|
| `/extract` | POST | Image → extracted fields JSON | ~6-16s |
| `/extract/batch` | POST | Multiple images → batch results | ~6s × N |
| `/schema/list` | GET | List known equipment schemas | <100ms |
| `/schema/discover` | POST | First image of new type → auto-discover schema | ~13-33s |
| `/review/queue` | GET | Fields needing human review | <100ms |
| `/review/correct` | POST | Human correction → update extraction | <100ms |

---

## Database Schema

```sql
CREATE TABLE extractions (
    id              UUID PRIMARY KEY,
    image_id        UUID REFERENCES images(id),
    equipment_type  VARCHAR(50),
    schema_version  INTEGER,
    fields          JSONB,
    review_flags    JSONB,
    created_at      TIMESTAMP,
    reviewed_at     TIMESTAMP,
    reviewed_by     VARCHAR(100)
);

CREATE TABLE schemas (
    id              SERIAL PRIMARY KEY,
    equipment_type  VARCHAR(50) UNIQUE,
    version         INTEGER,
    field_list      JSONB,
    locked_at       TIMESTAMP,
    discovered_by   UUID
);

CREATE TABLE images (
    id              UUID PRIMARY KEY,
    original_url    TEXT,
    preprocessed_url TEXT,
    equipment_type  VARCHAR(50),
    upload_time     TIMESTAMP,
    metadata        JSONB
);
```

---

## Technology Stack

### Backend

| Component | Choice | Why |
|-----------|--------|-----|
| **API framework** | FastAPI (Python 3.11+) | Async, typed, auto-generated OpenAPI docs |
| **ORM** | SQLAlchemy 2.0 + asyncpg | Async PostgreSQL access, native JSONB support |
| **Migrations** | Alembic | Schema versioning tied to SQLAlchemy models |
| **GPT client** | OpenAI Python SDK | Direct, well-documented, async support |
| **Image preprocessing** | OpenCV (CPU) | ROI detection, perspective rectification, quality checks |
| **Super-resolution** | BSRGAN x2 (GPU only) | Only when resolution < 1000px; skip on CPU-only infra |
| **Image handling** | Pillow | Resize, format conversion, metadata extraction |
| **Async processing (PoC)** | FastAPI BackgroundTasks | Zero extra infra; handles batch/async in-process |
| **Async processing (Prod)** | Redis + Celery | Dedicated workers, retries, monitoring at scale |
| **Validation** | Pydantic v2 | Request/response models, field validation |
| **Auth** | JWT (python-jose + passlib) | Stateless mobile API auth |
| **Testing** | pytest + httpx | Async test client for FastAPI |
| **Containerization** | Docker + docker-compose | Reproducible local dev (API + PostgreSQL + Redis) |

### Database & Storage

| Component | Choice | Why |
|-----------|--------|-----|
| **Extraction DB** | PostgreSQL 16 + JSONB | Structured metadata + flexible per-type fields |
| **Schema store** | `schemas` DB table | Already defined; versioned per equipment type |
| **Image storage (PoC)** | Local filesystem | Zero setup; images saved to `/data/images/` |
| **Image storage (Prod)** | Google Cloud Storage (GCS) | Same cloud as Cloud Run; signed URLs for mobile |
| **GCS client** | google-cloud-storage | Standard GCP SDK for Python |

### Mobile App

| Component | Choice | Why |
|-----------|--------|-----|
| **Framework** | React Native (Expo) | Cross-platform; JS/TS ecosystem; rapid PoC iteration |
| **Camera** | expo-camera | Framing overlay, quality gate integration |
| **Image quality** | On-device OpenCV (react-native-opencv) | Blur detection (Laplacian), glare check before upload |
| **HTTP client** | Axios | Request/response interceptors, upload progress |
| **State management** | Zustand | Lightweight, minimal boilerplate |
| **Navigation** | React Navigation | Standard for React Native |
| **UI components** | React Native Paper | Material Design, form inputs for review/edit |

### Infrastructure

| Component | Choice | Why |
|-----------|--------|-----|
| **API hosting** | Google Cloud Run | Auto-scaling, pay-per-request, container-native |
| **GPU preprocessing** | GCE GPU instance (on-demand) | BSRGAN only; spin up when needed, not always-on |
| **Database hosting** | Cloud SQL (PostgreSQL) | Managed backups, connection pooling |
| **Queue (Prod only)** | Cloud Memorystore (Redis) | Managed Redis for Celery; not needed in PoC |
| **Image storage** | GCS (production) / local (PoC) | Same cloud; signed URLs for mobile |
| **CI/CD** | GitHub Actions | Build → test → deploy to Cloud Run on push |
| **Monitoring** | Cloud Logging + Sentry | Error tracking, latency monitoring per endpoint |

---

## Cost Projection

| Volume | GPT API | Storage | Infra | Total/Day |
|--------|:-------:|:-------:|:-----:|:---------:|
| 100/day | $1 | ~$0 | ~$5 | ~$6 |
| 1,000/day | $10 | ~$1 | ~$10 | ~$21 |
| 10,000/day | $100 | ~$5 | ~$30 | ~$135 |

---

## Production Scale-Up (Post-PoC)

These components replace their PoC equivalents when moving to production scale.

### AWS S3 for Image Storage

Replaces: Local filesystem (PoC) / GCS (if cost optimization needed)

| Component | Choice | Why |
|-----------|--------|-----|
| **Image storage** | AWS S3 | Cheapest blob store at scale; mature lifecycle policies |
| **S3 client** | boto3 | Standard AWS SDK for Python |
| **Mobile access** | Pre-signed URLs | Temporary secure URLs generated server-side, no proxy needed |
| **Bucket structure** | `/{equipment_type}/{YYYY-MM}/{image_id}/original.jpg` + `preprocessed.jpg` | Organized by type and date for lifecycle management |
| **Lifecycle policy** | Move to S3 Glacier after 90 days | Reduces long-term storage cost by ~80% |

**When to switch:** When image volume exceeds ~1,000/day or cross-cloud storage cost matters.

### Redis + Celery for Async Processing

Replaces: FastAPI BackgroundTasks (PoC)

| Component | Choice | Why |
|-----------|--------|-----|
| **Message broker** | Redis (AWS ElastiCache or GCP Memorystore) | Fast, managed, sub-ms latency |
| **Task framework** | Celery | Retry logic, task routing, priority queues, monitoring |
| **Worker scaling** | Separate Celery worker containers | Scale workers independently from API |
| **Monitoring** | Flower (Celery dashboard) | Real-time task monitoring, failure alerts |
| **Task routing** | Dedicated queues per task type | `extract` queue, `batch` queue, `preprocess` queue |

**When to switch:** When batch processing (`/extract/batch`) needs >5 concurrent extractions, or you need retry/dead-letter handling for failed GPT calls.

### Migration Path

| PoC Component | Production Component | Trigger |
|---------------|---------------------|---------|
| Local filesystem | AWS S3 | >1,000 images/day or multi-server deployment |
| FastAPI BackgroundTasks | Redis + Celery | Batch processing, retry needs, worker scaling |
| SQLite (dev) | Cloud SQL (PostgreSQL) | Any deployment beyond local dev |
| Single container | Cloud Run + Celery workers | Concurrent extraction demand |

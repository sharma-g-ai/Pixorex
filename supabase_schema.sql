-- Supabase PoC schema for LabelReader
-- Run this in Supabase Dashboard > SQL Editor
-- Also create a Storage bucket named "scans" (private)

-- 1. records — one row per logical item
create table records (
    id              uuid primary key default gen_random_uuid(),
    record_type     text not null,
    schema_name     text not null,
    schema_version  text not null default '1.0',
    source          text default 'mobile_app',
    source_ref      text,
    user_email      text,
    status          text not null default 'uploaded'
                    check (status in ('uploaded', 'extracted', 'review_required', 'approved', 'rejected')),
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

create index idx_records_type_status on records(record_type, status);
create index idx_records_email on records(user_email);
create index idx_records_created on records(created_at desc);

-- 2. record_images — one row per image in the group
create table record_images (
    id              uuid primary key default gen_random_uuid(),
    record_id       uuid not null references records(id) on delete cascade,
    image_order     int not null default 1,
    panel_hint      text default 'unknown',
    storage_path    text not null,
    original_filename text,
    mime_type       text,
    created_at      timestamptz not null default now()
);

create index idx_record_images_record on record_images(record_id, image_order);

-- 3. extraction_runs — every model call preserved
create table extraction_runs (
    id                  uuid primary key default gen_random_uuid(),
    record_id           uuid not null references records(id) on delete cascade,
    provider            text not null default 'openai',
    model               text not null default 'gpt-5.4',
    method              text not null default 'vision_direct',
    schema_name         text,
    input_image_count   int not null default 1,
    raw_output_text     text,
    parsed_output       jsonb,
    image_match         boolean,
    detected_type       text,
    latency_ms          int,
    created_at          timestamptz not null default now()
);

create index idx_extraction_runs_record on extraction_runs(record_id, created_at desc);

-- 4. record_current — staging layer (Silver)
create table record_current (
    record_id           uuid primary key references records(id) on delete cascade,
    extraction_run_id   uuid references extraction_runs(id),
    fields              jsonb not null default '{}',
    extra_fields        jsonb not null default '{}',
    review_flags        jsonb not null default '{}',
    filled_field_count  int not null default 0,
    review_required     boolean not null default true,
    updated_at          timestamptz not null default now()
);

create index idx_record_current_gin on record_current using gin(fields);

-- 5. record_approved — client-facing layer (Gold)
create table record_approved (
    record_id               uuid primary key references records(id) on delete cascade,
    approved_fields         jsonb not null default '{}',
    approved_extra_fields   jsonb not null default '{}',
    approved_by             text,
    approved_at             timestamptz default now()
);

create index idx_record_approved_gin on record_approved using gin(approved_fields);

-- Views

create view approved_records_view as
select
    r.id as record_id,
    r.record_type,
    r.schema_name,
    r.user_email,
    r.created_at,
    a.approved_fields,
    a.approved_extra_fields,
    a.approved_by,
    a.approved_at
from records r
join record_approved a on a.record_id = r.id
where r.status = 'approved';

create view review_queue_view as
select
    r.id as record_id,
    r.record_type,
    r.user_email,
    rc.fields,
    rc.extra_fields,
    rc.review_flags,
    rc.filled_field_count,
    r.created_at
from records r
join record_current rc on rc.record_id = r.id
where r.status in ('extracted', 'review_required')
order by r.created_at desc;

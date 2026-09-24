-- ============================================================================
-- COMPLETE Supabase Setup for LabelReader PoC
-- ============================================================================
-- Run this ONE file in Supabase Dashboard > SQL Editor for a clean setup.
--
-- It creates:
-- - base tables
-- - schema and prompt template tables
-- - indexes
-- - review queue view
-- - approved client views
-- - flattened portal view
-- - storage bucket
-- - client RLS policies
-- - temporary operator anon policies for the current mobile PoC
-- ============================================================================

-- ── STEP 1: TABLES ───────────────────────────────────────────────────────────

create table if not exists public.records (
    id                uuid primary key default gen_random_uuid(),
    record_type       text not null,
    schema_name       text not null,
    schema_version    text not null default '1.0',
    source            text default 'mobile_app',
    source_ref        text,
    user_email        text,
    client_email      text,
    status            text not null default 'uploaded'
                      check (status in ('uploaded', 'extracted', 'review_required', 'approved', 'rejected')),
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

create index if not exists idx_records_type_status on public.records(record_type, status);
create index if not exists idx_records_email on public.records(user_email);
create index if not exists idx_records_client_email on public.records(lower(client_email));
create index if not exists idx_records_created on public.records(created_at desc);

create table if not exists public.record_images (
    id                uuid primary key default gen_random_uuid(),
    record_id         uuid not null references public.records(id) on delete cascade,
    image_order       int not null default 1,
    panel_hint        text default 'unknown',
    storage_path      text not null,
    original_filename text,
    mime_type         text,
    created_at        timestamptz not null default now()
);

create index if not exists idx_record_images_record on public.record_images(record_id, image_order);
create index if not exists idx_record_images_storage_path on public.record_images(storage_path);

create table if not exists public.extraction_runs (
    id                uuid primary key default gen_random_uuid(),
    record_id         uuid not null references public.records(id) on delete cascade,
    provider          text not null default 'openai',
    model             text not null default 'gpt-5.4',
    method            text not null default 'vision_direct',
    schema_name       text,
    prompt_key        text,
    prompt_version    text not null default '1.0',
    input_image_count int not null default 1,
    raw_output_text   text,
    parsed_output     jsonb,
    image_match       boolean,
    detected_type     text,
    suggested_schema  text,
    schema_confidence text,
    field_confidence  jsonb,
    field_review_notes jsonb,
    latency_ms        int,
    created_at        timestamptz not null default now()
);

alter table public.extraction_runs
  add column if not exists suggested_schema text,
  add column if not exists schema_confidence text;

create index if not exists idx_extraction_runs_record on public.extraction_runs(record_id, created_at desc);

create table if not exists public.record_current (
    record_id         uuid primary key references public.records(id) on delete cascade,
    extraction_run_id uuid references public.extraction_runs(id),
    fields            jsonb not null default '{}',
    extra_fields      jsonb not null default '{}',
    review_flags      jsonb not null default '{}',
    field_confidence  jsonb not null default '{}',
    field_review_notes jsonb not null default '{}',
    filled_field_count int not null default 0,
    review_required   boolean not null default true,
    updated_at        timestamptz not null default now()
);

create index if not exists idx_record_current_gin on public.record_current using gin(fields);

create table if not exists public.record_approved (
    record_id             uuid primary key references public.records(id) on delete cascade,
    approved_fields       jsonb not null default '{}',
    approved_extra_fields jsonb not null default '{}',
    field_confidence      jsonb not null default '{}',
    field_review_notes    jsonb not null default '{}',
    approved_by           text,
    approved_at           timestamptz default now()
);

create index if not exists idx_record_approved_gin on public.record_approved using gin(approved_fields);

-- Schema and prompt templates are database-owned so mobile/web clients do not
-- become the source of truth for extraction structure or instructions.
create table if not exists public.prompt_templates (
    prompt_key       text not null,
    version          text not null default '1.0',
    prompt_name      text not null,
    template_body    text not null,
    description      text,
    is_system        boolean not null default true,
    is_active        boolean not null default true,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    primary key (prompt_key, version)
);

create table if not exists public.schema_templates (
    schema_name        text primary key,
    display_name       text not null,
    description        text,
    fields             jsonb not null default '[]',
    field_descriptions jsonb not null default '{}',
    mandatory_fields   jsonb not null default '[]',
    prompt_key         text,
    prompt_version     text not null default '1.0',
    schema_version     text not null default '1.0',
    is_system          boolean not null default false,
    is_active          boolean not null default true,
    client_email       text,
    created_by         text,
    created_at         timestamptz not null default now(),
    updated_at         timestamptz not null default now(),
    constraint schema_templates_prompt_fkey
      foreign key (prompt_key, prompt_version)
      references public.prompt_templates(prompt_key, version)
);

create index if not exists idx_schema_templates_active
  on public.schema_templates(is_active, is_system, display_name);
create index if not exists idx_schema_templates_client
  on public.schema_templates(lower(client_email))
  where client_email is not null;

alter table public.extraction_runs
  add column if not exists prompt_key text,
  add column if not exists prompt_version text not null default '1.0',
  add column if not exists field_confidence jsonb,
  add column if not exists field_review_notes jsonb;

alter table public.prompt_templates
  add column if not exists version text not null default '1.0';

alter table public.schema_templates
  add column if not exists prompt_version text not null default '1.0';

-- Rename legacy always_review column to mandatory_fields on existing DBs.
-- Runs only when the old column exists and the new one does not — safe to
-- re-run on a clean install (the create table above already uses the new name).
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schema_templates'
      and column_name = 'always_review'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schema_templates'
      and column_name = 'mandatory_fields'
  ) then
    alter table public.schema_templates
      rename column always_review to mandatory_fields;
  end if;
end $$;

alter table public.schema_templates
  add column if not exists mandatory_fields jsonb not null default '[]';

alter table public.schema_templates
  drop constraint if exists schema_templates_prompt_key_fkey;

alter table public.schema_templates
  drop constraint if exists schema_templates_prompt_fkey;

alter table public.extraction_runs
  drop constraint if exists extraction_runs_prompt_fkey;

alter table public.prompt_templates
  drop constraint if exists prompt_templates_pkey;

alter table public.prompt_templates
  add constraint prompt_templates_pkey primary key (prompt_key, version);

alter table public.schema_templates
  add constraint schema_templates_prompt_fkey
  foreign key (prompt_key, prompt_version)
  references public.prompt_templates(prompt_key, version);

alter table public.extraction_runs
  add constraint extraction_runs_prompt_fkey
  foreign key (prompt_key, prompt_version)
  references public.prompt_templates(prompt_key, version);

alter table public.record_current
  add column if not exists field_confidence jsonb not null default '{}',
  add column if not exists field_review_notes jsonb not null default '{}';

alter table public.record_approved
  add column if not exists field_confidence jsonb not null default '{}',
  add column if not exists field_review_notes jsonb not null default '{}';

insert into public.prompt_templates
  (prompt_key, version, prompt_name, description, template_body, is_system, is_active)
values
  (
    'equipment_default',
    '1.0',
    'Equipment nameplate extraction',
    'Default prompt for industrial nameplates and equipment labels.',
    $prompt$
You are an expert at reading industrial nameplates, data plates, serial plates, rating plates, and equipment labels.

Read the full label systematically. For tables, read row by row including headers. For key-value plates, read each label-value pair in order.

Ambiguous character rules:
- 0 vs O: in numeric fields prefer 0; in model/serial fields preserve what is printed.
- 1 vs I vs l: in numeric fields prefer 1; in text fields use context.
- If a character is partially legible, use ? as a placeholder. This is better than guessing.
- Never invent plausible values. Return null when a field is not visible or not readable.

Use fixed schema fields first. Only use extra_fields for visible data that truly does not fit a fixed field.
Return values exactly as printed; do not add units or normalize dates unless the label prints them that way.
For manufacturer, return only the company name, not the address.

Equipment type: {{display_name}}

Fields to extract:
{{field_list}}

{{validation_contract}}

{{mismatch_handling_rules}}

{{field_confidence_rules}}

{{json_return_contract}}
$prompt$,
    true,
    true
  ),
  (
    'paint_label',
    '1.0',
    'Paint and chemical product label extraction',
    'Prompt for paint cans, sealants, coatings, adhesives, threadlockers, and related product labels.',
    $prompt$
You are an expert at reading product labels on industrial containers such as paint cans, sealant tubes, adhesive bottles, coatings, primers, hardeners, threadlockers, and similar products.

You may receive 1 to 10 images of the same product. Treat all images as one item and merge the clearest visible information into one JSON object. Do not return one object per image.

Panel priority:
- Front-facing priority: product_name, brand, color_name, color_code, finish, size
- Side/back priority: batch_number, manufacturing_date, expiry_date, specification, safety_warnings, voc_content, upc_barcode, po_number
- Any panel: product_code, manufacturer, description, made_in, dilution_ratio, coverage, dry_time, application_method, notes

Paint/product rules:
- product_name: use the primary commercial product name visible on the front label.
- product_code: extract the full part/catalog/product code exactly as printed.
- manufacturer: use the brand owner or prominent marketing company when visible, not a contract packer unless that is the only visible company.
- size, batch_number, manufacturing_date, expiry_date, and upc_barcode must be exactly as printed.
- For safety_warnings, use only readable warning text or hazard codes. Do not infer text from pictograms alone.
- Do not invent values that are not visible in at least one image.
- For extra_fields, capture only remaining visible labeled text not covered above as {"label": "value"} pairs.
  Do not duplicate a value already stored in a schema field, even if the label uses a synonym.
  Treat these labels as aliases of schema fields and do not repeat them in extra_fields:
    batch_number = LOT NO, LOT NUMBER, LOT #, BATCH, BATCH #
    manufacturing_date = DATE OF PACKAGING, PKG DATE, MFG DATE, PROD DATE
    expiry_date = EXPIRATION DATE, EXP DATE, USE BY, BEST BEFORE
    product_code = PART NO, PART #, CAT NO, CATALOG NUMBER
    upc_barcode = BARCODE, EAN, UPC, GTIN
    size = NET CONTENTS, NET WT, VOLUME, CONTENTS

Equipment type: {{display_name}}

Fields to extract:
{{field_list}}

{{validation_contract}}

{{mismatch_handling_rules}}

{{field_confidence_rules}}

{{json_return_contract}}
$prompt$,
    true,
    true
  ),
  (
    'other_default',
    '1.0',
    'Other label extraction',
    'Catch-all prompt for unknown labels, tags, stickers, packaging, and non-standard documents.',
    $prompt$
You are an expert at reading any kind of label, nameplate, tag, sticker, or printed information on products, equipment, or containers.

Identify the label type, then read all visible text systematically. For unknown labels, preserve as much visible information as possible without forcing it into an unrelated known schema.

Use:
- label_type for the user-facing category.
- primary_identifier for the most important visible code, serial, product code, UPC, or ID.
- secondary_identifier for a supporting code.
- barcode for any visible barcode/UPC/EAN text.
- visible_text for compact readable text that does not fit cleanly into fixed fields.
- extra_fields for remaining labeled text as {"label": "value"} pairs.

If multiple images are provided, merge information into one JSON object.
Never invent plausible values. Use null when not readable.

Equipment type: {{display_name}}

Fields to extract:
{{field_list}}

{{validation_contract}}

{{mismatch_handling_rules}}

{{field_confidence_rules}}

{{json_return_contract}}
$prompt$,
    true,
    true
  ),
  (
    'custom_default',
    '1.0',
    'Custom schema extraction',
    'Generic prompt for client-created custom schema templates.',
    $prompt$
You are extracting data for a client-defined schema.

Schema name: {{schema_name}}
Display name: {{display_name}}
Description: {{schema_description}}

Read all provided images of the same item and extract only the fields listed below. Use the optional field descriptions to understand what each field means.

Rules:
- Fill a field only when the value is directly visible or clearly represented on the label.
- Do not guess. Return null when not readable.
- Preserve values exactly as printed.
- Use extra_fields only when that field exists in the schema and the visible value does not fit another schema field.
- If multiple images are provided, merge information into one JSON object.

Fields to extract:
{{field_list}}

{{validation_contract}}

{{mismatch_handling_rules}}

{{field_confidence_rules}}

{{json_return_contract}}
$prompt$,
    true,
    true
  )
on conflict (prompt_key, version) do update set
  prompt_name   = excluded.prompt_name,
  description   = excluded.description,
  template_body = excluded.template_body,
  is_system     = excluded.is_system,
  is_active     = excluded.is_active,
  updated_at    = now();

-- Each predefined schema gets its own prompt row. Several rows intentionally
-- start with the same base template, but keeping separate prompt_key values
-- lets the team tune motor/generator/transformer/etc. independently later
-- without shipping app code.
insert into public.prompt_templates
  (prompt_key, version, prompt_name, description, template_body, is_system, is_active)
select
  v.prompt_key,
  '1.0',
  v.prompt_name,
  v.description,
  p.template_body,
  true,
  true
from (
  values
    ('motor',           'Motor prompt',               'Schema-specific prompt for motor nameplates.',                'equipment_default'),
    ('generator',       'Generator prompt',           'Schema-specific prompt for AC generator nameplates.',         'equipment_default'),
    ('transformer',     'Transformer prompt',         'Schema-specific prompt for current transformer nameplates.',  'equipment_default'),
    ('chiller',         'Chiller prompt',             'Schema-specific prompt for HVAC chiller nameplates.',         'equipment_default'),
    ('equipment_label', 'Equipment label prompt',     'Schema-specific prompt for general equipment labels.',        'equipment_default'),
    ('other',           'Other label prompt',         'Schema-specific prompt for unknown or miscellaneous labels.', 'other_default')
) as v(prompt_key, prompt_name, description, base_prompt_key)
join public.prompt_templates p
  on p.prompt_key = v.base_prompt_key
 and p.version = '1.0'
on conflict (prompt_key, version) do update set
  prompt_name   = excluded.prompt_name,
  description   = excluded.description,
  template_body = excluded.template_body,
  is_system     = excluded.is_system,
  is_active     = excluded.is_active,
  updated_at    = now();

insert into public.schema_templates
  (schema_name, display_name, description, fields, field_descriptions, mandatory_fields, prompt_key, prompt_version, is_system, is_active)
values
  (
    'motor',
    'Motor Nameplate',
    'Industrial motor nameplate schema.',
    '["manufacturer","location","country","model_no","type","form","frame_no","duty","hp","poles","ins_class","nema_des","nema_code","service_factor","volts","hz","rpm","amp","serial_no","max_amb_c","nom_fl_eff","bearing_ls","bearing_os","usable_208v_amp","temp_device_type","csa_temp_code","hazardous_locations","description","connection_info","made_in","notes","extra_fields"]'::jsonb,
    '{}'::jsonb,
    '["model_no","serial_no","rpm","bearing_ls","bearing_os"]'::jsonb,
    'motor',
    '1.0',
    true,
    true
  ),
  (
    'generator',
    'AC Generator Nameplate',
    'AC generator nameplate schema.',
    '["manufacturer","location","country","model_no","serial_no","type","frame","kva","kw","volts","amp","hz","rpm","phase","power_factor","ins_class","duty","excitation_volts","excitation_amps","bearing_type","weight_kg","made_in"]'::jsonb,
    '{}'::jsonb,
    '["model_no","serial_no","rpm"]'::jsonb,
    'generator',
    '1.0',
    true,
    true
  ),
  (
    'transformer',
    'Current Transformer Nameplate',
    'Current transformer nameplate schema.',
    '["manufacturer","location","country","model_no","serial_no","type","rated_voltage_kv","rated_current_primary","rated_current_secondary","ratio","burden_va","accuracy_class","frequency_hz","ins_class","weight_kg","made_in"]'::jsonb,
    '{}'::jsonb,
    '["model_no","serial_no","ratio"]'::jsonb,
    'transformer',
    '1.0',
    true,
    true
  ),
  (
    'chiller',
    'HVAC Chiller Nameplate',
    'HVAC chiller nameplate schema.',
    '["manufacturer","country","model_no","serial_no","type_of_use","series","crc","rated_voltage","rated_hz","rated_phase","volt_utilization_range","min_ckt_ampacity_ckt1","min_ckt_ampacity_ckt2","max_overcurrent_protection_ckt1","max_overcurrent_protection_ckt2","evap_heater_volt_ac","evap_heater_hz","evap_heater_phase","evap_heater_va","cprsr_mtr_1a_volts","cprsr_mtr_1a_hz","cprsr_mtr_1a_phase","cprsr_mtr_1a_rla","cprsr_mtr_1a_lra","cprsr_mtr_1a_hp","cprsr_mtr_1b_volts","cprsr_mtr_1b_hz","cprsr_mtr_1b_phase","cprsr_mtr_1b_rla","cprsr_mtr_1b_lra","cprsr_mtr_1b_hp","cprsr_mtr_2a_volts","cprsr_mtr_2a_hz","cprsr_mtr_2a_phase","cprsr_mtr_2a_rla","cprsr_mtr_2a_lra","cprsr_mtr_2a_hp","cprsr_mtr_2b_volts","cprsr_mtr_2b_hz","cprsr_mtr_2b_phase","cprsr_mtr_2b_rla","cprsr_mtr_2b_lra","cprsr_mtr_2b_hp","fan_mtrs_volts","fan_mtrs_hz","fan_mtrs_phase","fan_mtrs_qty","fan_mtrs_hp_ea","fan_mtrs_fla_ea","refrigerant_chg_ckt1_lbs","refrigerant_chg_ckt2_lbs","oil_chg_type","oil_chg_ckt1_gal","oil_chg_ckt2_gal","design_pressure_high_side","design_pressure_low_side","wiring_book","made_in"]'::jsonb,
    '{}'::jsonb,
    '["model_no","serial_no","crc"]'::jsonb,
    'chiller',
    '1.0',
    true,
    true
  ),
  (
    'equipment_label',
    'Equipment Label',
    'General equipment label schema.',
    '["manufacturer","location","country","serial_no","part_no","configuration_no","date_code","series","max_wpr_psi_bar","hazardous_locations","made_in"]'::jsonb,
    '{}'::jsonb,
    '["serial_no","part_no","configuration_no"]'::jsonb,
    'equipment_label',
    '1.0',
    true,
    true
  ),
  (
    'paint_label',
    'Paint / Chemical Label',
    'Paint, chemical, coating, sealant, adhesive, and threadlocker label schema.',
    '["product_name","product_code","product_type","manufacturer","brand","color_name","color_code","finish","size","batch_number","manufacturing_date","expiry_date","specification","description","safety_warnings","voc_content","upc_barcode","made_in","dilution_ratio","coverage","dry_time","application_method","po_number","notes","extra_fields"]'::jsonb,
    '{}'::jsonb,
    '["batch_number","product_code","upc_barcode","manufacturing_date","expiry_date","specification"]'::jsonb,
    'paint_label',
    '1.0',
    true,
    true
  ),
  (
    'other',
    'Other',
    'Catch-all schema for unknown labels and non-standard scans.',
    '["label_type","primary_identifier","secondary_identifier","barcode","product_name","manufacturer","brand","model_no","serial_no","description","specifications","size_or_quantity","date","made_in","country","visible_text","notes","extra_fields"]'::jsonb,
    '{}'::jsonb,
    '["primary_identifier","barcode","product_name"]'::jsonb,
    'other',
    '1.0',
    true,
    true
  )
on conflict (schema_name) do update set
  display_name       = excluded.display_name,
  description        = excluded.description,
  fields             = excluded.fields,
  field_descriptions = excluded.field_descriptions,
  mandatory_fields   = excluded.mandatory_fields,
  prompt_key         = excluded.prompt_key,
  prompt_version     = excluded.prompt_version,
  schema_version     = excluded.schema_version,
  is_system          = excluded.is_system,
  is_active          = excluded.is_active,
  updated_at         = now();

-- ── STEP 2: VIEWS ────────────────────────────────────────────────────────────

create or replace view public.review_queue_view as
select
    r.id as record_id,
    r.record_type,
    r.user_email,
    rc.fields,
    rc.extra_fields,
    rc.review_flags,
    rc.filled_field_count,
    r.created_at,
    rc.field_confidence,
    rc.field_review_notes
from public.records r
join public.record_current rc on rc.record_id = r.id
where r.status in ('extracted', 'review_required')
order by r.created_at desc;

-- Client-facing approved views intentionally exclude internal confidence and
-- review metadata. Keep those signals in record_current / record_approved and
-- review_queue_view only.
drop view if exists public.approved_records_view;
create or replace view public.approved_records_view
with (security_invoker = true) as
select
  r.id as record_id,
  r.record_type,
  r.schema_name,
  r.user_email,
  r.client_email,
  r.created_at,
  a.approved_fields,
  a.approved_extra_fields,
  a.approved_by,
  a.approved_at
from public.records r
join public.record_approved a on a.record_id = r.id
where r.status = 'approved';

drop view if exists public.approved_records_with_images_view;
create or replace view public.approved_records_with_images_view
with (security_invoker = true) as
select
  r.id as record_id,
  r.record_type,
  r.schema_name,
  r.user_email,
  r.client_email,
  r.created_at,
  a.approved_fields,
  a.approved_extra_fields,
  a.approved_by,
  a.approved_at,
  (
    select ri.storage_path
    from public.record_images ri
    where ri.record_id = r.id
    order by ri.image_order asc
    limit 1
  ) as preview_image_path
from public.records r
join public.record_approved a on a.record_id = r.id
where r.status = 'approved';

drop view if exists public.approved_records_flat;
create or replace view public.approved_records_flat
with (security_invoker = true) as
select
  r.id as record_id,
  r.record_type,
  r.schema_name,
  r.user_email,
  r.client_email,
  r.created_at,
  a.approved_by,
  a.approved_at,

  a.approved_fields->>'manufacturer'        as manufacturer,
  a.approved_fields->>'model_no'            as model_no,
  a.approved_fields->>'serial_no'           as serial_no,
  a.approved_fields->>'type'                as type,
  a.approved_fields->>'form'                as form,
  a.approved_fields->>'description'         as description,

  a.approved_fields->>'location'            as location,
  a.approved_fields->>'country'             as country,
  a.approved_fields->>'made_in'             as made_in,

  a.approved_fields->>'volts'               as volts,
  a.approved_fields->>'hz'                  as hz,
  a.approved_fields->>'amp'                 as amp,
  a.approved_fields->>'hp'                  as hp,
  a.approved_fields->>'rpm'                 as rpm,
  a.approved_fields->>'poles'               as poles,
  a.approved_fields->>'frame_no'            as frame_no,
  a.approved_fields->>'duty'                as duty,

  a.approved_fields->>'ins_class'           as ins_class,
  a.approved_fields->>'nema_des'            as nema_des,
  a.approved_fields->>'nema_code'           as nema_code,
  a.approved_fields->>'service_factor'      as service_factor,
  a.approved_fields->>'nom_fl_eff'          as nom_fl_eff,
  a.approved_fields->>'max_amb_c'           as max_amb_c,

  a.approved_fields->>'bearing_ls'          as bearing_ls,
  a.approved_fields->>'bearing_os'          as bearing_os,

  a.approved_fields->>'temp_device_type'    as temp_device_type,
  a.approved_fields->>'csa_temp_code'       as csa_temp_code,
  a.approved_fields->>'hazardous_locations' as hazardous_locations,
  a.approved_fields->>'usable_208v_amp'     as usable_208v_amp,

  a.approved_fields->>'part_no'             as part_no,
  a.approved_fields->>'configuration_no'    as configuration_no,
  a.approved_fields->>'date_code'           as date_code,
  a.approved_fields->>'series'              as series,
  a.approved_fields->>'max_wpr_psi_bar'     as max_wpr_psi_bar,

  a.approved_fields->>'connection_info'     as connection_info,
  a.approved_fields->>'notes'               as notes,

  -- Existing alias (kept so old clients that read extra_fields by this name still work)
  a.approved_extra_fields                   as extra_fields,

  (
    select ri.storage_path
    from public.record_images ri
    where ri.record_id = r.id
    order by ri.image_order asc
    limit 1
  ) as preview_image_path,

  -- Whole JSONB columns so the portal can render every schema dynamically
  -- (motor/generator/chiller/transformer/paint_label/equipment_label/other)
  -- instead of being locked to the flattened whitelist above.
  -- NOTE: these must stay AT THE END of the select list. CREATE OR REPLACE VIEW
  -- only allows appending new columns; reordering existing ones will error with
  -- "cannot change name of view column ... to ...". Add any future columns here.
  a.approved_fields                         as approved_fields,
  a.approved_extra_fields                   as approved_extra_fields
from public.records r
join public.record_approved a on a.record_id = r.id
where r.status = 'approved';

create or replace view public.approved_fields_long
with (security_invoker = true) as
select
  r.id as record_id,
  r.record_type,
  r.user_email,
  r.client_email,
  r.created_at,
  a.approved_by,
  a.approved_at,
  kv.key as field_name,
  kv.value as field_value
from public.records r
join public.record_approved a on a.record_id = r.id
cross join lateral jsonb_each_text(a.approved_fields) as kv(key, value)
where r.status = 'approved'
  and kv.value is not null
  and kv.value <> ''
  and kv.value <> 'null';

grant select on public.approved_records_view to authenticated;
grant select on public.approved_records_with_images_view to authenticated;
grant select on public.approved_records_flat to authenticated, anon;
grant select on public.approved_fields_long to authenticated, anon;
grant select, insert, update on public.prompt_templates to authenticated, anon;
grant select, insert, update on public.schema_templates to authenticated, anon;

-- ── STEP 3: REALTIME FOR DASHBOARD REFRESH ──────────────────────────────────
-- The client portal listens for changes on these base tables so Records and
-- Inventory Lookup update shortly after a mobile approval. Schema templates are
-- intentionally excluded so the Schemas tab stays stable while users edit/read.

do $$
begin
  begin
    alter publication supabase_realtime add table public.records;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.record_approved;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;

  begin
    alter publication supabase_realtime add table public.record_images;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- ── STEP 4: STORAGE BUCKET ──────────────────────────────────────────────────

insert into storage.buckets (id, name, public)
values ('scans', 'scans', false)
on conflict (id) do update
set public = excluded.public;

-- ── STEP 5: ENABLE RLS ──────────────────────────────────────────────────────

alter table public.records enable row level security;
alter table public.record_images enable row level security;
alter table public.extraction_runs enable row level security;
alter table public.record_current enable row level security;
alter table public.record_approved enable row level security;
alter table public.prompt_templates enable row level security;
alter table public.schema_templates enable row level security;

-- ── STEP 6: CLIENT PORTAL READ POLICIES ─────────────────────────────────────

drop policy if exists "schema_templates_readable_for_poc" on public.schema_templates;
create policy "schema_templates_readable_for_poc"
on public.schema_templates
for select
to authenticated, anon
using (is_active = true);

drop policy if exists "prompt_templates_readable_for_poc" on public.prompt_templates;
create policy "prompt_templates_readable_for_poc"
on public.prompt_templates
for select
to authenticated, anon
using (is_active = true);

drop policy if exists "clients_select_own_approved_records" on public.records;
create policy "clients_select_own_approved_records"
on public.records
for select
to authenticated
using (
  status = 'approved'
  and client_email is not null
  and lower(client_email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
);

drop policy if exists "clients_select_own_approved_payload" on public.record_approved;
create policy "clients_select_own_approved_payload"
on public.record_approved
for select
to authenticated
using (
  exists (
    select 1
    from public.records r
    where r.id = record_approved.record_id
      and r.status = 'approved'
      and r.client_email is not null
      and lower(r.client_email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  )
);

drop policy if exists "clients_select_own_record_images" on public.record_images;
create policy "clients_select_own_record_images"
on public.record_images
for select
to authenticated
using (
  exists (
    select 1
    from public.records r
    where r.id = record_images.record_id
      and r.status = 'approved'
      and r.client_email is not null
      and lower(r.client_email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  )
);

drop policy if exists "clients_select_own_scan_objects" on storage.objects;
create policy "clients_select_own_scan_objects"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'scans'
  and exists (
    select 1
    from public.record_images ri
    join public.records r on r.id = ri.record_id
    where ri.storage_path = name
      and r.status = 'approved'
      and r.client_email is not null
      and lower(r.client_email) = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  )
);

-- ── STEP 7: TEMPORARY OPERATOR POLICIES FOR THE CURRENT MOBILE POC ──────────
-- The Flutter app currently writes directly with the publishable/anon key.
-- These are intentionally broad and should be removed once writes move behind
-- backend-owned storage or operator Supabase Auth.

drop policy if exists "operator_insert_records_for_poc" on public.records;
create policy "operator_insert_records_for_poc"
on public.records
for insert
to anon
with check (true);

drop policy if exists "operator_select_records_for_poc" on public.records;
create policy "operator_select_records_for_poc"
on public.records
for select
to anon
using (true);

drop policy if exists "operator_update_records_for_poc" on public.records;
create policy "operator_update_records_for_poc"
on public.records
for update
to anon
using (true)
with check (true);

drop policy if exists "operator_delete_records_for_poc" on public.records;
create policy "operator_delete_records_for_poc"
on public.records
for delete
to anon
using (true);

drop policy if exists "operator_insert_record_images_for_poc" on public.record_images;
create policy "operator_insert_record_images_for_poc"
on public.record_images
for insert
to anon
with check (true);

drop policy if exists "operator_select_record_images_for_poc" on public.record_images;
create policy "operator_select_record_images_for_poc"
on public.record_images
for select
to anon
using (true);

drop policy if exists "operator_delete_record_images_for_poc" on public.record_images;
create policy "operator_delete_record_images_for_poc"
on public.record_images
for delete
to anon
using (true);

drop policy if exists "operator_insert_extraction_runs_for_poc" on public.extraction_runs;
create policy "operator_insert_extraction_runs_for_poc"
on public.extraction_runs
for insert
to anon
with check (true);

drop policy if exists "operator_select_extraction_runs_for_poc" on public.extraction_runs;
create policy "operator_select_extraction_runs_for_poc"
on public.extraction_runs
for select
to anon
using (true);

drop policy if exists "operator_delete_extraction_runs_for_poc" on public.extraction_runs;
create policy "operator_delete_extraction_runs_for_poc"
on public.extraction_runs
for delete
to anon
using (true);

drop policy if exists "operator_insert_record_current_for_poc" on public.record_current;
create policy "operator_insert_record_current_for_poc"
on public.record_current
for insert
to anon
with check (true);

drop policy if exists "operator_select_record_current_for_poc" on public.record_current;
create policy "operator_select_record_current_for_poc"
on public.record_current
for select
to anon
using (true);

drop policy if exists "operator_update_record_current_for_poc" on public.record_current;
create policy "operator_update_record_current_for_poc"
on public.record_current
for update
to anon
using (true)
with check (true);

drop policy if exists "operator_delete_record_current_for_poc" on public.record_current;
create policy "operator_delete_record_current_for_poc"
on public.record_current
for delete
to anon
using (true);

drop policy if exists "operator_insert_record_approved_for_poc" on public.record_approved;
create policy "operator_insert_record_approved_for_poc"
on public.record_approved
for insert
to anon
with check (true);

drop policy if exists "operator_select_record_approved_for_poc" on public.record_approved;
create policy "operator_select_record_approved_for_poc"
on public.record_approved
for select
to anon
using (true);

drop policy if exists "operator_update_record_approved_for_poc" on public.record_approved;
create policy "operator_update_record_approved_for_poc"
on public.record_approved
for update
to anon
using (true)
with check (true);

drop policy if exists "operator_delete_record_approved_for_poc" on public.record_approved;
create policy "operator_delete_record_approved_for_poc"
on public.record_approved
for delete
to anon
using (true);

drop policy if exists "operator_insert_schema_templates_for_poc" on public.schema_templates;
create policy "operator_insert_schema_templates_for_poc"
on public.schema_templates
for insert
to authenticated, anon
with check (is_system = false);

drop policy if exists "operator_update_schema_templates_for_poc" on public.schema_templates;
create policy "operator_update_schema_templates_for_poc"
on public.schema_templates
for update
to authenticated, anon
using (is_system = false)
with check (is_system = false);

drop policy if exists "operator_insert_prompt_templates_for_poc" on public.prompt_templates;
create policy "operator_insert_prompt_templates_for_poc"
on public.prompt_templates
for insert
to authenticated, anon
with check (is_system = false);

drop policy if exists "operator_update_prompt_templates_for_poc" on public.prompt_templates;
create policy "operator_update_prompt_templates_for_poc"
on public.prompt_templates
for update
to authenticated, anon
using (is_system = false)
with check (is_system = false);

drop policy if exists "operator_insert_scan_objects_for_poc" on storage.objects;
create policy "operator_insert_scan_objects_for_poc"
on storage.objects
for insert
to anon
with check (bucket_id = 'scans');

drop policy if exists "operator_select_scan_objects_for_poc" on storage.objects;
create policy "operator_select_scan_objects_for_poc"
on storage.objects
for select
to anon
using (bucket_id = 'scans');

drop policy if exists "operator_delete_scan_objects_for_poc" on storage.objects;
create policy "operator_delete_scan_objects_for_poc"
on storage.objects
for delete
to anon
using (bucket_id = 'scans');

-- ============================================================================
-- STEP 7: PAINT SCAN LOOKUP (Market Basket)
-- ============================================================================
-- Path A: no mobile changes. The Flutter app already creates one approved
-- record per paint can scan (schema_name = 'paint_label'). This section adds:
--
--   * paint_inventory            — dummy inventory table (UPC → availability)
--   * paint_upc_normalize(text)  — strips non-digits, accepts only 8/12/13
--                                  digit UPC/EAN values, and returns NULL for
--                                  partial or malformed codes
--   * paint_basket_view          — aggregates approved paint_label records by
--                                  UPC and joins against dummy inventory,
--                                  producing availability status
--
-- The portal reads paint_basket_view and highlights rows where status is
-- 'not_in_inventory', 'out_of_stock', or 'low_stock'.
--
-- Re-running this section is safe (uses create table if not exists + drop/create
-- view + on conflict update for seed data).
-- ============================================================================

-- 7.1 Dummy inventory table -------------------------------------------------

create table if not exists public.paint_inventory (
    upc              text primary key,
    product_code     text,
    product_name     text not null,
    brand            text,
    color_name       text,
    size             text,
    available_qty    integer not null default 0 check (available_qty >= 0),
    reorder_level    integer not null default 10 check (reorder_level >= 0),
    price_usd        numeric(10, 2),
    updated_at       timestamptz not null default now()
);

create index if not exists idx_paint_inventory_product_code
  on public.paint_inventory (lower(product_code))
  where product_code is not null;

-- 7.2 UPC normalization helper ---------------------------------------------
-- Returns digits for valid UPC/EAN lengths only (8, 12, or 13), otherwise NULL.
-- Example: ' 0 12345-67890 1 ' → '012345678901'
create or replace function public.paint_upc_normalize(raw text)
returns text
language sql
immutable
as $$
  select case
    when raw is null or btrim(raw) = '' then null
    else (
      with cleaned as (
        select regexp_replace(btrim(raw), '\D', '', 'g') as digits
      )
      select case
        when length(digits) in (8, 12, 13) then digits
        else null
      end
      from cleaned
    )
  end;
$$;

-- 7.3 Paint basket view ----------------------------------------------------
-- Aggregates approved paint_label records per client, strictly by normalized
-- UPC. No product_code fallback — the Flutter app / extraction layer is
-- responsible for populating upc_barcode on every paint_label scan, so any
-- record without a UPC is filtered out of the basket entirely.
--
-- Inventory lookup is intentionally separate from Records: scanned UPCs are
-- grouped here, then compared against paint_inventory to produce availability
-- quantity and status. This mimics an external catalog/ERP lookup for the demo.
--
-- Column list changed from the previous version, so this is DROP + CREATE
-- (CREATE OR REPLACE VIEW cannot remove or reorder columns).
drop view if exists public.paint_basket_view;

create view public.paint_basket_view
with (security_invoker = true) as
with scanned as (
  select
    r.id                                                    as record_id,
    r.client_email,
    r.created_at,
    public.paint_upc_normalize(ra.approved_fields->>'upc_barcode') as upc_digits,
    nullif(btrim(ra.approved_fields->>'product_code'), '')  as product_code,
    ra.approved_fields->>'product_name'                     as product_name,
    ra.approved_fields->>'brand'                            as brand,
    ra.approved_fields->>'color_name'                       as color_name,
    ra.approved_fields->>'size'                             as size,
    (
      select ri.storage_path
      from public.record_images ri
      where ri.record_id = r.id
      order by ri.image_order asc
      limit 1
    )                                                       as preview_image_path
  from public.records r
  join public.record_approved ra on ra.record_id = r.id
  where r.status = 'approved'
    and r.schema_name = 'paint_label'
    -- UPC is mandated at the extraction layer. Rows without a valid UPC are
    -- ignored so they don't pollute the basket.
    and public.paint_upc_normalize(ra.approved_fields->>'upc_barcode') is not null
),
grouped as (
  select
    client_email,
    upc_digits                                        as upc,
    max(product_code)                                 as scanned_product_code,
    max(product_name)                                 as scanned_product_name,
    max(brand)                                        as scanned_brand,
    max(color_name)                                   as scanned_color_name,
    max(size)                                         as scanned_size,
    (array_agg(preview_image_path order by created_at desc)
      filter (where preview_image_path is not null))[1] as preview_image_path,
    count(*)                                          as scanned_qty,
    min(created_at)                                   as first_scanned_at,
    max(created_at)                                   as last_scanned_at,
    array_agg(distinct record_id)                     as record_ids
  from scanned
  group by client_email, upc_digits
)
select
  g.client_email,
  g.upc,
  coalesce(i.product_code, g.scanned_product_code)   as product_code,
  coalesce(i.product_name, g.scanned_product_name)   as product_name,
  coalesce(i.brand, g.scanned_brand)                 as brand,
  coalesce(i.color_name, g.scanned_color_name)       as color_name,
  coalesce(i.size, g.scanned_size)                   as size,
  g.preview_image_path,
  g.scanned_qty,
  i.available_qty,
  i.reorder_level,
  case
    when i.upc is null then 'not_in_inventory'
    when i.available_qty = 0 then 'out_of_stock'
    when i.available_qty <= i.reorder_level then 'low_stock'
    else 'in_stock'
  end                                                as stock_status,
  (i.upc is not null)                                as matched_inventory,
  g.first_scanned_at,
  g.last_scanned_at,
  g.record_ids
from grouped g
left join public.paint_inventory i
  on public.paint_upc_normalize(i.upc) = g.upc
-- Order: most-scanned first (so the heaviest-demand SKUs float to the top),
-- then most recent as a tiebreaker, then UPC for stable ordering within ties.
order by g.scanned_qty desc, g.last_scanned_at desc, g.upc asc;

grant select on public.paint_basket_view to authenticated, anon;
grant select on public.paint_inventory   to authenticated, anon;

-- 7.4 Cleanup of stale inventory rows from earlier seed versions -----------
-- Earlier iterations of this seed used different primary keys for the same
-- logical products (fake 0123456xxxxx UPCs and gen_random_uuid() strings).
-- Those rows persisted after the tuning commit because ON CONFLICT DO UPDATE
-- only refreshes rows keyed by the current UPC. Leaving them around caused:
--
--   * duplicate basket rows (two inventory rows sharing the same product_code
--     made the old product_code fallback multiply results)
--   * confusing "48 vs 25 available" Loctite entries for the same SKU
--
-- This DELETE is idempotent — on a fresh database it removes nothing; on an
-- upgraded database it removes exactly the known stale rows I seeded earlier.
delete from public.paint_inventory
where upc in (
  -- First seed (commit 8ea56cf): fake 0123456xxxxx UPC-A stand-ins
  '012345601010', '012345602020', '012345603030', '012345604040',
  -- First seed: fake 0999999xxxxx Asian Paints stand-ins
  '099999999990', '099999999991'
);

-- Also drop any row whose product_code matches the two NOUPC rows but whose
-- PK is a random UUID string (from gen_random_uuid()::text in commit 8ea56cf).
-- The current seed uses 'NOUPC-*' prefixes as stable keys; anything else with
-- those product_codes is a leftover.
delete from public.paint_inventory
where product_code in ('PPG-SPG-101', 'SW-PROC-1GAL')
  and upc not like 'NOUPC-%';

-- 7.5 Seed dummy inventory -------------------------------------------------
-- Quantities and prices are tuned to look like a small paint-and-chemicals
-- retailer's stockroom. Breakdown:
--
--   * High-turn top sellers (Behr white semi-gloss, SW ProClassic, Asian
--     Paints bulk) — 50-160 units on hand
--   * Mid-turn specialty (BM Advance, PPG primer, niche colors) — 15-45
--   * Low-turn / high-cost (aerospace enamels, custom-mixed shades) — 4-10
--   * Two rows deliberately at zero to demo the 'out_of_stock' bucket:
--     - PPG Deltron Urethane Clear   (matches an existing DCX3030 scan)
--     - BM Regal Eggshell Hale Navy  (no existing scan but realistic)
--
-- Primary keys are stable UPC strings so re-running the seed doesn't duplicate
-- rows. The paint basket lookup intentionally matches on UPC only; rows without
-- a captured UPC stay out of the market basket until extraction is corrected.
--
-- The on-conflict clause refreshes quantities and prices on every re-run,
-- so tuning this block and replaying the SQL file is a valid workflow.
insert into public.paint_inventory
  (upc,              product_code,       product_name,                     brand,             color_name,        size,     available_qty, reorder_level, price_usd)
values
  -- ── Current PoC scan UPCs from the live demo data ─────────────────────
  -- These four rows are intentionally aligned with the scanned UPCs visible
  -- in the portal so the demo shows in-stock, low-stock, out-of-stock, and
  -- inventory-matched behavior instead of every row being "not in inventory".
  ('8904469112033', '4861',           'Shoe To Matching Nude',             null,              'Sun / 5-XL 24-42','1 UNIT', 12,            5,             19.99),
  ('12336789',      null,             'BEHR PREMIUM PLUS',                 'BEHR',            'ULTRA PURE WHITE','1 GAL',  25,            10,            39.98),
  ('34567890',      null,             'Matt/sheen Finish',                 'DecoMax',         null,              '20L',    0,             5,             59.99),
  ('705327734968',  '550-222-19',     'CRAZY GREEN',                       'Kelly-Moore Paints','CRAZY GREEN',    '1 QT',   3,             8,             26.99),

  -- ── Product-code matches for real records in your DB ──────────────────
  -- Kelly-Moore custom color — niche, low-turn, still in stock
  ('071474550222',    '550-222-19',       'Kel-Tone Acrylic Latex',         'Kelly-Moore',     'Crazy Green',     '1 QT',   6,             8,             26.99),
  -- PPG Aerospace F-package enamel — specialty product, expensive, low stock
  ('087080675355',    '870806F753550WFR', 'Aerospace Enamel F-Package',     'PPG Aerospace',   'Gloss White',     '1 GAL',  4,             3,             215.00),
  -- PPG Deltron DCX3030 — deliberately OUT OF STOCK to demo the basket
  ('087080303030',    'DCX3030',          'Deltron Universal Clear',        'PPG Aerospace',   'Clear',           '1 GAL',  0,             6,             168.00),
  -- Loctite 242 Blue threadlocker — fast-moving shop consumable
  ('079340884427',    'IDH 88442',        'Threadlocker 242 Blue',          'Loctite',         'Blue',            '50 ML',  48,            24,            14.99),

  -- ── UPC-first rows (real UPC-A codes for generic paint SKUs) ──────────
  -- Behr Premium Interior Semi-Gloss White — top-selling wall paint
  ('036000291452',    null,               'Premium Plus Interior Semi-Gloss','Behr',           'Ultra Pure White','1 GAL',  72,            40,            39.98),
  -- Behr Premium Exterior Flat — still moves but dark colors are slower
  ('036000291469',    null,               'Premium Plus Exterior Flat',     'Behr',            'Charcoal Smoke',  '1 GAL',  12,            15,            42.98),
  -- Benjamin Moore Advance — premium interior
  ('078477123456',    null,               'Advance Interior Satin',         'Benjamin Moore',  'Simply White',    '1 GAL',  36,            20,            72.99),
  -- Benjamin Moore Regal Hale Navy — deliberately OUT OF STOCK
  ('078477123463',    null,               'Regal Select Eggshell',          'Benjamin Moore',  'Hale Navy',       '1 GAL',  0,             16,            78.99),

  -- ── Extra catalog rows that should not match until UPC is captured ─────
  ('NOUPC-PPG-SPG-101',   'PPG-SPG-101',  'Shopline Speed Prime',           'PPG Industries',  'Gray Primer',     '1 GAL',  18,            10,            89.50),
  ('NOUPC-SW-PROC-1GAL',  'SW-PROC-1GAL', 'ProClassic Interior Acrylic',    'Sherwin Williams','Extra White',     '1 GAL',  54,            25,            68.99),

  -- ── Won't match any current scan — bulk Asian Paints for shelf depth ──
  ('840900000101',    'AP-APEX-1L',       'Apex Ultima Exterior',           'Asian Paints',    'Sunset Orange',   '1 L',    84,            30,            19.99),
  ('840900000102',    'AP-TRACTOR-4L',    'Tractor Emulsion Advanced',      'Asian Paints',    'Parchment',       '4 L',    156,           50,            32.99),

  -- ── Two more realistic retail fillers so the shelf looks stocked ──────
  ('021200411601',    'RU-STP-QT',        'Stops Rust Protective Enamel',   'Rust-Oleum',      'Hunter Green',    '1 QT',   22,            12,            16.49),
  ('042222000019',    'KILZ-PREMIUM',     'Premium Primer Sealer',          'Kilz',            'White',           '1 GAL',  41,            18,            33.98)
on conflict (upc) do update set
  product_code   = excluded.product_code,
  product_name   = excluded.product_name,
  brand          = excluded.brand,
  color_name     = excluded.color_name,
  size           = excluded.size,
  available_qty  = excluded.available_qty,
  reorder_level  = excluded.reorder_level,
  price_usd      = excluded.price_usd,
  updated_at     = now();

-- 7.6 RLS policies ---------------------------------------------------------
-- Inventory is read-only public for the PoC demo (no client filter).
-- paint_basket_view uses security_invoker so the existing client_email RLS
-- on the underlying records table applies transparently.
alter table public.paint_inventory enable row level security;

drop policy if exists "paint_inventory_readable" on public.paint_inventory;
create policy "paint_inventory_readable"
  on public.paint_inventory
  for select
  to authenticated, anon
  using (true);

-- ── DONE ────────────────────────────────────────────────────────────────────
-- After running this:
-- 1. Create or confirm a client user in Supabase Auth
-- 2. Set client_email on approved rows
-- 3. Deploy the portal to Netlify/Vercel
-- 4. Sign in through the portal with email + password

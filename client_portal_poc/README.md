# Client Portal

Static web portal for clients to view approved extraction records.

## What's in this folder

```
client_portal_poc/
├── index.html              ← Portal UI
├── app.js                  ← Logic (auth, data, rendering, export)
├── styles.css              ← Styling
├── config.js               ← Supabase credentials (edit for your project)
├── config.example.js       ← Template for config.js
├── README.md               ← This file
├── SETUP.md                ← Step-by-step clean install guide
└── sql/
    └── 01_complete_setup.sql   ← ONLY SQL file — run once in Supabase
```

## Quick start

1. Run `sql/01_complete_setup.sql` in Supabase SQL Editor
2. Deploy the schema-assist Edge Function if you want image-to-schema generation
3. Create a client user in Supabase Auth → Users → Add user (auto-confirm)
4. Copy `config.example.js` to `config.js`, fill your Supabase URL and anon key
5. Deploy this folder to Netlify (drag and drop)
6. Sign in on the portal with the client email and password

See [SETUP.md](SETUP.md) for the full guide with verification queries and troubleshooting.

## Schema Assist Edge Function

The Schemas page can generate a draft schema from an uploaded label image. The
browser does not call OpenAI directly. It invokes a Supabase Edge Function:

```text
Netlify portal → Supabase Edge Function schema-assist → OpenAI
```

Deploy once per Supabase project:

```bash
cd /home/msi/Downloads/ocr_poc
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set OPENAI_API_KEY='your-openai-key'
supabase functions deploy schema-assist
```

If the Supabase project is already linked locally, skip `supabase link`.

Then keep this in `config.js`:

```js
schemaAssistFunction: 'schema-assist',
aiAssistModel: 'gpt-4.1-mini',
```

Leave `schemaAssistFunction` blank only if you want to disable image-to-schema
generation and use manual schema creation only.

## Schema Policy

`Other` is a quarantine lane, not the target production schema.

Use it when the selected label type is unknown or the image does not fit the current schemas. Review `Other` records regularly by grouping on `approved_fields->>'label_type'`. If the same `label_type` appears repeatedly, for example 10 or more approved records, promote that pattern into a formal schema and prompt instead of letting it stay in `Other`.

Recommended review query:

```sql
select
  ra.approved_fields->>'label_type' as label_type,
  count(*) as record_count,
  array_agg(distinct ra.approved_fields->>'brand') as brands
from public.records r
join public.record_approved ra on ra.record_id = r.id
where r.schema_name = 'other'
group by ra.approved_fields->>'label_type'
having count(*) >= 10
order by record_count desc;
```

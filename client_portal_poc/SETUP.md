# Client Portal — Clean Install Guide

Complete setup from scratch. One SQL file, one deploy.

---

## Step 1: Supabase SQL Setup

1. Open Supabase Dashboard → **SQL Editor**
2. Paste the contents of `sql/01_complete_setup.sql`
3. Click **Run** (accept the "destructive operations" warning)

This creates everything:
- 5 tables (records, record_images, extraction_runs, record_current, record_approved)
- 5 views (review_queue, approved_records, approved_with_images, approved_flat, approved_fields_long)
- Private storage bucket `scans`
- RLS on all tables
- Client read policies (authenticated, scoped by client_email)
- Operator write policies (anon, for PoC mobile app)

## Step 2: Create Client User

1. Go to Supabase Dashboard → **Authentication** → **Users**
2. Click **Add user**
3. Enter client email and password
4. Check **Auto Confirm User**
5. Click Create

## Step 3: Deploy Schema Assist Function

This is required only for the dashboard **Schemas → From image** upload flow.
The browser must not call OpenAI directly; Netlify calls Supabase, and the Edge
Function calls OpenAI using a server-side secret.

From the repo root:

```bash
cd /home/msi/Downloads/ocr_poc
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set OPENAI_API_KEY='your-openai-key'
supabase functions deploy schema-assist
```

If the project is already linked, skip `supabase link`. If you do not deploy
this function, manual schema creation still works, but image-to-schema upload
will show a configuration/runtime error.

## Step 4: Configure the Portal

Copy `config.example.js` to `config.js`:

```js
window.CLIENT_PORTAL_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR_ANON_KEY',
  approvedView: 'approved_records_flat',
  imageBucket: 'scans',
  appTitle: 'Extraction Records',
  allowMagicLink: false,
  schemaAssistFunction: 'schema-assist',
  aiAssistModel: 'gpt-4.1-mini',
};
```

## Step 5: Deploy to Netlify

1. Go to https://app.netlify.com
2. **Add new site** → **Deploy manually**
3. Drag and drop the `client_portal_poc/` folder
4. Netlify gives you a public HTTPS URL

## Step 6: Add Redirect URL in Supabase

1. Go to Supabase Dashboard → **Authentication** → **URL Configuration**
2. Add your Netlify URL to **Redirect URLs**

## Step 7: Verify

### Check tables exist

```sql
select count(*) from public.records;
select * from storage.buckets where id = 'scans';
```

### Check approved records are visible to client

```sql
select record_id, manufacturer, model_no, client_email
from public.approved_records_flat
where lower(client_email) = lower('client@example.com')
limit 5;
```

### Check from the mobile app

1. Extract a record → should appear in `records` table
2. Approve it → should appear in `record_approved` with `client_email` set
3. Sign in on the portal → approved record should be visible

### Check schema image upload

1. Sign in on the portal
2. Open **Schemas**
3. Upload a label image
4. The image should preview first, then the form should auto-fill with suggested fields

In browser console, this should show the edge-function configuration:

```js
window.__schemaAssistDebug
```

Expected key values:

```js
{
  hasAiAssist: true,
  schemaAssistFunction: 'schema-assist'
}
```

---

## Troubleshooting

**Login works but no records appear:**
- Check `records.status = 'approved'` exists
- Check `records.client_email` matches the logged-in email
- Run: `select id, status, client_email from records where status = 'approved';`

**Portal shows blank after sign-in:**
- Hard refresh: Ctrl+Shift+R
- Check browser console (F12) for errors
- Verify `config.js` has correct Supabase URL and anon key

**Mobile app says "Supabase sync failed":**
- Check the SQL was run successfully (tables exist)
- Check `config.dart` has correct `supabaseUrl` and `supabaseAnonKey`

**Image preview doesn't load:**
- Check `scans` bucket exists in Supabase Storage
- Check `record_images` has rows with `storage_path`

**Schema upload says NetworkError / failed to fetch:**
- Confirm `supabase functions deploy schema-assist` completed successfully
- Confirm `OPENAI_API_KEY` is set as a Supabase secret, not in `config.js`
- Confirm `config.js` has `schemaAssistFunction: 'schema-assist'`
- Hard refresh the Netlify page after redeploying: Ctrl+Shift+R

**Testing schema upload on localhost:**
- `http://localhost:8080` serves only the static portal
- By default it still calls the deployed Supabase function
- To test a local function instead, serve the function locally and set:

```js
schemaAssistUrl: 'http://localhost:54321/functions/v1/schema-assist'
```

Keep `schemaAssistUrl` blank before deploying the portal to Netlify.

---

## Security Notes (PoC)

- The anon key is a publishable key — safe for frontend use
- Never put the service role key in client code
- Current anon write policies are PoC-only — remove when writes move to a backend
- Client access is scoped by `client_email` via RLS
- Images are private, served via signed URLs (1-hour expiry)

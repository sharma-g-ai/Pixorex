# LabelReader PoC — Complete Setup Guide

## Overview

LabelReader is a mobile app that captures industrial nameplate/label images, extracts field data using GPT vision, and stores results in Supabase. A client portal (static website) shows approved records.

### Architecture

```
Mobile App (Flutter)
  → captures image
  → sends to OpenAI GPT for field extraction
  → saves to: Local JSON (always) + Supabase (primary) + Google Sheets (parallel)
  → operator reviews and approves
  → approved records visible in Client Portal

Client Portal (Static HTML/JS)
  → hosted on Netlify
  → reads approved records from Supabase
  → client signs in with Supabase Auth (email/password)
  → sees only their own approved records (RLS enforced)
```

### Branch

Use branch: **`supabaseGsheets`**

```bash
git clone https://github.com/AmzurATG/LabelReader.git
cd LabelReader
git checkout supabaseGsheets
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Flutter SDK | 3.41+ | Build the mobile app |
| Android SDK | 34+ | Android APK build |
| Java JDK | 17+ | Android build toolchain |
| OpenAI API key | — | GPT vision extraction |
| Supabase project | Free tier | Database + Auth + Storage |
| Netlify account | Free tier | Host the client portal |
| Google Sheets API | Optional | Parallel sheet sync |

---

## Step 1: Supabase Project Setup

### 1.1 Create a Supabase project

1. Go to https://supabase.com → New Project
2. Note down:
   - **Project URL**: `https://YOUR_PROJECT.supabase.co`
   - **Anon/Public key**: from Settings → API → `anon` / `public` key

### 1.2 Run the SQL setup

1. Go to Supabase Dashboard → **SQL Editor**
2. Paste the contents of **`client_portal_poc/sql/01_complete_setup.sql`**
3. Click **Run** (accept the "destructive operations" warning — it's just `drop policy if exists`)

This creates:
- 5 tables: `records`, `record_images`, `extraction_runs`, `record_current`, `record_approved`
- Views: `approved_records_flat`, `approved_records_with_images_view`, `review_queue_view`
- Storage bucket: `scans` (private)
- RLS policies: client read access + operator anon write access (PoC-only)

### 1.3 Create client user for the portal

1. Go to Supabase Dashboard → **Authentication** → **Users**
2. Click **Add user** (top right)
3. Enter:
   - Email: the client's email (e.g., `client@company.com`)
   - Password: choose one
   - Check **"Auto Confirm User"**
4. Click Create

### 1.4 Verify

Run these in SQL Editor to confirm:

```sql
-- Tables exist
select count(*) from public.records;

-- Storage bucket exists
select * from storage.buckets where id = 'scans';

-- RLS is enabled
select tablename, rowsecurity from pg_tables where schemaname = 'public' and tablename in ('records', 'record_approved');
```

---

## Step 2: Configure the Flutter App

### 2.1 Update config.dart

Edit `frontend/lib/services/config.dart`:

```dart
// Your OpenAI API key
const String openAiApiKey = 'sk-proj-YOUR_KEY_HERE';

// Your Supabase credentials
const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
const String supabaseAnonKey = 'YOUR_ANON_KEY_HERE';

// Client email — all approved records are assigned to this client
const String defaultClientEmail = 'client@company.com';

// Google Sheets (optional — leave as-is to disable)
const String googleSheetId = 'YOUR_SHEET_ID';
```

### 2.2 Google Sheets setup (optional)

If you want parallel Sheets sync:
1. Create a Google Cloud project
2. Enable Sheets API
3. Create a service account
4. Download credentials JSON to `frontend/assets/credentials.json`
5. Share the spreadsheet with the service account email

If you don't need Sheets, the app still works — Sheets sync fails silently and Supabase is the primary store.

---

## Step 3: Build the APK

### 3.1 Install Flutter (if not installed)

```bash
# Download Flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$HOME/flutter/bin:$PATH"

# Install Android SDK command-line tools
mkdir -p ~/Android/Sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip
unzip /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-temp
mv /tmp/cmdline-tools-temp/cmdline-tools ~/Android/Sdk/cmdline-tools/latest

# Set environment
export ANDROID_HOME=~/Android/Sdk
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Accept licenses and install SDK components
yes | sdkmanager --licenses
sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34" "cmake;3.22.1"

# Configure Flutter
flutter config --android-sdk ~/Android/Sdk
flutter doctor
```

### 3.2 Build

```bash
cd LabelReader/frontend
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

### 3.3 Install on device

Transfer the APK to an Android phone and install:
- USB: `adb install build/app/outputs/flutter-apk/app-release.apk`
- Or copy to phone Downloads and tap to install

---

## Step 4: Deploy the Client Portal

### 4.1 Configure the portal

Copy and edit `client_portal_poc/config.js`:

```js
window.CLIENT_PORTAL_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR_ANON_KEY_HERE',
  approvedView: 'approved_records_flat',
  imageBucket: 'scans',
  appTitle: 'Client Records Portal',
  allowMagicLink: false,
};
```

### 4.2 Deploy to Netlify

1. Go to https://app.netlify.com
2. Click **Add new site** → **Deploy manually**
3. Drag and drop the `client_portal_poc/` folder
4. Netlify generates a public URL (e.g., `https://xyz.netlify.app`)

### 4.3 Add redirect URL in Supabase

1. Go to Supabase Dashboard → **Authentication** → **URL Configuration**
2. Add your Netlify URL to **Redirect URLs**

---

## Step 5: Test End-to-End

### Operator flow (mobile app)

1. Open the app on your Android phone
2. Enter your operator email when prompted
3. Select equipment type (e.g., "Motor Nameplate")
4. Capture or pick an image
5. Wait for GPT extraction
6. Review the extracted fields
7. Tap **"Submit as-is"** or edit fields first then submit

### Verify in Supabase

Check the dashboard (Table Editor):
- `records` — new row with `status = 'approved'`
- `record_images` — image uploaded to `scans` bucket
- `extraction_runs` — GPT model and method logged
- `record_current` — extracted fields
- `record_approved` — approved fields with `approved_by`

### Client flow (portal)

1. Open the Netlify URL in a browser
2. Sign in with the client email/password created in Step 1.3
3. Approved records should appear with:
   - Flat field columns (manufacturer, model_no, volts, etc.)
   - Image thumbnails
   - Detail panel on click
   - CSV export

---

## Troubleshooting

### App says "Supabase sync failed"

- Check `config.dart` has correct `supabaseUrl` and `supabaseAnonKey`
- Check the SQL setup ran successfully (tables exist)
- Check RLS policies exist: Supabase Dashboard → Authentication → Policies

### Portal shows "No approved records found"

- Check there are approved records: `select * from records where status = 'approved';`
- Check `client_email` is set: `select id, client_email from records where status = 'approved';`
- Check the client user is confirmed in Supabase Auth
- Check the `client_email` on records matches the logged-in portal email

### Portal login says "Invalid login credentials"

- User might not be confirmed — go to Auth → Users → confirm the user
- Password might be wrong — reset it in the dashboard

### Image preview doesn't load in portal

- Check `scans` bucket exists in Storage
- Check `record_images` has a `storage_path` for that record
- Check the anon SELECT policy on `storage.objects` exists

### Build fails with "Ninja not found"

```bash
sdkmanager "cmake;3.22.1"
```

### Build fails with "Java version too old"

Need JDK 17+. Download portable: https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz

---

## File Reference

| File | Purpose |
|------|---------|
| `frontend/lib/services/config.dart` | API keys, Supabase URL, client email |
| `frontend/lib/services/openai_service.dart` | GPT prompts (3 prompt types) |
| `frontend/lib/services/supabase_service.dart` | Supabase CRUD operations |
| `frontend/lib/services/app_state.dart` | App orchestration (extract → save → sync) |
| `frontend/lib/services/sheets_service.dart` | Google Sheets parallel sync |
| `frontend/lib/services/local_store.dart` | Local JSON persistence |
| `frontend/assets/schemas/*.json` | Field schemas per equipment type |
| `client_portal_poc/` | Static client portal (HTML/JS/CSS) |
| `client_portal_poc/sql/01_complete_setup.sql` | Complete Supabase SQL setup |
| `client_portal_poc/config.js` | Portal Supabase config |
| `supabase_implementation_plan.md` | Architecture design doc |

---

## Security Notes (PoC)

- The anon key is safe to embed in the APK and portal — it's a publishable key
- The **service role key** must NEVER be in frontend code
- Current anon write policies are **PoC-only** — remove them when writes move to a backend
- Client access is protected by Supabase Auth + RLS (scoped by `client_email`)
- Images are private in the `scans` bucket, served via signed URLs

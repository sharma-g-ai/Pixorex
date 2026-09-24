// Demo-only configuration — keys are embedded in APK.
// For production, use a backend proxy to hide these secrets.
//
// Copy this file to config.dart and fill in real values.
// config.dart is gitignored — never commit real secrets.

const String openAiApiKey = 'sk-...';

const String openAiModel = 'gpt-5.4';

const String googleSheetId = '';

const String sheetUrl =
    'https://docs.google.com/spreadsheets/d/$googleSheetId/edit';

// Supabase
const String supabaseUrl = '';
const String supabaseAnonKey = '';

bool get hasSupabaseConfig =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

// Client email for portal RLS — all approved records are assigned to this client.
const String defaultClientEmail = '';

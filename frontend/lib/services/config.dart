// Demo builds inject this key with --dart-define-from-file.
// It remains extractable from the APK; use an authenticated proxy for distribution.
const String openAiApiKey = String.fromEnvironment('OPENAI_API_KEY');

const String openAiModel = 'gpt-5.4';

// Supabase
const String supabaseUrl = 'https://pdxdwbfzujbqnwmgenas.supabase.co';
const String supabaseAnonKey = 'sb_publishable_3P-sFGTBSc1DuQGhJFrBJw_djPpUU3p';

bool get hasSupabaseConfig =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

// Client email for portal RLS — all approved records are assigned to this client.
const String defaultClientEmail = 'client.ppg.demo@amzur.com';

window.CLIENT_PORTAL_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  approvedView: 'approved_records_flat',
  imageBucket: 'scans',
  appTitle: 'EquipTrack Dashboard',
  allowMagicLink: false,
  // Supabase Edge Function used by the Schemas page image upload.
  // Deploy supabase/functions/schema-assist and keep provider credentials
  // server-side. Leave blank to disable image-to-schema assist.
  schemaAssistFunction: 'schema-assist',
  // Optional developer-only override. Example:
  // schemaAssistUrl: 'http://localhost:54321/functions/v1/schema-assist',
  schemaAssistUrl: '',
  aiAssistModel: 'gpt-4.1-mini',
};

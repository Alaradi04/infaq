/// Supabase project ID: `omdppfnhxtzayvpxdlbm` (fn**hxtzay**, not fn**hxztay**).
///
/// Use [kSupabaseUrl] for [Supabase.initialize] only — no `/auth/v1/callback` suffix.
/// For Google Cloud Console (Web OAuth client), use [kSupabaseGoogleOAuthWebRedirectUri].
/// For mobile OAuth return URL, use [kOAuthRedirectTo] in `oauth_redirect.dart`.
const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://omdppfnhxtzayvpxdlbm.supabase.co',
);

const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_XsViN4uolUNEJWenMUS3wQ_4b9wEjOb',
);

/// Google Cloud Console → OAuth 2.0 client (Web) → Authorized redirect URIs.
/// Supabase Dashboard → Authentication → URL Configuration → Redirect URLs (web flow).
const String kSupabaseGoogleOAuthWebRedirectUri =
    'https://omdppfnhxtzayvpxdlbm.supabase.co/auth/v1/callback';

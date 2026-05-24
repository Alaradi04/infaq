/// Return URL for mobile OAuth (Google, etc.). Must match:
/// - Android: `AndroidManifest` intent-filter (`com.infaq.app` / `login-callback`)
/// - iOS: `CFBundleURLSchemes` in `Info.plist`
/// - Supabase Dashboard → Authentication → URL Configuration → **Redirect URLs** (add this exact value)
///
/// Google Web OAuth (Cloud Console authorized redirect URI) is separate:
/// `https://omdppfnhxtzayvpxdlbm.supabase.co/auth/v1/callback` — do not use that value here or in [Supabase.initialize].
const String kOAuthRedirectTo = 'com.infaq.app://login-callback';

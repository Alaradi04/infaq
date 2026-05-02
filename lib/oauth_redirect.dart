/// Return URL for mobile OAuth (Google, etc.). Must match:
/// - Android: `AndroidManifest` intent-filter (`com.infaq.app` / `login-callback`)
/// - iOS: `CFBundleURLSchemes` in `Info.plist`
/// - Supabase Dashboard → Authentication → URL Configuration → **Redirect URLs** (add this exact value)
const String kOAuthRedirectTo = 'com.infaq.app://login-callback';

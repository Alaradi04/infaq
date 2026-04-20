import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Storage bucket for subscription row images.
/// Reuses `avatars` to avoid missing-bucket failures in environments
/// where a separate `subscription-icon` bucket was not created.
class InfaqSubscriptionIconStorage {
  static const String bucket = 'avatars';

  static String publicUrl(SupabaseClient client, String path) {
    return client.storage.from(bucket).getPublicUrl(path.trim());
  }

  /// [iconUrl] may be a storage path or an already-resolved https URL.
  static String? resolveDisplayUrl(SupabaseClient client, String? iconUrl) {
    if (iconUrl == null || iconUrl.trim().isEmpty) return null;
    final t = iconUrl.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return publicUrl(client, t);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Storage bucket for profile images. Create a **public** bucket named `avatars` in the dashboard.
class InfaqAvatarStorage {
  static const String bucket = 'avatars';

  /// Full public URL for a stored object path, or null if [path] is empty.
  static String? publicUrl(SupabaseClient client, String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return client.storage.from(bucket).getPublicUrl(path.trim());
  }
}

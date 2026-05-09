import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/subscription/subscription_preset_icons.dart';

/// Supabase Storage for subscription icons.
///
/// - Preset icons: public bucket `subscription-icons`, paths from [SubscriptionPresetIcon.storagePath].
/// - User uploads: same bucket, paths like `{userId}/sub_{timestamp}.ext` (see add/edit screens).
/// - Legacy uploads may still live under bucket `avatars` with the same path shape.
class InfaqSubscriptionIconStorage {
  static const String presetBucket = 'subscription-icons';

  /// Older builds stored subscription images here; paths contain `/sub_`.
  static const String legacyUserIconBucket = 'avatars';

  static String publicUrl(SupabaseClient client, String bucket, String path) {
    return client.storage.from(bucket).getPublicUrl(path.trim());
  }

  /// Public URL for a preset [iconKey] registered in [kSubscriptionPresetIconByKey].
  static String? presetPublicUrl(SupabaseClient client, String iconKey) {
    final preset = kSubscriptionPresetIconByKey[iconKey.trim().toLowerCase()];
    if (preset == null) return null;
    return publicUrl(client, presetBucket, preset.storagePath);
  }

  /// [iconUrl] may be a storage path or an already-resolved https URL.
  static String? resolveDisplayUrl(SupabaseClient client, String? iconUrl) {
    if (iconUrl == null || iconUrl.trim().isEmpty) return null;
    final t = iconUrl.trim();
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return resolvePathToPublicUrl(client, t);
  }

  /// Resolves a non-URL storage path to a public URL.
  ///
  /// - `custom/…` — user uploads in [presetBucket] (`subscription-icons`).
  /// - `userId/sub_…` (no `custom/` prefix) — legacy uploads in [legacyUserIconBucket].
  static String? resolvePathToPublicUrl(SupabaseClient client, String path) {
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final trimmed = path.trim();
    if (trimmed.startsWith('custom/')) {
      return publicUrl(client, presetBucket, trimmed);
    }
    if (trimmed.contains('/sub_')) {
      return publicUrl(client, legacyUserIconBucket, trimmed);
    }
    return publicUrl(client, presetBucket, trimmed);
  }

  /// Storage bucket for new gallery uploads (same as presets).
  static String get userUploadBucket => presetBucket;

  /// Path prefix for uploads in [userUploadBucket] (avoids clashing with legacy avatars paths).
  static String customUploadPath(String userId, String fileName) =>
      'custom/$userId/$fileName';

  /// Use for list/detail UI: prefer preset [iconKey], then [iconUrl].
  static String? resolveSubscriptionIconUrl(
    SupabaseClient client, {
    String? iconKey,
    String? iconUrl,
  }) {
    final key = validatedSubscriptionIconKey(iconKey);
    if (key != null) {
      return presetPublicUrl(client, key);
    }
    return resolveDisplayUrl(client, iconUrl);
  }
}

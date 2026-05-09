/// Predefined subscription service icons in Supabase Storage bucket `subscription-icons`.
///
/// Each [storagePath] must match the **exact** object key in the bucket (case-sensitive),
/// including extension. Your files are at the bucket root (no `presets/` folder).
class SubscriptionPresetIcon {
  const SubscriptionPresetIcon({
    required this.key,
    required this.label,
    required this.storagePath,
  });

  /// Stored in `subscriptions.icon_key` (snake_case ASCII).
  final String key;

  final String label;

  /// Path inside the `subscription-icons` bucket (exact key as in Dashboard).
  final String storagePath;
}

/// Keys stay snake_case for the DB; [storagePath] matches your uploaded filenames.
const List<SubscriptionPresetIcon> kSubscriptionPresetIcons = [
  SubscriptionPresetIcon(
    key: 'netflix',
    label: 'Netflix',
    storagePath: 'Netflix.webp',
  ),
  SubscriptionPresetIcon(
    key: 'osn',
    label: 'OSN',
    storagePath: 'Osn.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'tod',
    label: 'Tod',
    storagePath: 'Tod.webp',
  ),
  SubscriptionPresetIcon(
    key: 'shahid',
    label: 'Shahid',
    storagePath: 'Shahed.png',
  ),
  SubscriptionPresetIcon(
    key: 'watch_it',
    label: 'Watch it',
    storagePath: 'Watch_it.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'yango_play',
    label: 'Yango Play',
    storagePath: 'Yango_play.png',
  ),
  SubscriptionPresetIcon(
    key: 'amazon_prime',
    label: 'Amazon Prime',
    storagePath: 'Amazon_prime.png',
  ),
  SubscriptionPresetIcon(
    key: 'disney_plus',
    label: 'Disney+',
    storagePath: 'Disney.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'apple_tv',
    label: 'Apple TV',
    storagePath: 'Apple_tv.png',
  ),
  SubscriptionPresetIcon(
    key: 'crunchyroll',
    label: 'Crunchyroll',
    storagePath: 'Crunchyroll.png',
  ),
  SubscriptionPresetIcon(
    key: 'youtube',
    label: 'YouTube',
    storagePath: 'Youtube_premium.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'microsoft_365',
    label: 'Microsoft 365',
    storagePath: 'Microsoft365.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'adobe',
    label: 'Adobe',
    storagePath: 'Adobe.webp',
  ),
  SubscriptionPresetIcon(
    key: 'apple_music',
    label: 'Apple Music',
    storagePath: 'Apple_music.webp',
  ),
  SubscriptionPresetIcon(
    key: 'spotify',
    label: 'Spotify',
    storagePath: 'Spotify.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'talabat',
    label: 'Talabat',
    storagePath: 'Talabat.webp',
  ),
  SubscriptionPresetIcon(
    key: 'jahez',
    label: 'Jahez',
    storagePath: 'Jahez.png',
  ),
  SubscriptionPresetIcon(
    key: 'ahlan',
    label: 'Ahlan',
    storagePath: 'Ahlan.png',
  ),
  SubscriptionPresetIcon(
    key: 'chatgpt',
    label: 'ChatGPT',
    storagePath: 'Chatgpt.webp',
  ),
  SubscriptionPresetIcon(
    key: 'claude',
    label: 'Claude',
    storagePath: 'Claude.png',
  ),
  SubscriptionPresetIcon(
    key: 'gemini',
    label: 'Gemini',
    storagePath: 'Gemini.webp',
  ),
  SubscriptionPresetIcon(
    key: 'google_drive',
    label: 'Google Drive',
    storagePath: 'Google_drive.jpg',
  ),
  SubscriptionPresetIcon(
    key: 'onedrive',
    label: 'OneDrive',
    storagePath: 'OneDrive.png',
  ),
  SubscriptionPresetIcon(
    key: 'dropbox',
    label: 'Dropbox',
    storagePath: 'Dropbox.png',
  ),
];

final Map<String, SubscriptionPresetIcon> kSubscriptionPresetIconByKey = {
  for (final p in kSubscriptionPresetIcons) p.key: p,
};

String? validatedSubscriptionIconKey(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return null;
  return kSubscriptionPresetIconByKey.containsKey(t) ? t : null;
}

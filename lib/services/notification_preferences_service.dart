import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Row in `notification_preferences` (subset used by the app).
class NotificationPreferences {
  const NotificationPreferences({
    required this.notificationsEnabled,
    required this.smsAutoRecordingEnabled,
  });

  final bool notificationsEnabled;
  final bool smsAutoRecordingEnabled;

  factory NotificationPreferences.fromMap(Map<String, dynamic> m) {
    return NotificationPreferences(
      notificationsEnabled: m['notifications_enabled'] == true,
      smsAutoRecordingEnabled: m['sms_auto_recording_enabled'] == true,
    );
  }
}

/// Loads/saves notification prefs and keeps a cache for [shouldDeliverNotifications].
class NotificationPreferencesService {
  NotificationPreferencesService._();
  static final NotificationPreferencesService instance = NotificationPreferencesService._();

  final SupabaseClient _client = Supabase.instance.client;
  NotificationPreferences? _cached;

  /// When `notifications_enabled` is false, normal and AI notifications should not be shown/sent.
  /// Defaults to true until prefs are loaded (matches DB default intent).
  bool shouldDeliverNotifications() {
    return _cached?.notificationsEnabled ?? true;
  }

  void _setCache(NotificationPreferences? p) => _cached = p;

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// For Profile subtitle: `true` if no row yet (defaults to enabled) or column is true.
  Future<bool> profileNotificationsEnabled() async {
    final user = _client.auth.currentUser;
    if (user == null) return true;
    try {
      final row = await _client
          .from('notification_preferences')
          .select('notifications_enabled, sms_auto_recording_enabled')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) {
        _setCache(null);
        return true;
      }
      final map = Map<String, dynamic>.from(row);
      final p = NotificationPreferences.fromMap(map);
      _setCache(p);
      return p.notificationsEnabled;
    } catch (e, st) {
      debugPrint('notification_preferences profile fetch failed: $e\n$st');
      return true;
    }
  }

  /// Load prefs for settings; creates row with defaults if missing.
  Future<NotificationPreferences> loadOrCreateForSettings() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    final existing = await _client
        .from('notification_preferences')
        .select('notifications_enabled, sms_auto_recording_enabled')
        .eq('user_id', user.id)
        .maybeSingle();
    if (existing != null) {
      final p = NotificationPreferences.fromMap(Map<String, dynamic>.from(existing));
      _setCache(p);
      return p;
    }

    final now = _nowIso();
    try {
      await _client.from('notification_preferences').insert({
        'user_id': user.id,
        'notifications_enabled': true,
        'sms_auto_recording_enabled': false,
        'created_at': now,
        'updated_at': now,
      });
    } catch (e, st) {
      debugPrint('notification_preferences insert (maybe race): $e\n$st');
    }

    final again = await _client
        .from('notification_preferences')
        .select('notifications_enabled, sms_auto_recording_enabled')
        .eq('user_id', user.id)
        .maybeSingle();
    if (again == null) {
      throw StateError('Could not load notification preferences after insert');
    }
    final p = NotificationPreferences.fromMap(Map<String, dynamic>.from(again));
    _setCache(p);
    return p;
  }

  Future<void> updateNotificationsEnabled(bool value) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('notification_preferences').update({
      'notifications_enabled': value,
      'updated_at': _nowIso(),
    }).eq('user_id', user.id);
    _setCache(
      NotificationPreferences(
        notificationsEnabled: value,
        smsAutoRecordingEnabled: _cached?.smsAutoRecordingEnabled ?? false,
      ),
    );
  }

  Future<void> updateSmsAutoRecordingEnabled(bool value) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('notification_preferences').update({
      'sms_auto_recording_enabled': value,
      'updated_at': _nowIso(),
    }).eq('user_id', user.id);
    _setCache(
      NotificationPreferences(
        notificationsEnabled: _cached?.notificationsEnabled ?? true,
        smsAutoRecordingEnabled: value,
      ),
    );
  }
}

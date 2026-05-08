import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:infaq/services/bank_notification_sync_service.dart';
import 'package:infaq/services/notification_preferences_service.dart';

/// Android-only flow: explains notification-listener access for bank/SMS alerts
/// shown as notifications, optional runtime notification permission (Android 13+),
/// and tracks a one-time explanation dismiss while still allowing a home banner.
class AutoDetectionPermissionsCoordinator {
  AutoDetectionPermissionsCoordinator._();
  static final AutoDetectionPermissionsCoordinator instance =
      AutoDetectionPermissionsCoordinator._();

  static const _kIntroDismissed = 'auto_detection_permission_intro_dismissed_v1';

  bool _isAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Called once [HomeScreen] is shown (user is signed in with a profile row).
  Future<void> handleStartupOnHomeScreen(BuildContext context) async {
    if (!_isAndroid()) return;
    debugPrint('[Permissions] startup check (home)');

    final listenerOk =
        await BankNotificationSyncService.instance.isNotificationListenerEnabled();
    debugPrint('[Permissions] notification listener enabled=$listenerOk');

    if (!listenerOk) {
      final before = await Permission.notification.status;
      debugPrint('[Permissions] POST_NOTIFICATIONS before request: $before');
      if (!before.isGranted) {
        final req = await Permission.notification.request();
        debugPrint('[Permissions] POST_NOTIFICATIONS after request: $req');
      }
    }

    if (!context.mounted) return;

    if (listenerOk) return;

    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final introDismissed = prefs.getBool(_kIntroDismissed) ?? false;
    if (introDismissed) {
      debugPrint('[Permissions] intro already dismissed, skipping dialog');
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Enable automatic recording'),
          content: const Text(
            'INFAQ can record transactions from notifications your bank and wallet '
            'apps already show on your phone. SMS alerts also work when they appear '
            'as notifications in your messaging app.\n\n'
            'Next, turn on notification access for INFAQ in system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await prefs.setBool(_kIntroDismissed, true);
                debugPrint('[Permissions] user chose Maybe later');
              },
              child: Text(
                'Maybe later',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await prefs.setBool(_kIntroDismissed, true);
                debugPrint('[Permissions] opening notification listener settings');
                await BankNotificationSyncService.instance
                    .openNotificationListenerSettings();
              },
              child: const Text('Open settings'),
            ),
          ],
        );
      },
    );
  }

  /// After returning from Android settings, refresh banner visibility.
  Future<bool> shouldShowHomeBanner() async {
    if (!_isAndroid()) return false;
    final listenerOk =
        await BankNotificationSyncService.instance.isNotificationListenerEnabled();
    if (listenerOk) return false;

    try {
      final p = await NotificationPreferencesService.instance
          .loadOrCreateForSettings();
      final prefs = await SharedPreferences.getInstance();
      final introDismissed = prefs.getBool(_kIntroDismissed) ?? false;
      return p.smsAutoRecordingEnabled || introDismissed;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kIntroDismissed) ?? false;
    }
  }

  Future<void> openListenerSettingsFromBanner() async {
    debugPrint('[Permissions] banner: open listener settings');
    await BankNotificationSyncService.instance.openNotificationListenerSettings();
  }
}

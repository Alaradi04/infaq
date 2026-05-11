import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Minimal wrapper around [FlutterLocalNotificationsPlugin] for INFAQ.
///
/// Initialization is **lazy** (never blocks [main]). Call [ensureInitialized]
/// before show/schedule/cancel.
class InfaqLocalNotificationsService {
  InfaqLocalNotificationsService._();
  static final InfaqLocalNotificationsService instance =
      InfaqLocalNotificationsService._();

  static const String _log = '[LocalNotif]';

  static const String _androidChannelId = 'infaq_local_default';
  static const String _androidChannelName = 'INFAQ alerts';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initFuture;

  bool get isInitialized => _initialized;

  /// Single-flight init; safe to call from many places.
  Future<void> ensureInitialized() {
    if (_initialized) {
      return Future.value();
    }
    _initFuture ??= _performInit();
    return _initFuture!;
  }

  Future<void> _performInit() async {
    if (_initialized) {
      return;
    }
    debugPrint('$_log service init: start');
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
        debugPrint('$_log timezone set: $name');
      } catch (e, st) {
        debugPrint('$_log timezone init failed, UTC fallback: $e\n$st');
        tz.setLocalLocation(tz.UTC);
      }

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _plugin.initialize(initSettings);
      debugPrint('$_log plugin.initialize: completed');

      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            description: 'INFAQ local alerts and reminders',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        debugPrint('$_log Android channel created: $_androidChannelId');
      }

      _initialized = true;
      debugPrint('$_log service init: success (initialized=true)');
    } catch (e, st) {
      debugPrint('$_log service init: FAILED\n$e\n$st');
      _initFuture = null;
      rethrow;
    }
  }

  NotificationDetails _defaultDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelShowBadge: true,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// When [requestAndroidPermissionIfDenied] is true, runs a permission request
  /// (Android 13+). Transaction pipeline uses false and skips show if not granted.
  Future<bool> showImmediate({
    required int notificationId,
    required String title,
    required String body,
    bool requestAndroidPermissionIfDenied = false,
  }) async {
    try {
      await ensureInitialized();
    } catch (e, st) {
      debugPrint('$_log showImmediate: init failed before show: $e\n$st');
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      var status = await Permission.notification.status;
      debugPrint('$_log showImmediate: POST_NOTIFICATIONS status=$status');
      if (!status.isGranted) {
        if (requestAndroidPermissionIfDenied) {
          status = await Permission.notification.request();
          debugPrint(
            '$_log showImmediate: POST_NOTIFICATIONS after request=$status',
          );
        }
        if (!status.isGranted) {
          debugPrint(
            '$_log showImmediate: ABORT (POST_NOTIFICATIONS not granted)',
          );
          return false;
        }
      }
    }

    try {
      debugPrint(
        '$_log showImmediate: calling show id=$notificationId title=$title',
      );
      await _plugin.show(
        notificationId,
        title,
        body,
        _defaultDetails(),
      );
      debugPrint('$_log showImmediate: show completed id=$notificationId');
      return true;
    } catch (e, st) {
      debugPrint('$_log showImmediate: show FAILED\n$e\n$st');
      return false;
    }
  }

  Future<bool> scheduleAt({
    required int notificationId,
    required String title,
    required String body,
    required DateTime whenLocal,
  }) async {
    try {
      await ensureInitialized();
    } catch (e, st) {
      debugPrint('$_log scheduleAt: init failed: $e\n$st');
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await Permission.notification.isGranted;
      debugPrint(
        '$_log scheduleAt: POST_NOTIFICATIONS isGranted=$granted',
      );
      if (!granted) {
        debugPrint(
          '$_log scheduleAt: ABORT (cannot schedule without notification permission)',
        );
        return false;
      }
    }

    final tz.TZDateTime scheduled = tz.TZDateTime.from(whenLocal, tz.local);
    final nowTz = tz.TZDateTime.now(tz.local);
    if (scheduled.isBefore(nowTz)) {
      debugPrint(
        '$_log scheduleAt: skip id=$notificationId (scheduled in past: $scheduled)',
      );
      return false;
    }

    try {
      debugPrint(
        '$_log scheduleAt: zonedSchedule id=$notificationId at=$scheduled',
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _plugin.zonedSchedule(
            notificationId,
            title,
            body,
            scheduled,
            _defaultDetails(),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (e, st) {
          debugPrint(
            '$_log scheduleAt: exact mode failed, retry inexact: $e\n$st',
          );
          await _plugin.zonedSchedule(
            notificationId,
            title,
            body,
            scheduled,
            _defaultDetails(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      } else {
        await _plugin.zonedSchedule(
          notificationId,
          title,
          body,
          scheduled,
          _defaultDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      debugPrint('$_log scheduleAt: completed id=$notificationId');
      return true;
    } catch (e, st) {
      debugPrint('$_log scheduleAt: FAILED\n$e\n$st');
      return false;
    }
  }

  Future<void> cancel(int notificationId) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(notificationId);
    } catch (e, st) {
      debugPrint('$_log cancel id=$notificationId failed: $e\n$st');
    }
  }

  Future<void> cancelAll() async {
    try {
      await ensureInitialized();
      await _plugin.cancelAll();
    } catch (e, st) {
      debugPrint('$_log cancelAll failed: $e\n$st');
    }
  }

  /// Used by debug UI: request permission then show (logs each step).
  Future<String?> debugSendTestNotification() async {
    debugPrint('$_log TEST: debugSendTestNotification start');
    try {
      await ensureInitialized();
    } catch (e, st) {
      final msg = 'Init failed: $e';
      debugPrint('$_log TEST: $msg\n$st');
      return msg;
    }
    final ok = await showImmediate(
      notificationId: 9_001_001,
      title: 'INFAQ test',
      body: 'Local notifications are working.',
      requestAndroidPermissionIfDenied: true,
    );
    if (ok) {
      debugPrint('$_log TEST: debugSendTestNotification success');
      return null;
    }
    const msg =
        'Notification permission denied or show failed. Enable notifications for INFAQ in system settings.';
    debugPrint('$_log TEST: $msg');
    return msg;
  }

  /// Used by debug UI: request permission then schedule in ~10s.
  Future<String?> debugScheduleTestIn10Seconds() async {
    debugPrint('$_log TEST: debugScheduleTestIn10Seconds start');
    try {
      await ensureInitialized();
    } catch (e, st) {
      final msg = 'Init failed: $e';
      debugPrint('$_log TEST: $msg\n$st');
      return msg;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final r = await Permission.notification.request();
      debugPrint('$_log TEST: POST_NOTIFICATIONS after request=$r');
      if (!r.isGranted) {
        const msg =
            'Notification permission denied. Allow notifications for INFAQ to test scheduling.';
        debugPrint('$_log TEST: $msg');
        return msg;
      }
    }
    final when = DateTime.now().add(const Duration(seconds: 10));
    final ok = await scheduleAt(
      notificationId: 9_001_002,
      title: 'INFAQ scheduled test',
      body: 'This was scheduled 10 seconds ago for testing.',
      whenLocal: when,
    );
    if (ok) {
      debugPrint('$_log TEST: debugScheduleTestIn10Seconds success');
      return null;
    }
    const msg = 'Schedule failed (see logs for exception).';
    debugPrint('$_log TEST: $msg');
    return msg;
  }

  static int notificationIdFor(String logicalKey) {
    return logicalKey.hashCode & 0x7fffffff;
  }
}

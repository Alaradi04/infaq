import 'package:flutter/foundation.dart';
import 'package:infaq/services/infaq_local_notifications_service.dart';
import 'package:infaq/services/local_notification_toggle_store.dart';
import 'package:infaq/services/notification_preferences_service.dart';
import 'package:infaq/subscription_renewal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Date-based subscription reminders (local midnight + 5 minutes), not fixed 9 AM.
class SubscriptionReminderLocalNotifications {
  SubscriptionReminderLocalNotifications._();

  static const _log = '[LocalNotif][Sub]';
  static const _kTracked = 'ln_sub_reminder_pairs_v1';

  /// Local fire time on a calendar day (not renewal-specific hour).
  static DateTime _at005OnDay(DateTime day) =>
      DateTime(day.year, day.month, day.day, 0, 5);

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<bool> _gate() async {
    if (!NotificationPreferencesService.instance.shouldDeliverNotifications()) {
      return false;
    }
    final toggles = await LocalNotificationToggleStore.readAll();
    if (!toggles.subscription) {
      return false;
    }
    return true;
  }

  static Future<List<String>> _tracked() async {
    final p = await SharedPreferences.getInstance();
    return List<String>.from(p.getStringList(_kTracked) ?? const []);
  }

  static Future<void> _setTracked(List<String> entries) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kTracked, entries);
  }

  static String _pairKey(String subscriptionId, String renewalIso) =>
      '$subscriptionId|$renewalIso';

  static Future<void> _cancelPairIds(String subscriptionId, String renewalIso) {
    final d2 = InfaqLocalNotificationsService.notificationIdFor(
      'subscription_2_days:$subscriptionId:$renewalIso',
    );
    final d1 = InfaqLocalNotificationsService.notificationIdFor(
      'subscription_1_day:$subscriptionId:$renewalIso',
    );
    return Future.wait([
      InfaqLocalNotificationsService.instance.cancel(d2),
      InfaqLocalNotificationsService.instance.cancel(d1),
    ]);
  }

  /// Removes scheduled reminders for [subscriptionId] (any renewal date).
  static Future<void> cancelRemindersForSubscriptionId(String subscriptionId) async {
    await InfaqLocalNotificationsService.instance.ensureInitialized();
    debugPrint('$_log cancel: subscriptionId=$subscriptionId');
    final list = await _tracked();
    final next = <String>[];
    for (final e in list) {
      final parts = e.split('|');
      if (parts.length == 2 && parts[0] == subscriptionId) {
        debugPrint(
          '$_log cancel: pair renewalIso=${parts[1]} (clearing scheduled ids)',
        );
        await _cancelPairIds(parts[0], parts[1]);
      } else {
        next.add(e);
      }
    }
    await _setTracked(next);
    debugPrint('$_log cancel: done subscriptionId=$subscriptionId');
  }

  static Future<void> cancelAllTrackedReminders() async {
    await InfaqLocalNotificationsService.instance.ensureInitialized();
    debugPrint('$_log cancelAllTracked: begin');
    final list = await _tracked();
    for (final e in list) {
      final parts = e.split('|');
      if (parts.length == 2) {
        await _cancelPairIds(parts[0], parts[1]);
      }
    }
    await _setTracked([]);
    debugPrint('$_log cancelAllTracked: done');
  }

  /// 2-day / 1-day reminder relative to renewal [date] only; fire at 00:05 that day or immediately if that moment passed today.
  static Future<void> _scheduleOrShowDateReminder({
    required String subscriptionId,
    required String subscriptionName,
    required String renewalIso,
    required DateTime reminderDate,
    required bool isTwoDayReminder,
    required int notificationId,
  }) async {
    final today = _startOfDay(DateTime.now());
    final remDay = _startOfDay(reminderDate);
    final now = DateTime.now();
    final fireAt = _at005OnDay(remDay);

    if (remDay.isBefore(today)) {
      debugPrint(
        '$_log ${isTwoDayReminder ? "2-day" : "1-day"} SKIP (past date): '
        'subId=$subscriptionId name=$subscriptionName renewal=$renewalIso '
        'reminderDate=${remDay.toIso8601String().split("T").first}',
      );
      return;
    }

    final title = isTwoDayReminder
        ? '$subscriptionName renews soon'
        : '$subscriptionName renews tomorrow';
    final body = isTwoDayReminder
        ? 'Your $subscriptionName subscription renews in 2 days.'
        : 'Your $subscriptionName subscription renews tomorrow.';

    if (remDay == today) {
      if (!now.isBefore(fireAt)) {
        debugPrint(
          '$_log ${isTwoDayReminder ? "2-day" : "1-day"} IMMEDIATE: '
          'subId=$subscriptionId name=$subscriptionName renewal=$renewalIso '
          'reminderDate=${remDay.toIso8601String().split("T").first} '
          '(now >= 00:05 today)',
        );
        await InfaqLocalNotificationsService.instance.showImmediate(
          notificationId: notificationId,
          title: title,
          body: body,
        );
      } else {
        debugPrint(
          '$_log ${isTwoDayReminder ? "2-day" : "1-day"} SCHEDULE: '
          'subId=$subscriptionId name=$subscriptionName renewal=$renewalIso '
          'at=$fireAt (today, before 00:05)',
        );
        await InfaqLocalNotificationsService.instance.scheduleAt(
          notificationId: notificationId,
          title: title,
          body: body,
          whenLocal: fireAt,
        );
      }
    } else {
      debugPrint(
        '$_log ${isTwoDayReminder ? "2-day" : "1-day"} SCHEDULE: '
        'subId=$subscriptionId name=$subscriptionName renewal=$renewalIso '
        'reminderDate=${remDay.toIso8601String().split("T").first} at=$fireAt',
      );
      await InfaqLocalNotificationsService.instance.scheduleAt(
        notificationId: notificationId,
        title: title,
        body: body,
        whenLocal: fireAt,
      );
    }
  }

  /// Replaces reminders for this subscription row (after add/edit).
  static Future<void> replaceRemindersForSubscription(
    Map<String, dynamic> subscription,
  ) async {
    await InfaqLocalNotificationsService.instance.ensureInitialized();

    final id = subscription['id']?.toString();
    if (id == null || id.isEmpty) {
      debugPrint('$_log replace: skip (missing id)');
      return;
    }

    final rawName = (subscription['name'] ?? 'Subscription').toString().trim();
    final displayName = rawName.isEmpty ? 'Subscription' : rawName;
    final active = SubscriptionRenewal.isActive(subscription);

    debugPrint(
      '$_log replace: begin subId=$id name=$displayName isActive=$active',
    );

    await cancelRemindersForSubscriptionId(id);

    if (!await _gate()) {
      debugPrint('$_log replace: aborted (notifications gate off)');
      return;
    }
    if (!active) {
      debugPrint(
        '$_log replace: done (inactive — pending reminders cancelled only)',
      );
      return;
    }

    final nextRenewal = SubscriptionRenewal.displayNextRenewal(subscription);
    if (nextRenewal == null) {
      debugPrint('$_log replace: skip (no next renewal date)');
      return;
    }

    final renewalDay = _startOfDay(nextRenewal);
    final renewalIso = SubscriptionRenewal.toIsoDate(nextRenewal);
    final twoDayReminderDate = renewalDay.subtract(const Duration(days: 2));
    final oneDayReminderDate = renewalDay.subtract(const Duration(days: 1));

    debugPrint(
      '$_log replace: renewalDate=${renewalDay.toIso8601String().split("T").first} '
      'twoDayReminder=${_startOfDay(twoDayReminderDate).toIso8601String().split("T").first} '
      'oneDayReminder=${_startOfDay(oneDayReminderDate).toIso8601String().split("T").first}',
    );

    final id2 = InfaqLocalNotificationsService.notificationIdFor(
      'subscription_2_days:$id:$renewalIso',
    );
    final id1 = InfaqLocalNotificationsService.notificationIdFor(
      'subscription_1_day:$id:$renewalIso',
    );

    await _scheduleOrShowDateReminder(
      subscriptionId: id,
      subscriptionName: displayName,
      renewalIso: renewalIso,
      reminderDate: twoDayReminderDate,
      isTwoDayReminder: true,
      notificationId: id2,
    );

    await _scheduleOrShowDateReminder(
      subscriptionId: id,
      subscriptionName: displayName,
      renewalIso: renewalIso,
      reminderDate: oneDayReminderDate,
      isTwoDayReminder: false,
      notificationId: id1,
    );

    final tracked = await _tracked();
    final key = _pairKey(id, renewalIso);
    if (!tracked.contains(key)) {
      tracked.add(key);
      await _setTracked(tracked);
    }
    debugPrint('$_log replace: complete subId=$id renewal=$renewalIso');
  }
}

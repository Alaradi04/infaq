import 'package:flutter/foundation.dart';
import 'package:infaq/services/infaq_local_notifications_service.dart';
import 'package:infaq/services/local_notification_dedupe_store.dart';
import 'package:infaq/services/notification_preferences_service.dart';

/// Local goal alerts after a successful goal save (add/edit). No scheduling on startup.
class GoalLocalNotifications {
  GoalLocalNotifications._();

  static const _log = '[LocalNotif][Goal]';

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fmtMoney(double amount) {
    if (amount.isNaN || amount.isInfinite) return '0';
    final a = amount.abs();
    if ((a * 100).round() / 100 == a.roundToDouble()) {
      return a.toStringAsFixed(a % 1 == 0 ? 0 : 2);
    }
    return a.toStringAsFixed(2);
  }

  /// ISO-like year-week label for dedupe (Monday-based week-of-year, 1–53).
  static String _yearWeekKey(DateTime d) {
    final x = _startOfDay(d);
    final jan1 = DateTime(x.year, 1, 1);
    final firstMonday = jan1.subtract(Duration(days: (jan1.weekday - 1) % 7));
    final w = 1 + x.difference(firstMonday).inDays ~/ 7;
    return '${x.year}-W${w.clamp(1, 53).toString().padLeft(2, '0')}';
  }

  static String _yearMonth(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Days from [today] (date-only) to [deadline] (date-only), inclusive sense: 0 = today.
  static int _daysUntilDeadline(DateTime today, DateTime deadline) {
    final a = _startOfDay(today);
    final b = _startOfDay(deadline);
    return b.difference(a).inDays;
  }

  /// Priority: completed > deadline tomorrow > close > deadline within 7 days.
  /// Returns at most one notification per save.
  static Future<void> onAfterGoalSaved({
    required String? goalId,
    required String title,
    required double target,
    required double current,
    required String deadlineIso,
    String? currencyCode,
  }) async {
    if (!NotificationPreferencesService.instance.shouldDeliverNotifications()) {
      debugPrint('$_log skip: master notifications disabled');
      return;
    }
    if (goalId == null || goalId.isEmpty) {
      debugPrint('$_log skip: missing goalId');
      return;
    }

    final deadline = DateTime.tryParse(deadlineIso);
    if (deadline == null) {
      debugPrint('$_log skip: bad deadlineIso=$deadlineIso');
      return;
    }

    final displayTitle = title.trim().isEmpty ? 'Your goal' : title.trim();
    final cur = (currencyCode ?? '').trim().toUpperCase();
    final currencyPrefix = cur.isEmpty ? '' : '$cur ';

    final today = DateTime.now();
    final days = _daysUntilDeadline(today, deadline);
    final remaining = target - current;

    debugPrint(
      '$_log evaluate: goalId=$goalId title=$displayTitle target=$target '
      'current=$current deadline=$deadlineIso daysUntil=$days remaining=$remaining',
    );

    late final String dedupeKey;
    late final String notifTitle;
    late final String notifBody;

    if (current >= target && target > 0) {
      dedupeKey = 'goal_completed:$goalId';
      notifTitle = 'Goal completed';
      notifBody =
          'Congrats! You completed your $displayTitle goal.';
      debugPrint('$_log pick: completed dedupe=$dedupeKey');
    } else if (days == 1) {
      final dKey = deadlineIso.contains('T')
          ? deadlineIso.split('T').first
          : deadlineIso;
      dedupeKey = 'goal_deadline_tomorrow:$goalId:$dKey';
      notifTitle = 'Goal deadline tomorrow';
      notifBody =
          'Your $displayTitle goal deadline is tomorrow.';
      debugPrint('$_log pick: deadline_tomorrow dedupe=$dedupeKey');
    } else if (remaining > 0 && remaining <= target * 0.10 && target > 0) {
      dedupeKey = 'goal_close:$goalId:${_yearMonth(today)}';
      notifTitle = 'Goal is close';
      notifBody =
          'Only $currencyPrefix${_fmtMoney(remaining)} left to complete your $displayTitle goal.';
      debugPrint('$_log pick: close dedupe=$dedupeKey');
    } else if (days >= 0 && days <= 7 && days != 1) {
      dedupeKey = 'goal_deadline_soon:$goalId:${_yearWeekKey(today)}';
      notifTitle = 'Goal deadline is coming';
      notifBody =
          'Your $displayTitle goal deadline is coming soon.';
      debugPrint('$_log pick: deadline_soon dedupe=$dedupeKey days=$days');
    } else {
      debugPrint('$_log pick: none (no rule matched)');
      return;
    }

    if (!await LocalNotificationDedupeStore.consumeIfNew(dedupeKey)) {
      debugPrint('$_log skip: already sent ($dedupeKey)');
      return;
    }

    await InfaqLocalNotificationsService.instance.ensureInitialized();
    final nid = InfaqLocalNotificationsService.notificationIdFor(dedupeKey);
    final ok = await InfaqLocalNotificationsService.instance.showImmediate(
      notificationId: nid,
      title: notifTitle,
      body: notifBody,
    );
    if (ok) {
      debugPrint('$_log show OK id=$nid');
    } else {
      await LocalNotificationDedupeStore.clearKey(dedupeKey);
      debugPrint('$_log show FAILED, reverted dedupe ($dedupeKey)');
    }
  }
}

import 'package:flutter/foundation.dart';

/// Next renewal display and optional DB sync. Uses [next_payment] as anchor only
/// (never [created_at]). Normalizes stale or implausible dates by [billing_cycle].
class SubscriptionRenewal {
  SubscriptionRenewal._();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _clampDayInMonth(int year, int month, int day) {
    final last = DateTime(year, month + 1, 0).day;
    return day > last ? last : day;
  }

  /// Part 2: next calendar occurrence of [paymentDay] on or after [today].
  static DateTime monthlyCandidateFromToday(DateTime today, int paymentDay) {
    final t = _dateOnly(today);
    var y = t.year;
    var m = t.month;
    var d = _clampDayInMonth(y, m, paymentDay);
    var candidate = DateTime(y, m, d);
    if (candidate.isBefore(t)) {
      if (m == 12) {
        y += 1;
        m = 1;
      } else {
        m += 1;
      }
      d = _clampDayInMonth(y, m, paymentDay);
      candidate = DateTime(y, m, d);
    }
    return candidate;
  }

  /// Part 3: next yearly occurrence of anchor month/day on or after [today].
  static DateTime yearlyCandidateFromToday(DateTime today, DateTime anchor) {
    final t = _dateOnly(today);
    final a = _dateOnly(anchor);
    var y = t.year;
    var d = _clampDayInMonth(y, a.month, a.day);
    var candidate = DateTime(y, a.month, d);
    if (candidate.isBefore(t)) {
      y = t.year + 1;
      d = _clampDayInMonth(y, a.month, a.day);
      candidate = DateTime(y, a.month, d);
    }
    return candidate;
  }

  /// Anchor date from DB (local calendar day).
  static DateTime? anchorDate(Map<String, dynamic> s) {
    final raw = s['next_payment'] ?? s['next_payment_date'];
    if (raw == null) return null;
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return null;
    final l = d.toLocal();
    return _dateOnly(l);
  }

  static bool isActive(Map<String, dynamic> s) {
    final v = s['is_active'];
    if (v == false || v == 0) return false;
    if (v == true || v == 1) return true;
    final str = v?.toString().toLowerCase();
    return str != 'false' && str != '0' && str != 'inactive';
  }

  static String normalizedCycle(Map<String, dynamic> s) {
    return (s['billing_cycle'] ?? 'monthly').toString().toLowerCase().trim();
  }

  static int? customIntervalDays(Map<String, dynamic> s) {
    for (final k in const [
      'billing_interval_days',
      'interval_days',
      'custom_interval_days',
      'billing_interval',
    ]) {
      final v = s[k];
      if (v is int && v > 0) return v;
      if (v is num && v.toInt() > 0) return v.toInt();
      final p = int.tryParse(v?.toString() ?? '');
      if (p != null && p > 0) return p;
    }
    return null;
  }

  static bool isRollingRecurring(Map<String, dynamic> s) {
    final c = normalizedCycle(s);
    const known = {'monthly', 'yearly', 'weekly', 'daily'};
    if (known.contains(c)) return true;
    if (c == 'custom' && customIntervalDays(s) != null) return true;
    return false;
  }

  static bool isInvalidOrNonRollingCycle(Map<String, dynamic> s) {
    final c = normalizedCycle(s);
    if (c.isEmpty) return true;
    const known = {'monthly', 'yearly', 'weekly', 'daily', 'custom'};
    if (!known.contains(c)) return true;
    if (c == 'custom' && customIntervalDays(s) == null) return true;
    return false;
  }

  /// Next renewal date to display.
  static DateTime? displayNextRenewal(
    Map<String, dynamic> s, {
    DateTime? now,
  }) {
    final anchor = anchorDate(s);
    if (anchor == null) return null;
    final today = _dateOnly(now ?? DateTime.now());
    if (!isActive(s)) {
      return anchor;
    }
    if (!isRollingRecurring(s)) {
      return anchor;
    }
    return _computeActiveRenewal(anchor, s, today);
  }

  static DateTime _computeActiveRenewal(
    DateTime anchor,
    Map<String, dynamic> s,
    DateTime today,
  ) {
    final c = normalizedCycle(s);
    switch (c) {
      case 'monthly':
        return _monthlyNextRenewal(anchor, today);
      case 'yearly':
        final yc = yearlyCandidateFromToday(today, anchor);
        if (anchor.isBefore(today)) {
          return yc;
        }
        return yc.isBefore(anchor) ? yc : anchor;
      case 'weekly':
        var n = anchor;
        while (n.isBefore(today)) {
          n = n.add(const Duration(days: 7));
          n = _dateOnly(n);
        }
        return n;
      case 'daily':
        var n = anchor;
        while (n.isBefore(today)) {
          n = n.add(const Duration(days: 1));
          n = _dateOnly(n);
        }
        return n;
      case 'custom':
        final days = customIntervalDays(s) ?? 1;
        var n = anchor;
        while (n.isBefore(today)) {
          n = n.add(Duration(days: days));
          n = _dateOnly(n);
        }
        return n;
      default:
        return anchor;
    }
  }

  /// Part 1–2: payment day from [anchor]; stale anchors use candidate only.
  /// If [anchor] is still in the future, use whichever is sooner: the day-of-month
  /// candidate (this/next month) or [anchor], so a wrong far-future stored date
  /// does not show "32d left" when the real next bill is this month.
  static DateTime _monthlyNextRenewal(DateTime anchor, DateTime today) {
    final paymentDay = anchor.day;
    final candidate = monthlyCandidateFromToday(today, paymentDay);
    if (anchor.isBefore(today)) {
      return candidate;
    }
    return candidate.isBefore(anchor) ? candidate : anchor;
  }

  /// ISO `YYYY-MM-DD` for Supabase date columns.
  static String toIsoDate(DateTime d) {
    final x = _dateOnly(d);
    final m = x.month.toString().padLeft(2, '0');
    final day = x.day.toString().padLeft(2, '0');
    return '${x.year}-$m-$day';
  }

  /// Persist when computed renewal differs from stored anchor (active recurring only).
  static bool shouldPersistRolledDate(
    Map<String, dynamic> s,
    DateTime storedAnchor,
    DateTime rolled,
  ) {
    if (!isActive(s)) return false;
    if (!isRollingRecurring(s)) return false;
    return !_sameDay(storedAnchor, rolled);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Part 9: one-line debug per subscription.
  static void debugLogRenewal(
    Map<String, dynamic> s, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final anchor = anchorDate(s);
    final computed = displayNextRenewal(s, now: now);
    final daysLeft = computed?.difference(today).inDays;
    debugPrint(
      '[sub renewal] name=${s['name']} billing_cycle=${normalizedCycle(s)} '
      'stored_next_payment=${anchor == null ? 'null' : toIsoDate(anchor)} '
      'today=${toIsoDate(today)} '
      'computed_next=${computed == null ? 'null' : toIsoDate(computed)} '
      'days_left=$daysLeft',
    );
  }
}

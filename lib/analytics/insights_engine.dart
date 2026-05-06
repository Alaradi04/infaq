import 'package:flutter/material.dart';
import 'package:infaq/analytics/insights_models.dart';
import 'package:infaq/category/category_icons.dart';
import 'package:infaq/subscription/subscription_analytics.dart';

DateTime? parseTxLocalDate(Map<String, dynamic> t) {
  final raw = t['date'] ?? t['created_at'];
  if (raw == null) return null;
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return null;
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

double readAmount(Map<String, dynamic> t) => subReadAmount(t['amount']);

bool txIsIncome(Map<String, dynamic> t) {
  final cat = t['categories'];
  if (cat is Map) {
    final ty = cat['type']?.toString().toLowerCase();
    if (ty == 'income') return true;
    if (ty == 'expense') return false;
  }
  final legacy = (t['type'] ?? t['transaction_type'] ?? '').toString().toLowerCase();
  return legacy == 'income' || legacy == 'credit' || legacy == 'in';
}

bool txIsExpense(Map<String, dynamic> t, double amount) {
  if (txIsIncome(t)) return false;
  return subIsExpense(t, amount);
}

bool _inInclusiveRange(DateTime? d, DateTime start, DateTime end) {
  if (d == null) return false;
  return !d.isBefore(start) && !d.isAfter(end);
}

Map<String, double> expenseByCategory(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  final map = <String, double>{};
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (!_inInclusiveRange(d, start, end)) continue;
    final amt = readAmount(t);
    if (!txIsExpense(t, amt)) continue;
    final cat = t['categories'];
    final name = cat is Map ? (cat['name'] ?? 'Uncategorized').toString().trim() : 'Uncategorized';
    final key = name.isEmpty ? 'Uncategorized' : name;
    map[key] = (map[key] ?? 0) + amt.abs();
  }
  return map;
}

(double income, double expense) sumIncomeExpense(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  var inc = 0.0;
  var exp = 0.0;
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (!_inInclusiveRange(d, start, end)) continue;
    final amt = readAmount(t);
    if (txIsIncome(t)) {
      inc += amt.abs();
    } else if (txIsExpense(t, amt)) {
      exp += amt.abs();
    }
  }
  return (inc, exp);
}

double sumSubscriptionLinkedExpenses(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  var sum = 0.0;
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (!_inInclusiveRange(d, start, end)) continue;
    final sid = t['subscription_id'];
    if (sid == null || sid.toString().isEmpty) continue;
    final amt = readAmount(t);
    if (txIsExpense(t, amt)) sum += amt.abs();
  }
  return sum;
}

MonthComparison buildMonthComparison(
  Iterable<Map<String, dynamic>> transactions,
  DateTime now,
) {
  final thisM = DateTime(now.year, now.month, 1);
  final (thisStart, thisEnd) = calendarMonthBounds(thisM);
  final lastM = DateTime(now.year, now.month - 1, 1);
  final (lastStart, lastEnd) = calendarMonthBounds(lastM);

  final tThis = sumIncomeExpense(transactions, thisStart, thisEnd);
  final tLast = sumIncomeExpense(transactions, lastStart, lastEnd);
  return MonthComparison(
    thisMonthIncome: tThis.$1,
    thisMonthExpense: tThis.$2,
    thisMonthNet: tThis.$1 - tThis.$2,
    lastMonthIncome: tLast.$1,
    lastMonthExpense: tLast.$2,
    lastMonthNet: tLast.$1 - tLast.$2,
  );
}

List<CategorySpendSlice> buildCategorySlices(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  final grouped = <String, ({String name, String? id, dynamic savedColor, double amount})>{};
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (!_inInclusiveRange(d, start, end)) continue;
    final amt = readAmount(t);
    if (!txIsExpense(t, amt)) continue;
    final cat = t['categories'];
    final catNameRaw = cat is Map ? cat['name']?.toString() : null;
    final name = (catNameRaw == null || catNameRaw.trim().isEmpty) ? 'Uncategorized' : catNameRaw.trim();
    final id = (cat is Map ? cat['id'] : null)?.toString() ?? t['category_id']?.toString();
    final savedColor = cat is Map ? (cat['color'] ?? cat['color_value'] ?? cat['hex_color']) : null;
    final key = (id != null && id.isNotEmpty) ? 'id:$id' : 'name:${name.toLowerCase()}';
    final prev = grouped[key];
    grouped[key] = (
      name: name,
      id: id,
      savedColor: savedColor ?? prev?.savedColor,
      amount: (prev?.amount ?? 0) + amt.abs(),
    );
  }

  final entries = grouped.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  return [
    for (final e in entries)
      CategorySpendSlice(
        name: e.name,
        amount: e.amount,
        color: categoryDisplayColorFor(e.name, categoryId: e.id, savedColor: e.savedColor),
      ),
  ];
}

List<TrendBarSlice> buildTrendBars(
  InsightsTimeRange range,
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  switch (range) {
    case InsightsTimeRange.thisWeek:
      return _dailyBars(transactions, start, end);
    case InsightsTimeRange.thisYear:
      return _monthlyBarsYear(transactions, start, end);
    case InsightsTimeRange.thisMonth:
    case InsightsTimeRange.lastMonth:
      return _weekBucketsInRange(transactions, start, end);
  }
}

List<TrendBarSlice> _dailyBars(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  final map = <DateTime, double>{};
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    map[DateTime(d.year, d.month, d.day)] = 0;
  }
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (d == null || d.isBefore(start) || d.isAfter(end)) continue;
    final amt = readAmount(t);
    if (!txIsExpense(t, amt)) continue;
    final key = DateTime(d.year, d.month, d.day);
    map[key] = (map[key] ?? 0) + amt.abs();
  }
  final keys = map.keys.toList()..sort();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return [
    for (final k in keys)
      TrendBarSlice(label: days[k.weekday - 1], amount: map[k] ?? 0),
  ];
}

List<TrendBarSlice> _weekBucketsInRange(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  final totalDays = end.difference(start).inDays + 1;
  final bucketCount = totalDays <= 7 ? totalDays : (totalDays / 7).ceil().clamp(1, 6);
  final bucketSize = (totalDays / bucketCount).ceil().clamp(1, 999);
  final amounts = List<double>.filled(bucketCount, 0);

  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (d == null || d.isBefore(start) || d.isAfter(end)) continue;
    final amt = readAmount(t);
    if (!txIsExpense(t, amt)) continue;
    final idx = d.difference(start).inDays ~/ bucketSize;
    final i = idx.clamp(0, bucketCount - 1);
    amounts[i] += amt.abs();
  }

  return [
    for (var i = 0; i < bucketCount; i++)
      TrendBarSlice(label: 'W${i + 1}', amount: amounts[i]),
  ];
}

/// One bar per calendar month from [start] through [end] (inclusive, date-only).
List<TrendBarSlice> _monthlyBarsCalendarSpan(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
  final out = <TrendBarSlice>[];
  final startD = DateTime(start.year, start.month, start.day);
  final endD = DateTime(end.year, end.month, end.day);
  var cur = DateTime(startD.year, startD.month, 1);
  final endMonth = DateTime(endD.year, endD.month, 1);
  final sameYearAcrossRange = startD.year == endD.year;
  while (!cur.isAfter(endMonth)) {
    final monthStart = DateTime(cur.year, cur.month, 1);
    final monthEnd = DateTime(cur.year, cur.month + 1, 0);
    final sliceStart = monthStart.isBefore(startD) ? startD : monthStart;
    final sliceEnd = monthEnd.isAfter(endD) ? endD : monthEnd;
    var sum = 0.0;
    for (final t in transactions) {
      final d = parseTxLocalDate(t);
      if (d == null || d.isBefore(sliceStart) || d.isAfter(sliceEnd)) continue;
      final amt = readAmount(t);
      if (!txIsExpense(t, amt)) continue;
      sum += amt.abs();
    }
    final lbl = sameYearAcrossRange ? labels[cur.month - 1] : '${labels[cur.month - 1]} ${cur.year}';
    out.add(TrendBarSlice(label: lbl, amount: sum));
    cur = DateTime(cur.year, cur.month + 1, 1);
  }
  return out;
}

/// Trend chart for a user-picked date range on the Insights screen.
List<TrendBarSlice> buildTrendBarsForCustomRange(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  final startD = DateTime(start.year, start.month, start.day);
  final endD = DateTime(end.year, end.month, end.day);
  final spanDays = endD.difference(startD).inDays + 1;
  if (spanDays <= 7) {
    return _dailyBars(transactions, startD, endD);
  }
  if (spanDays <= 45) {
    return _weekBucketsInRange(transactions, startD, endD);
  }
  return _monthlyBarsCalendarSpan(transactions, startD, endD);
}

List<TrendBarSlice> _monthlyBarsYear(
  Iterable<Map<String, dynamic>> transactions,
  DateTime start,
  DateTime end,
) {
  const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
  final amounts = List<double>.filled(12, 0);
  for (final t in transactions) {
    final d = parseTxLocalDate(t);
    if (d == null || d.isBefore(start) || d.isAfter(end)) continue;
    if (d.year != start.year) continue;
    final amt = readAmount(t);
    if (!txIsExpense(t, amt)) continue;
    amounts[d.month - 1] += amt.abs();
  }
  final now = DateTime.now();
  final lastMonth = end.year == now.year ? now.month : 12;
  return [
    for (var m = 0; m < lastMonth; m++) TrendBarSlice(label: labels[m], amount: amounts[m]),
  ];
}

SubscriptionAnalytics buildSubscriptionBlock(
  List<Map<String, dynamic>> subscriptions,
  List<Map<String, dynamic>> transactions,
  DateTime periodStart,
  DateTime periodEnd,
) {
  var monthly = 0.0;
  var yearlySum = 0.0;
  var active = 0;
  var inactive = 0;
  DateTime? nextPay;
  String? nextName;

  for (final s in subscriptions) {
    final activeFlag = parseSubscriptionIsActive(s['is_active']);
    if (activeFlag) {
      active++;
    } else {
      inactive++;
    }
    final amt = subReadAmount(s['amount']);
    final cycle = (s['billing_cycle'] ?? 'monthly').toString().toLowerCase();
    if (activeFlag) {
      if (cycle == 'yearly') {
        monthly += amt / 12.0;
        yearlySum += amt;
      } else {
        monthly += amt;
        yearlySum += amt * 12.0;
      }
    }

    final raw = s['next_payment'] ?? s['next_payment_date'];
    final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
    if (d != null && activeFlag) {
      final local = d.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final todayD = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      if (!day.isBefore(todayD)) {
        if (nextPay == null || day.isBefore(nextPay)) {
          nextPay = day;
          nextName = (s['name'] ?? '').toString();
        }
      }
    }
  }

  final linked = sumSubscriptionLinkedExpenses(transactions, periodStart, periodEnd);

  return SubscriptionAnalytics(
    monthlyRecurringCost: monthly,
    yearlyCommittedCost: yearlySum,
    activeCount: active,
    inactiveCount: inactive,
    nextPayment: nextPay,
    nextPaymentSubscriptionName: nextName,
    subscriptionLinkedExpenseInPeriod: linked,
  );
}

GoalAnalytics buildGoalBlock(List<Map<String, dynamic>> goals) {
  if (goals.isEmpty) {
    return const GoalAnalytics(
      totalGoals: 0,
      totalSaved: 0,
      rows: [],
      nearestDeadline: null,
      nearestDeadlineTitle: null,
      showLowProgressDeadlineWarning: false,
    );
  }

  var saved = 0.0;
  final rows = <GoalProgressRow>[];
  DateTime? nearest;
  String? nearestTitle;
  var warn = false;
  final today = DateTime.now();
  final todayD = DateTime(today.year, today.month, today.day);

  for (final g in goals) {
    final id = g['id']?.toString() ?? '';
    final title = (g['title'] ?? 'Goal').toString();
    final target = subReadAmount(g['target_amount']);
    final current = subReadAmount(g['current_amount']);
    saved += current;
    final pct = target > 0 ? (current / target * 100).clamp(0.0, 999.0) : 0.0;
    DateTime? dl;
    final rawD = g['deadline'];
    if (rawD != null) {
      final p = DateTime.tryParse(rawD.toString());
      if (p != null) {
        final l = p.toLocal();
        dl = DateTime(l.year, l.month, l.day);
      }
    }
    rows.add(
      GoalProgressRow(
        id: id,
        title: title,
        targetAmount: target,
        currentAmount: current,
        progressPct: pct,
        deadline: dl,
      ),
    );
    if (dl != null && !dl.isBefore(todayD)) {
      if (nearest == null || dl.isBefore(nearest)) {
        nearest = dl;
        nearestTitle = title;
      }
      final daysLeft = dl.difference(todayD).inDays;
      if (daysLeft <= 14 && daysLeft >= 0 && pct < 30) {
        warn = true;
      }
    }
  }
  rows.sort((a, b) => b.progressPct.compareTo(a.progressPct));

  return GoalAnalytics(
    totalGoals: goals.length,
    totalSaved: saved,
    rows: rows,
    nearestDeadline: nearest,
    nearestDeadlineTitle: nearestTitle,
    showLowProgressDeadlineWarning: warn,
  );
}

List<SmartInsightItem> buildSmartInsights({
  required List<CategorySpendSlice> categories,
  required MonthComparison monthComparison,
  required double balance,
  required SubscriptionAnalytics subs,
  required GoalAnalytics goals,
}) {
  final out = <SmartInsightItem>[];

  if (categories.isNotEmpty) {
    final top = categories.first;
    out.add(
      SmartInsightItem(
        icon: Icons.pie_chart_outline_rounded,
        iconBackground: const Color(0xFFE3F2FD),
        iconColor: const Color(0xFF1565C0),
        title: 'Top spending category',
        body: '${top.name} leads your spending in this period.',
      ),
    );
  }

  if (monthComparison.thisMonthExpense > monthComparison.lastMonthExpense &&
      monthComparison.lastMonthExpense > 0) {
    out.add(
      SmartInsightItem(
        icon: Icons.warning_amber_rounded,
        iconBackground: const Color(0xFFFFEBEE),
        iconColor: const Color(0xFFC62828),
        title: 'Spending uptick',
        body: 'This month’s expenses are higher than last month. Consider reviewing discretionary categories.',
      ),
    );
  } else if (monthComparison.thisMonthExpense < monthComparison.lastMonthExpense &&
      monthComparison.thisMonthExpense > 0) {
    out.add(
      SmartInsightItem(
        icon: Icons.trending_down_rounded,
        iconBackground: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF2E7D32),
        title: 'Positive trend',
        body: 'You spent less this month than last month — nice work staying under last month’s pace.',
      ),
    );
  }

  if (balance >= 0 &&
      monthComparison.thisMonthExpense > 0 &&
      balance < monthComparison.thisMonthExpense) {
    out.add(
      SmartInsightItem(
        icon: Icons.account_balance_wallet_outlined,
        iconBackground: const Color(0xFFFFF3E0),
        iconColor: const Color(0xFFEF6C00),
        title: 'Low balance vs spending',
        body: 'Your balance is below this month’s expenses so far. Plan for upcoming bills or reduce spend.',
      ),
    );
  }

  if (monthComparison.thisMonthExpense > 0 &&
      subs.monthlyRecurringCost > monthComparison.thisMonthExpense * 0.35) {
    out.add(
      SmartInsightItem(
        icon: Icons.subscriptions_outlined,
        iconBackground: const Color(0xFFF3E5F5),
        iconColor: const Color(0xFF6A1B9A),
        title: 'Subscriptions footprint',
        body: 'Recurring subscriptions are a large share of monthly expenses. Audit inactive services.',
      ),
    );
  }

  if (goals.showLowProgressDeadlineWarning) {
    out.add(
      SmartInsightItem(
        icon: Icons.flag_outlined,
        iconBackground: const Color(0xFFFFEBEE),
        iconColor: const Color(0xFFC62828),
        title: 'Goal deadline',
        body: 'At least one goal has a nearby deadline with low progress — consider increasing contributions.',
      ),
    );
  }

  if (out.isEmpty) {
    out.add(
      SmartInsightItem(
        icon: Icons.lightbulb_outline_rounded,
        iconBackground: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF3F5F4A),
        title: 'Keep logging',
        body: 'Add income and expenses to unlock richer comparisons and alerts.',
      ),
    );
  }

  return out;
}

InsightsPayload buildInsightsPayload({
  required double balance,
  required String currency,
  required InsightsTimeRange range,
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> subscriptions,
  required List<Map<String, dynamic>> goals,
  required DateTime now,
}) {
  final (pStart, pEnd) = insightsRangeBounds(range, now);
  final period = sumIncomeExpense(transactions, pStart, pEnd);
  final income = period.$1;
  final expense = period.$2;
  final net = income - expense;
  final savingsRate = income > 1e-6 ? (net / income) * 100 : 0.0;

  final cats = buildCategorySlices(transactions, pStart, pEnd);
  final bars = buildTrendBars(range, transactions, pStart, pEnd);
  final monthCmp = buildMonthComparison(transactions, now);
  final subBlock = buildSubscriptionBlock(subscriptions, transactions, pStart, pEnd);
  final goalBlock = buildGoalBlock(goals);

  final insights = buildSmartInsights(
    categories: cats,
    monthComparison: monthCmp,
    balance: balance,
    subs: subBlock,
    goals: goalBlock,
  );

  return InsightsPayload(
    balance: balance,
    currency: currency,
    range: range,
    periodLabel: range.shortLabel,
    periodIncome: income,
    periodExpense: expense,
    periodNet: net,
    savingsRatePct: savingsRate,
    categorySlices: cats,
    trendBars: bars,
    monthComparison: monthCmp,
    subscriptionAnalytics: subBlock,
    goalAnalytics: goalBlock,
    smartInsights: insights,
    transactionCountInFetch: transactions.length,
  );
}

/// Snapshot for an arbitrary inclusive date range (custom Insights period or export). [range] is a UI placeholder.
InsightsPayload buildCustomPeriodPayload({
  required double balance,
  required String currency,
  required DateTime periodStart,
  required DateTime periodEnd,
  required String periodLabel,
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> subscriptions,
  required List<Map<String, dynamic>> goals,
  required DateTime now,
}) {
  final pStart = DateTime(periodStart.year, periodStart.month, periodStart.day);
  final pEnd = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
  final period = sumIncomeExpense(transactions, pStart, pEnd);
  final income = period.$1;
  final expense = period.$2;
  final net = income - expense;
  final savingsRate = income > 1e-6 ? (net / income) * 100 : 0.0;

  final cats = buildCategorySlices(transactions, pStart, pEnd);
  final bars = buildTrendBarsForCustomRange(transactions, pStart, pEnd);
  final monthCmp = buildMonthComparison(transactions, now);
  final subBlock = buildSubscriptionBlock(subscriptions, transactions, pStart, pEnd);
  final goalBlock = buildGoalBlock(goals);

  final insights = buildSmartInsights(
    categories: cats,
    monthComparison: monthCmp,
    balance: balance,
    subs: subBlock,
    goals: goalBlock,
  );

  return InsightsPayload(
    balance: balance,
    currency: currency,
    range: InsightsTimeRange.thisMonth,
    periodLabel: periodLabel,
    periodIncome: income,
    periodExpense: expense,
    periodNet: net,
    savingsRatePct: savingsRate,
    categorySlices: cats,
    trendBars: bars,
    monthComparison: monthCmp,
    subscriptionAnalytics: subBlock,
    goalAnalytics: goalBlock,
    smartInsights: insights,
    transactionCountInFetch: transactions.length,
  );
}

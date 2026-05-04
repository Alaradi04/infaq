import 'package:flutter/material.dart';

/// Time window for charts and period summary (balance is always live).
enum InsightsTimeRange {
  thisWeek,
  thisMonth,
  lastMonth,
  thisYear,
}

extension InsightsTimeRangeLabel on InsightsTimeRange {
  String get shortLabel {
    switch (this) {
      case InsightsTimeRange.thisWeek:
        return 'This week';
      case InsightsTimeRange.thisMonth:
        return 'This month';
      case InsightsTimeRange.lastMonth:
        return 'Last month';
      case InsightsTimeRange.thisYear:
        return 'This year';
    }
  }
}

/// Inclusive calendar bounds in local time (date-only semantics).
(DateTime start, DateTime end) insightsRangeBounds(InsightsTimeRange range, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  switch (range) {
    case InsightsTimeRange.thisWeek:
      final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
      final sunday = monday.add(const Duration(days: 6));
      return (monday, sunday.isAfter(today) ? today : sunday);
    case InsightsTimeRange.thisMonth:
      final start = DateTime(now.year, now.month, 1);
      final end = _lastDayOfMonth(now.year, now.month);
      final endClamped = end.isAfter(today) ? today : end;
      return (start, endClamped);
    case InsightsTimeRange.lastMonth:
      final firstThis = DateTime(now.year, now.month, 1);
      final lastPrev = firstThis.subtract(const Duration(days: 1));
      final start = DateTime(lastPrev.year, lastPrev.month, 1);
      final end = DateTime(lastPrev.year, lastPrev.month, lastPrev.day);
      return (start, end);
    case InsightsTimeRange.thisYear:
      final start = DateTime(now.year, 1, 1);
      return (start, today);
  }
}

DateTime _lastDayOfMonth(int y, int m) => DateTime(y, m + 1, 0);

(DateTime start, DateTime end) calendarMonthBounds(DateTime forMonth) {
  final start = DateTime(forMonth.year, forMonth.month, 1);
  final end = _lastDayOfMonth(forMonth.year, forMonth.month);
  final today = DateTime.now();
  final todayD = DateTime(today.year, today.month, today.day);
  if (forMonth.year == today.year && forMonth.month == today.month) {
    return (start, todayD);
  }
  return (start, end);
}

class CategorySpendSlice {
  const CategorySpendSlice({required this.name, required this.amount, required this.color});
  final String name;
  final double amount;
  final Color color;
}

class TrendBarSlice {
  const TrendBarSlice({required this.label, required this.amount});
  final String label;
  final double amount;
}

class MonthComparison {
  const MonthComparison({
    required this.thisMonthIncome,
    required this.thisMonthExpense,
    required this.thisMonthNet,
    required this.lastMonthIncome,
    required this.lastMonthExpense,
    required this.lastMonthNet,
  });

  final double thisMonthIncome;
  final double thisMonthExpense;
  final double thisMonthNet;
  final double lastMonthIncome;
  final double lastMonthExpense;
  final double lastMonthNet;

  double get incomeDiff => thisMonthIncome - lastMonthIncome;
  double get expenseDiff => thisMonthExpense - lastMonthExpense;
  double get netDiff => thisMonthNet - lastMonthNet;

  /// Percent change vs prior month; null if baseline ~0.
  double? get pctIncome => _pct(lastMonthIncome, thisMonthIncome);
  double? get pctExpense => _pct(lastMonthExpense, thisMonthExpense);
  double? get pctNet => _pct(lastMonthNet, thisMonthNet);

  static double? _pct(double baseline, double value) {
    if (baseline.abs() < 1e-6) return null;
    return ((value - baseline) / baseline.abs()) * 100;
  }
}

class SubscriptionAnalytics {
  const SubscriptionAnalytics({
    required this.monthlyRecurringCost,
    required this.yearlyCommittedCost,
    required this.activeCount,
    required this.inactiveCount,
    required this.nextPayment,
    required this.nextPaymentSubscriptionName,
    required this.subscriptionLinkedExpenseInPeriod,
  });

  final double monthlyRecurringCost;
  final double yearlyCommittedCost;
  final int activeCount;
  final int inactiveCount;
  final DateTime? nextPayment;
  final String? nextPaymentSubscriptionName;
  final double subscriptionLinkedExpenseInPeriod;
}

class GoalProgressRow {
  const GoalProgressRow({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.currentAmount,
    required this.progressPct,
    required this.deadline,
  });

  final String id;
  final String title;
  final double targetAmount;
  final double currentAmount;
  final double progressPct;
  final DateTime? deadline;
}

class GoalAnalytics {
  const GoalAnalytics({
    required this.totalGoals,
    required this.totalSaved,
    required this.rows,
    required this.nearestDeadline,
    required this.nearestDeadlineTitle,
    required this.showLowProgressDeadlineWarning,
  });

  final int totalGoals;
  final double totalSaved;
  final List<GoalProgressRow> rows;
  final DateTime? nearestDeadline;
  final String? nearestDeadlineTitle;
  final bool showLowProgressDeadlineWarning;
}

class SmartInsightItem {
  const SmartInsightItem({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String body;
}

class InsightsPayload {
  const InsightsPayload({
    required this.balance,
    required this.currency,
    required this.range,
    required this.periodLabel,
    required this.periodIncome,
    required this.periodExpense,
    required this.periodNet,
    required this.savingsRatePct,
    required this.categorySlices,
    required this.trendBars,
    required this.monthComparison,
    required this.subscriptionAnalytics,
    required this.goalAnalytics,
    required this.smartInsights,
    required this.transactionCountInFetch,
  });

  final double balance;
  final String currency;
  final InsightsTimeRange range;
  /// Human-readable period (export, subtitles). Usually matches [range.shortLabel] or a custom range.
  final String periodLabel;
  final double periodIncome;
  final double periodExpense;
  final double periodNet;
  final double savingsRatePct;
  final List<CategorySpendSlice> categorySlices;
  final List<TrendBarSlice> trendBars;
  final MonthComparison monthComparison;
  final SubscriptionAnalytics subscriptionAnalytics;
  final GoalAnalytics goalAnalytics;
  final List<SmartInsightItem> smartInsights;
  final int transactionCountInFetch;

  bool get hasAnyTransactions => transactionCountInFetch > 0;
}

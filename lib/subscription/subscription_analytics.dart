/// Helpers to attribute expenses to a subscription row and compare with category spend (e.g. food).
library;

double subReadAmount(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 0;
}

DateTime? subTxDate(Map<String, dynamic> r) {
  final raw = r['date'] ?? r['created_at'];
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString());
}

bool subIsExpense(Map<String, dynamic> data, double amount) {
  final catMap = data['categories'];
  String? catType;
  if (catMap is Map) catType = catMap['type']?.toString().toLowerCase();
  final legacyType = (data['type'] ?? data['transaction_type'] ?? '').toString().toLowerCase();
  return catType == 'expense' ||
      (catType == null &&
          (legacyType == 'expense' ||
              legacyType == 'debit' ||
              legacyType == 'out' ||
              (legacyType.isEmpty && amount < 0)));
}

/// Sums absolute expense amounts linked by [subscription_id] or description containing subscription [name].
double subscriptionAttributedExpenseAllTime(
  Map<String, dynamic> subscription,
  List<Map<String, dynamic>> transactions,
) {
  final sid = subscription['id']?.toString();
  final name = (subscription['name'] ?? '').toString().trim().toLowerCase();
  var sum = 0.0;
  for (final t in transactions) {
    final amount = subReadAmount(t['amount']);
    if (!subIsExpense(t, amount)) continue;
    final link = t['subscription_id']?.toString();
    if (sid != null && link != null && link == sid) {
      sum += amount.abs();
      continue;
    }
    if (name.isNotEmpty) {
      final desc = (t['description'] ?? '').toString().toLowerCase();
      if (desc.contains(name)) sum += amount.abs();
    }
  }
  return sum;
}

/// Same rules as [subscriptionAttributedExpenseAllTime] but only transactions in [month].
double subscriptionAttributedExpenseInMonth(
  Map<String, dynamic> subscription,
  List<Map<String, dynamic>> transactions,
  DateTime month,
) {
  final sid = subscription['id']?.toString();
  final name = (subscription['name'] ?? '').toString().trim().toLowerCase();
  var sum = 0.0;
  for (final t in transactions) {
    final d = subTxDate(t);
    if (d == null || d.year != month.year || d.month != month.month) continue;
    final amount = subReadAmount(t['amount']);
    if (!subIsExpense(t, amount)) continue;
    final link = t['subscription_id']?.toString();
    if (sid != null && link != null && link == sid) {
      sum += amount.abs();
      continue;
    }
    if (name.isNotEmpty) {
      final desc = (t['description'] ?? '').toString().toLowerCase();
      if (desc.contains(name)) sum += amount.abs();
    }
  }
  return sum;
}

/// Expense total for categories that look like food/groceries in a given calendar month.
double foodLikeExpenseInMonth(
  List<Map<String, dynamic>> transactions,
  DateTime month,
) {
  var sum = 0.0;
  for (final t in transactions) {
    final d = subTxDate(t);
    if (d == null || d.year != month.year || d.month != month.month) continue;
    final cat = t['categories'];
    final catName = cat is Map ? (cat['name'] ?? '').toString().toLowerCase() : '';
    final isFood = catName.contains('food') ||
        catName.contains('grocery') ||
        catName.contains('groceries') ||
        catName.contains('dining') ||
        catName.contains('restaurant');
    if (!isFood) continue;
    final amount = subReadAmount(t['amount']);
    if (subIsExpense(t, amount)) sum += amount.abs();
  }
  return sum;
}

bool parseSubscriptionIsActive(dynamic raw) {
  if (raw == null) return true;
  if (raw is bool) return raw;
  final s = raw.toString().toLowerCase();
  return s == 'true' || s == '1';
}

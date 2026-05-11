import 'package:flutter/foundation.dart';
import 'package:infaq/services/infaq_local_notifications_service.dart';
import 'package:infaq/services/local_notification_dedupe_store.dart';
import 'package:infaq/services/local_notification_toggle_store.dart';
import 'package:infaq/services/notification_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local notifications after a transaction is saved (automatic or manual).
///
/// All work is triggered from explicit save paths only — not from [build] or
/// opening settings.
class AutomaticTransactionLocalNotifications {
  AutomaticTransactionLocalNotifications._();

  static const _log = '[LocalNotif][Tx]';

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _fmtAmount(double amount) {
    if (amount.isNaN || amount.isInfinite) return '0';
    final a = amount.abs();
    if ((a * 100).round() / 100 == a.roundToDouble()) {
      return a.toStringAsFixed(a % 1 == 0 ? 0 : 2);
    }
    return a.toStringAsFixed(2);
  }

  static bool _isExpenseRowForBudget(Map<String, dynamic> data, double amount) {
    final catMap = data['categories'];
    String? catType;
    if (catMap is Map) {
      catType = catMap['type']?.toString().toLowerCase();
    }
    final legacyType = (data['type'] ?? data['transaction_type'] ?? '')
        .toString()
        .toLowerCase();
    return catType == 'expense' ||
        (catType == null &&
            (legacyType == 'expense' ||
                legacyType == 'debit' ||
                legacyType == 'out' ||
                (legacyType.isEmpty && amount < 0)));
  }

  static double _readAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  /// One query: [prevMonthStart] .. [currentMonthEnd] inclusive (date-only bounds).
  static Future<List<Map<String, dynamic>>> _fetchExpenseRowsForBudgetWindow(
    SupabaseClient client,
    String userId,
    DateTime prevMonthStart,
    DateTime currentMonthEnd,
  ) async {
    final startStr =
        '${prevMonthStart.year}-${prevMonthStart.month.toString().padLeft(2, '0')}-${prevMonthStart.day.toString().padLeft(2, '0')}';
    final endStr =
        '${currentMonthEnd.year}-${currentMonthEnd.month.toString().padLeft(2, '0')}-${currentMonthEnd.day.toString().padLeft(2, '0')}';
    try {
      dynamic res;
      try {
        res = await client
            .from('transactions')
            .select('amount, date, created_at, category_id, categories(type)')
            .eq('user_id', userId)
            .gte('date', startStr)
            .lte('date', endStr);
      } catch (_) {
        res = await client
            .from('transactions')
            .select('amount, date, created_at, category_id')
            .eq('user_id', userId)
            .gte('date', startStr)
            .lte('date', endStr);
      }
      final list = res as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e, st) {
      debugPrint('$_log fetch window $startStr..$endStr failed: $e\n$st');
      return [];
    }
  }

  static double _sumExpensesInMonth(
    List<Map<String, dynamic>> rows,
    int year,
    int month,
    String? categoryId,
  ) {
    var sum = 0.0;
    for (final r in rows) {
      final raw = r['date'] ?? r['created_at'];
      if (raw == null) continue;
      final d = DateTime.tryParse(raw.toString());
      if (d == null) continue;
      if (d.year != year || d.month != month) continue;
      final cid = r['category_id']?.toString();
      if (categoryId != null && cid != categoryId) continue;
      final amount = _readAmount(r['amount']);
      if (!_isExpenseRowForBudget(r, amount)) continue;
      sum += amount.abs();
    }
    return sum;
  }

  static Future<void> onAfterAutomaticTransactionSaved({
    required String userId,
    required String? transactionId,
    required String transactionType,
    required String merchant,
    required double amount,
    required String? categoryId,
    required String categoryName,
  }) {
    return _onAfterTransactionSaved(
      userId: userId,
      transactionId: transactionId,
      transactionType: transactionType,
      merchant: merchant,
      amount: amount,
      categoryId: categoryId,
      categoryName: categoryName,
      dedupePrefix: 'auto',
    );
  }

  static Future<void> onAfterManualTransactionSaved({
    required String userId,
    required String? transactionId,
    required String transactionType,
    required String merchant,
    required double amount,
    required String? categoryId,
    required String categoryName,
  }) {
    return _onAfterTransactionSaved(
      userId: userId,
      transactionId: transactionId,
      transactionType: transactionType,
      merchant: merchant,
      amount: amount,
      categoryId: categoryId,
      categoryName: categoryName,
      dedupePrefix: 'manual',
    );
  }

  static Future<void> _onAfterTransactionSaved({
    required String userId,
    required String? transactionId,
    required String transactionType,
    required String merchant,
    required double amount,
    required String? categoryId,
    required String categoryName,
    required String dedupePrefix,
  }) async {
    if (!NotificationPreferencesService.instance.shouldDeliverNotifications()) {
      debugPrint('$_log skip: master notifications disabled (cached prefs)');
      return;
    }

    final toggles = await LocalNotificationToggleStore.readAll();
    final isIncome = transactionType == 'income';

    if (isIncome) {
      if (!toggles.transaction) {
        debugPrint('$_log skip income: transaction toggle off');
        return;
      }
      if (transactionId == null || transactionId.isEmpty) {
        debugPrint('$_log skip income: missing transaction id');
        return;
      }
      await _maybeShowTransactionRecorded(
        toggles: toggles,
        userId: userId,
        transactionId: transactionId,
        isIncome: true,
        merchant: merchant,
        amount: amount,
        categoryName: categoryName,
        dedupePrefix: dedupePrefix,
      );
      return;
    }

    // Expense: optional transaction toast; budget/category only for expense.
    final wantTx =
        toggles.transaction &&
        transactionId != null &&
        transactionId.isNotEmpty;
    final wantBudget = toggles.budget;
    final cid = categoryId?.trim();
    final wantCategory = toggles.category && cid != null && cid.isNotEmpty;

    if (!wantTx && !wantBudget && !wantCategory) {
      debugPrint('$_log skip expense: all relevant toggles off or no category');
      return;
    }

    final needUserRow = wantTx || wantBudget;
    String currency = '';
    double monthlyBudget = 0;
    if (needUserRow) {
      try {
        final row = await Supabase.instance.client
            .from('users')
            .select('currency, Balance')
            .eq('id', userId)
            .maybeSingle();
        if (row != null) {
          final m = Map<String, dynamic>.from(row);
          currency = (m['currency'] ?? '').toString().toUpperCase().trim();
          monthlyBudget = _readAmount(m['Balance']);
        }
      } catch (e, st) {
        debugPrint('$_log user row fetch failed: $e\n$st');
      }
    }

    if (wantTx) {
      await _maybeShowTransactionRecorded(
        toggles: toggles,
        userId: userId,
        transactionId: transactionId,
        isIncome: false,
        merchant: merchant,
        amount: amount,
        categoryName: categoryName,
        dedupePrefix: dedupePrefix,
        currencyPrefix: currency.isEmpty ? '' : '$currency ',
      );
    }

    if (!wantBudget && !wantCategory) {
      return;
    }

    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final monthEnd = DateTime(y, m + 1, 0);
    final prevMonth = m == 1 ? 12 : m - 1;
    final prevYear = m == 1 ? y - 1 : y;
    final prevStart = DateTime(prevYear, prevMonth, 1);

    List<Map<String, dynamic>>? rowsWindow;
    if (wantBudget && monthlyBudget > 0 || wantCategory) {
      rowsWindow = await _fetchExpenseRowsForBudgetWindow(
        Supabase.instance.client,
        userId,
        prevStart,
        monthEnd,
      );
    }

    if (wantBudget && monthlyBudget > 0 && rowsWindow != null) {
      final spent = _sumExpensesInMonth(rowsWindow, y, m, null);
      final ratio = spent / monthlyBudget;

      if (ratio >= 1.0) {
        final key = 'budget_100:${_monthKey(now)}';
        await _showDeduped(
          dedupeKey: key,
          title: 'Budget exceeded',
          body: 'You went over your monthly budget.',
        );
      } else if (ratio >= 0.8) {
        final key = 'budget_80:${_monthKey(now)}';
        await _showDeduped(
          dedupeKey: key,
          title: 'Budget almost reached',
          body: 'You’ve used 80% of your monthly budget.',
        );
      }
    }

    if (wantCategory && rowsWindow != null) {
      final catId = cid;
      final thisSpend = _sumExpensesInMonth(rowsWindow, y, m, catId);
      final prevSpend =
          _sumExpensesInMonth(rowsWindow, prevYear, prevMonth, catId);

      final spike = prevSpend <= 0
          ? thisSpend >= 50
          : thisSpend > prevSpend * 1.35 && thisSpend >= prevSpend + 15;

      if (spike) {
        final key = 'category_spike:$catId:${_monthKey(now)}';
        final label =
            categoryName.trim().isEmpty ? 'This category' : categoryName.trim();
        await _showDeduped(
          dedupeKey: key,
          title: '$label spending is high',
          body: 'You’re spending more than usual on $label this month.',
        );
      }
    }
  }

  static Future<void> _maybeShowTransactionRecorded({
    required LocalNotificationToggles toggles,
    required String userId,
    required String? transactionId,
    required bool isIncome,
    required String merchant,
    required double amount,
    required String categoryName,
    required String dedupePrefix,
    String currencyPrefix = '',
  }) async {
    if (!toggles.transaction) return;
    final id = transactionId;
    if (id == null || id.isEmpty) return;

    if (currencyPrefix.isEmpty && isIncome) {
      try {
        final row = await Supabase.instance.client
            .from('users')
            .select('currency')
            .eq('id', userId)
            .maybeSingle();
        if (row != null) {
          final c = (row['currency'] ?? '').toString().toUpperCase().trim();
          currencyPrefix = c.isEmpty ? '' : '$c ';
        }
      } catch (e, st) {
        debugPrint('$_log currency fetch failed: $e\n$st');
      }
    }

    final dedupeKey = isIncome
        ? '${dedupePrefix}_income_recorded:$id'
        : '${dedupePrefix}_expense_recorded:$id';
    if (!await LocalNotificationDedupeStore.consumeIfNew(dedupeKey)) {
      debugPrint('$_log skip tx toast: already sent ($dedupeKey)');
      return;
    }

    final svc = InfaqLocalNotificationsService.instance;
    final nid = InfaqLocalNotificationsService.notificationIdFor(dedupeKey);
    bool shown;
    if (isIncome) {
      shown = await svc.showImmediate(
        notificationId: nid,
        title: 'Income recorded',
        body: '$currencyPrefix${_fmtAmount(amount)} income was saved.',
      );
    } else {
      shown = await svc.showImmediate(
        notificationId: nid,
        title: 'Expense recorded',
        body:
            '$merchant expense of $currencyPrefix${_fmtAmount(amount)} was saved.',
      );
    }
    if (!shown) {
      await LocalNotificationDedupeStore.clearKey(dedupeKey);
      debugPrint('$_log reverted dedupe (show failed): $dedupeKey');
    }
  }

  static Future<void> _showDeduped({
    required String dedupeKey,
    required String title,
    required String body,
  }) async {
    if (!await LocalNotificationDedupeStore.consumeIfNew(dedupeKey)) {
      return;
    }
    final ok = await InfaqLocalNotificationsService.instance.showImmediate(
      notificationId: InfaqLocalNotificationsService.notificationIdFor(dedupeKey),
      title: title,
      body: body,
    );
    if (!ok) {
      await LocalNotificationDedupeStore.clearKey(dedupeKey);
    }
  }
}

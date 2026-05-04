import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/analytics/insights_engine.dart';
import 'package:infaq/analytics/insights_models.dart';

class InsightsService {
  InsightsService(this._client);

  final SupabaseClient _client;

  /// Include prior calendar year so January still has “last month” (December) data.
  static DateTime _fetchStartWindow(DateTime now) => DateTime(now.year - 1, 1, 1);

  Future<InsightsPayload> load({
    required String userId,
    required InsightsTimeRange range,
  }) async {
    final now = DateTime.now();
    final startWin = _fetchStartWindow(now);
    final endWin = DateTime(now.year, now.month, now.day);

    final userRow = await _client
        .from('users')
        .select('Balance, currency')
        .eq('id', userId)
        .maybeSingle();

    final balance = _readBalance(userRow?['Balance']);
    final currency = (userRow?['currency'] as String?)?.trim().isNotEmpty == true
        ? (userRow!['currency'] as String).trim()
        : 'BHD';

    List<Map<String, dynamic>> transactions;
    try {
      final res = await _client
          .from('transactions')
          .select(
            'id, amount, date, created_at, subscription_id, description, category_id, categories(name, type)',
          )
          .eq('user_id', userId)
          .gte('date', _isoDate(startWin))
          .lte('date', _isoDate(endWin))
          .order('date', ascending: false)
          .limit(8000);
      transactions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      final res = await _client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(8000);
      transactions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    List<Map<String, dynamic>> subscriptions;
    try {
      final res = await _client.from('subscriptions').select().eq('user_id', userId);
      subscriptions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      subscriptions = [];
    }

    List<Map<String, dynamic>> goals;
    try {
      final res = await _client
          .from('goals')
          .select('id, title, target_amount, current_amount, deadline, created_at')
          .eq('created_by', userId);
      goals = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      goals = [];
    }

    return buildInsightsPayload(
      balance: balance,
      currency: currency,
      range: range,
      transactions: transactions,
      subscriptions: subscriptions,
      goals: goals,
      now: now,
    );
  }

  /// Loads aggregates for [periodStart]–[periodEnd] (inclusive dates) for CSV/PDF export.
  Future<InsightsPayload> loadForExportPeriod({
    required String userId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String periodLabel,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exportStart = DateTime(periodStart.year, periodStart.month, periodStart.day);
    var exportEnd = DateTime(periodEnd.year, periodEnd.month, periodEnd.day);
    if (exportEnd.isAfter(today)) exportEnd = today;
    if (exportStart.isAfter(exportEnd)) {
      exportEnd = exportStart;
    }

    final defaultWinStart = DateTime(now.year - 1, 1, 1);
    final fetchStart = exportStart.isBefore(defaultWinStart) ? DateTime(exportStart.year, 1, 1) : defaultWinStart;

    final userRow = await _client
        .from('users')
        .select('Balance, currency')
        .eq('id', userId)
        .maybeSingle();

    final balance = _readBalance(userRow?['Balance']);
    final currency = (userRow?['currency'] as String?)?.trim().isNotEmpty == true
        ? (userRow!['currency'] as String).trim()
        : 'BHD';

    List<Map<String, dynamic>> transactions;
    try {
      final res = await _client
          .from('transactions')
          .select(
            'id, amount, date, created_at, subscription_id, description, category_id, categories(name, type)',
          )
          .eq('user_id', userId)
          .gte('date', _isoDate(fetchStart))
          .lte('date', _isoDate(today))
          .order('date', ascending: false)
          .limit(15000);
      transactions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      final res = await _client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(15000);
      transactions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    List<Map<String, dynamic>> subscriptions;
    try {
      final res = await _client.from('subscriptions').select().eq('user_id', userId);
      subscriptions = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      subscriptions = [];
    }

    List<Map<String, dynamic>> goals;
    try {
      final res = await _client
          .from('goals')
          .select('id, title, target_amount, current_amount, deadline, created_at')
          .eq('created_by', userId);
      goals = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      goals = [];
    }

    return buildCustomPeriodPayload(
      balance: balance,
      currency: currency,
      periodStart: exportStart,
      periodEnd: exportEnd,
      periodLabel: periodLabel,
      transactions: transactions,
      subscriptions: subscriptions,
      goals: goals,
      now: now,
    );
  }

  double _readBalance(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

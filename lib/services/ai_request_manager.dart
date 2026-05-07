import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/services/ai_usage_logger.dart';

enum AiDailyBucket { insights, categorize, manualRecategorize, leaf }

enum AiCategorizeCallKind { automatic, debouncedSuggestion, manualRecategorize }

/// Thrown when a call would exceed the per-day AI budget (leaf classification).
class AiQuotaExceededException implements Exception {
  AiQuotaExceededException(this.bucket);
  final AiDailyBucket bucket;
  @override
  String toString() => 'AiQuotaExceededException($bucket)';
}

/// Central cache, deduplication, daily caps, and fingerprints for Edge Function calls.
class AiRequestManager {
  AiRequestManager._();
  static final AiRequestManager instance = AiRequestManager._();

  static const int maxInsightsPerDay = 3;
  static const int maxCategorizePerDay = 20;
  static const int maxManualRecategorizePerDay = 10;
  static const int maxLeafPerDay = 25;

  static const Duration insightsTtl = Duration(hours: 24);

  final Map<String, _MemCacheEntry> _memory = {};
  final Map<String, Future<dynamic>> _inflight = {};

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, int>> _readDaily(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('infaq_ai_daily_v1_${userId}_$_todayKey()');
      if (raw == null || raw.isEmpty) return {};
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _bumpDaily(String userId, AiDailyBucket bucket) async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = 'infaq_ai_daily_v1_${userId}_$_todayKey()';
      final cur = await _readDaily(userId);
      final name = bucket.name;
      cur[name] = (cur[name] ?? 0) + 1;
      await p.setString(key, jsonEncode(cur));
    } catch (_) {}
  }

  Future<int> _dailyCount(String userId, AiDailyBucket bucket) async {
    final cur = await _readDaily(userId);
    return cur[bucket.name] ?? 0;
  }

  static String stableHash(String input) {
    var h = 5381;
    for (final c in input.codeUnits) {
      h = ((h << 5) + h) + c;
    }
    return (h & 0x7fffffff).toRadixString(16);
  }

  /// Compact fingerprint: recent transactions + goals + subscriptions.
  Future<String> buildFinancialFingerprint(String userId) async {
    final client = Supabase.instance.client;
    final buf = StringBuffer('fp|$userId');
    try {
      final txs = await client
          .from('transactions')
          .select('id, amount, created_at, category_id')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      final list = txs as List<dynamic>;
      buf.write('|tx:${list.length}');
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        buf.write(
          '|${m['id']}:${m['amount']}:${m['created_at']}:${m['category_id']}',
        );
      }
    } catch (_) {
      buf.write('|tx_err');
    }
    try {
      final g = await client
          .from('goals')
          .select('id, created_at')
          .eq('created_by', userId)
          .order('created_at', ascending: false)
          .limit(25);
      final list = g as List<dynamic>;
      buf.write('|g:${list.length}');
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        buf.write('|${m['id']}:${m['created_at']}');
      }
    } catch (_) {
      buf.write('|g_err');
    }
    try {
      final s = await client
          .from('subscriptions')
          .select('id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(25);
      final list = s as List<dynamic>;
      buf.write('|s:${list.length}');
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        buf.write('|${m['id']}:${m['created_at']}');
      }
    } catch (_) {
      buf.write('|s_err');
    }
    return stableHash(buf.toString());
  }

  Future<List<Map<String, dynamic>>?> _readHomeInsightsDisk(
    String userId,
    String fingerprint,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('infaq_ai_insight_home_v1_$userId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['fp']?.toString() != fingerprint) return null;
      final at = DateTime.tryParse(m['at']?.toString() ?? '');
      if (at == null) return null;
      if (DateTime.now().difference(at) > insightsTtl) return null;
      final cards = m['cards'];
      if (cards is! List) return null;
      return cards
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeHomeInsightsDisk(
    String userId,
    String fingerprint,
    List<Map<String, dynamic>> cards,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'infaq_ai_insight_home_v1_$userId',
        jsonEncode({
          'fp': fingerprint,
          'at': DateTime.now().toIso8601String(),
          'cards': cards,
        }),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>?> _readDetailedDisk(
    String userId,
    String period,
    String fingerprint,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(
        'infaq_ai_insight_det_v1_${userId}_$period',
      );
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['fp']?.toString() != fingerprint) return null;
      final at = DateTime.tryParse(m['at']?.toString() ?? '');
      if (at == null) return null;
      if (DateTime.now().difference(at) > insightsTtl) return null;
      final insights = m['insights'];
      if (insights is! List) return null;
      return insights
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDetailedDisk(
    String userId,
    String period,
    String fingerprint,
    List<Map<String, dynamic>> insights,
  ) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        'infaq_ai_insight_det_v1_${userId}_$period',
        jsonEncode({
          'fp': fingerprint,
          'at': DateTime.now().toIso8601String(),
          'insights': insights,
        }),
      );
    } catch (_) {}
  }

  String _merchantKey(String transactionName) {
    final t = transactionName.toLowerCase().trim();
    if (t.isEmpty) return '';
    final parts = t.split(RegExp(r'\s+'));
    return parts.take(5).join(' ');
  }

  Future<Map<String, dynamic>?> _readMerchantCategory(
    String userId,
    String merchantKey,
  ) async {
    if (merchantKey.isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('infaq_ai_merchant_cat_v1_$userId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final v = m[merchantKey];
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return null;
  }

  Future<void> _writeMerchantCategory(
    String userId,
    String merchantKey,
    Map<String, dynamic> categorization,
  ) async {
    if (merchantKey.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final key = 'infaq_ai_merchant_cat_v1_$userId';
      final raw = p.getString(key);
      final map = <String, dynamic>{};
      if (raw != null) {
        try {
          map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
        } catch (_) {}
      }
      map[merchantKey] = categorization;
      if (map.length > 200) {
        final keys = map.keys.toList()..sort();
        for (var i = 0; i < keys.length - 200; i++) {
          map.remove(keys[i]);
        }
      }
      await p.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> runHomeInsights({
    required SupabaseClient client,
    required String userId,
    required String reason,
    bool forceRefresh = false,
    required Future<List<Map<String, dynamic>>> Function() invoke,
  }) async {
    final fp = await buildFinancialFingerprint(userId);
    final memKey = 'home|$userId|$fp';

    if (!forceRefresh) {
      final mem = _memory[memKey];
      if (mem != null &&
          mem.fingerprint == fp &&
          DateTime.now().difference(mem.at) <= insightsTtl) {
        AiUsageLogger.instance.logCacheHit(
          feature: 'generate-home-insights',
          userId: userId,
          reason: '$reason|memory',
          inputHash: fp,
        );
        return List<Map<String, dynamic>>.from(mem.value as List);
      }
      final disk = await _readHomeInsightsDisk(userId, fp);
      if (disk != null) {
        _memory[memKey] = _MemCacheEntry(at: DateTime.now(), fingerprint: fp, value: disk);
        AiUsageLogger.instance.logCacheHit(
          feature: 'generate-home-insights',
          userId: userId,
          reason: '$reason|disk',
          inputHash: fp,
        );
        return disk;
      }
    }

    if (_inflight[memKey] != null) {
      AiUsageLogger.instance.logSkippedInFlight(
        feature: 'generate-home-insights',
        userId: userId,
        inputHash: fp,
      );
      return await _inflight[memKey]! as List<Map<String, dynamic>>;
    }

    final under = await _dailyCount(userId, AiDailyBucket.insights) < maxInsightsPerDay;
    if (!under && !forceRefresh) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'generate-home-insights',
        userId: userId,
        reason: reason,
        inputHash: fp,
      );
      final stale = await _readHomeInsightsDisk(userId, fp);
      if (stale != null) return stale;
      final any = await _readAnyHomeStale(userId);
      if (any != null) return any;
      return [];
    }

    if (!under && forceRefresh) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'generate-home-insights',
        userId: userId,
        reason: '$reason|forceRefresh_blocked',
        inputHash: fp,
      );
      final stale = await _readHomeInsightsDisk(userId, fp);
      if (stale != null) return stale;
      return [];
    }

    final fut = () async {
      try {
        final cards = await invoke();
        await _bumpDaily(userId, AiDailyBucket.insights);
        AiUsageLogger.instance.logApiInvoke(
          feature: 'generate-home-insights',
          userId: userId,
          reason: reason,
          inputHash: fp,
          inputSizeEstimate: AiUsageLogger.jsonEstimate(cards),
        );
        _memory[memKey] = _MemCacheEntry(
          at: DateTime.now(),
          fingerprint: fp,
          value: cards,
        );
        await _writeHomeInsightsDisk(userId, fp, cards);
        return cards;
      } finally {
        _inflight.remove(memKey);
      }
    }();

    _inflight[memKey] = fut;
    return await fut;
  }

  Future<List<Map<String, dynamic>>?> _readAnyHomeStale(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('infaq_ai_insight_home_v1_$userId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final cards = m['cards'];
      if (cards is! List) return null;
      return cards
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> runDetailedInsights({
    required String userId,
    required String period,
    required String reason,
    bool forceRefresh = false,
    required Future<List<Map<String, dynamic>>> Function() invoke,
  }) async {
    final fp = await buildFinancialFingerprint(userId);
    final memKey = 'det|$userId|$period|$fp';

    if (!forceRefresh) {
      final mem = _memory[memKey];
      if (mem != null &&
          mem.fingerprint == fp &&
          DateTime.now().difference(mem.at) <= insightsTtl) {
        AiUsageLogger.instance.logCacheHit(
          feature: 'generate-detailed-insights',
          userId: userId,
          reason: '$reason|memory|$period',
          inputHash: fp,
        );
        return List<Map<String, dynamic>>.from(mem.value as List);
      }
      final disk = await _readDetailedDisk(userId, period, fp);
      if (disk != null) {
        _memory[memKey] = _MemCacheEntry(at: DateTime.now(), fingerprint: fp, value: disk);
        AiUsageLogger.instance.logCacheHit(
          feature: 'generate-detailed-insights',
          userId: userId,
          reason: '$reason|disk|$period',
          inputHash: fp,
        );
        return disk;
      }
    }

    if (_inflight[memKey] != null) {
      AiUsageLogger.instance.logSkippedInFlight(
        feature: 'generate-detailed-insights',
        userId: userId,
        inputHash: fp,
      );
      return await _inflight[memKey]! as List<Map<String, dynamic>>;
    }

    final under = await _dailyCount(userId, AiDailyBucket.insights) < maxInsightsPerDay;
    if (!under && !forceRefresh) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'generate-detailed-insights',
        userId: userId,
        reason: reason,
        inputHash: fp,
      );
      final stale = await _readDetailedDisk(userId, period, fp);
      if (stale != null) return stale;
      return [];
    }
    if (!under && forceRefresh) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'generate-detailed-insights',
        userId: userId,
        reason: '$reason|forceRefresh_blocked',
        inputHash: fp,
      );
      final stale = await _readDetailedDisk(userId, period, fp);
      if (stale != null) return stale;
      return [];
    }

    final fut = () async {
      try {
        final insights = await invoke();
        await _bumpDaily(userId, AiDailyBucket.insights);
        AiUsageLogger.instance.logApiInvoke(
          feature: 'generate-detailed-insights',
          userId: userId,
          reason: '$reason|$period',
          inputHash: fp,
          inputSizeEstimate: AiUsageLogger.jsonEstimate(insights),
        );
        _memory[memKey] = _MemCacheEntry(
          at: DateTime.now(),
          fingerprint: fp,
          value: insights,
        );
        await _writeDetailedDisk(userId, period, fp, insights);
        return insights;
      } finally {
        _inflight.remove(memKey);
      }
    }();

    _inflight[memKey] = fut;
    return await fut;
  }

  Future<Map<String, dynamic>> runCategorize({
    required SupabaseClient client,
    required String userId,
    required String transactionName,
    required double amount,
    required String transactionType,
    String? description,
    required List<String> availableCategories,
    required AiCategorizeCallKind kind,
    required String reason,
    required Future<Map<String, dynamic>> Function() invoke,
  }) async {
    final mKey = _merchantKey(transactionName);
    final catSig = stableHash(availableCategories.join('\n'));
    final inputHash = stableHash(
      '$transactionName|$amount|$transactionType|$catSig|${description ?? ''}',
    );

    final cachedMerchant = await _readMerchantCategory(userId, mKey);
    if (cachedMerchant != null && mKey.isNotEmpty) {
      AiUsageLogger.instance.logCacheHit(
        feature: 'categorize-transaction',
        userId: userId,
        reason: '$reason|merchant_map',
        inputHash: inputHash,
      );
      return Map<String, dynamic>.from(cachedMerchant);
    }

    final memKey = 'cat|$userId|$inputHash';
    final mem = _memory[memKey];
    if (mem != null) {
      AiUsageLogger.instance.logCacheHit(
        feature: 'categorize-transaction',
        userId: userId,
        reason: '$reason|memory',
        inputHash: inputHash,
      );
      return Map<String, dynamic>.from(mem.value as Map);
    }

    if (_inflight[memKey] != null) {
      AiUsageLogger.instance.logSkippedInFlight(
        feature: 'categorize-transaction',
        userId: userId,
        inputHash: inputHash,
      );
      return await _inflight[memKey]! as Map<String, dynamic>;
    }

    final bucket = kind == AiCategorizeCallKind.manualRecategorize
        ? AiDailyBucket.manualRecategorize
        : AiDailyBucket.categorize;
    final max = kind == AiCategorizeCallKind.manualRecategorize
        ? maxManualRecategorizePerDay
        : maxCategorizePerDay;
    final under = await _dailyCount(userId, bucket) < max;
    if (!under) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'categorize-transaction',
        userId: userId,
        reason: reason,
        inputHash: inputHash,
      );
      final fallback = _localCategorizeFallback(transactionType, availableCategories);
      return fallback;
    }

    final fut = () async {
      try {
        final result = await invoke();
        await _bumpDaily(userId, bucket);
        AiUsageLogger.instance.logApiInvoke(
          feature: 'categorize-transaction',
          userId: userId,
          reason: '$reason|${kind.name}',
          inputHash: inputHash,
          inputSizeEstimate: transactionName.length + availableCategories.join().length,
        );
        _memory[memKey] = _MemCacheEntry(
          at: DateTime.now(),
          fingerprint: inputHash,
          value: result,
        );
        final suggested =
            (result['suggested_category'] ?? '').toString().trim();
        if (mKey.isNotEmpty && suggested.isNotEmpty) {
          await _writeMerchantCategory(userId, mKey, result);
        }
        return result;
      } finally {
        _inflight.remove(memKey);
      }
    }();

    _inflight[memKey] = fut;
    return await fut;
  }

  Map<String, dynamic> _localCategorizeFallback(
    String transactionType,
    List<String> availableCategories,
  ) {
    final isInc = transactionType.toLowerCase() == 'income';
    final want = isInc ? 'other income' : 'other expense';
    String? pick;
    for (final c in availableCategories) {
      if (c.toLowerCase() == want) {
        pick = c;
        break;
      }
    }
    pick ??= availableCategories.isNotEmpty ? availableCategories.first : 'Other';
    return {
      'suggested_category': pick,
      'confidence': 'local_fallback',
      'leaf_color': null,
    };
  }

  Future<Map<String, dynamic>> runLeafClassify({
    required String userId,
    required String transactionName,
    required String category,
    required String transactionType,
    required String reason,
    required Future<Map<String, dynamic>> Function() invoke,
  }) async {
    final inputHash = stableHash('$transactionName|$category|$transactionType');
    final memKey = 'leaf|$userId|$inputHash';

    final mem = _memory[memKey];
    if (mem != null) {
      AiUsageLogger.instance.logCacheHit(
        feature: 'classify-leaf-impact',
        userId: userId,
        reason: '$reason|memory',
        inputHash: inputHash,
      );
      return Map<String, dynamic>.from(mem.value as Map);
    }

    if (_inflight[memKey] != null) {
      AiUsageLogger.instance.logSkippedInFlight(
        feature: 'classify-leaf-impact',
        userId: userId,
        inputHash: inputHash,
      );
      return await _inflight[memKey]! as Map<String, dynamic>;
    }

    final under =
        await _dailyCount(userId, AiDailyBucket.leaf) < maxLeafPerDay;
    if (!under) {
      AiUsageLogger.instance.logSkippedQuota(
        feature: 'classify-leaf-impact',
        userId: userId,
        reason: reason,
        inputHash: inputHash,
      );
      throw AiQuotaExceededException(AiDailyBucket.leaf);
    }

    final fut = () async {
      try {
        final result = await invoke();
        await _bumpDaily(userId, AiDailyBucket.leaf);
        AiUsageLogger.instance.logApiInvoke(
          feature: 'classify-leaf-impact',
          userId: userId,
          reason: reason,
          inputHash: inputHash,
          inputSizeEstimate:
              transactionName.length + category.length + transactionType.length,
        );
        _memory[memKey] = _MemCacheEntry(
          at: DateTime.now(),
          fingerprint: inputHash,
          value: result,
        );
        return result;
      } finally {
        _inflight.remove(memKey);
      }
    }();

    _inflight[memKey] = fut;
    return await fut;
  }

  /// Debug: today's counts + fingerprint sample.
  Future<Map<String, dynamic>> debugSnapshot(String userId) async {
    final daily = await _readDaily(userId);
    final fp = await buildFinancialFingerprint(userId);
    final day = _todayKey();
    return {
      'fingerprint': fp,
      'day': day,
      'daily_counts': daily,
      'limits': {
        'insights': maxInsightsPerDay,
        'categorize': maxCategorizePerDay,
        'manualRecategorize': maxManualRecategorizePerDay,
        'leaf': maxLeafPerDay,
      },
    };
  }
}

class _MemCacheEntry {
  _MemCacheEntry({
    required this.at,
    required this.fingerprint,
    required this.value,
  });
  final DateTime at;
  final String fingerprint;
  final Object value;
}

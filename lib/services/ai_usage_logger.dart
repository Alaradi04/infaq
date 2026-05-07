import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Debug / telemetry for AI (Edge Function) usage — not sent to servers.
class AiUsageLogger {
  AiUsageLogger._();
  static final AiUsageLogger instance = AiUsageLogger._();

  static const _prefsKeyPrefix = 'infaq_ai_usage_stats_v1_';

  int cacheHitsSession = 0;
  int cacheMissesSession = 0;
  int apiCallsSession = 0;
  int skippedQuotaSession = 0;
  int skippedDuplicateInFlightSession = 0;

  String? lastFeature;
  DateTime? lastCallAt;
  String? lastReason;
  bool? lastFromCache;

  void logApiInvoke({
    required String feature,
    required String userId,
    required String reason,
    required String inputHash,
    int? inputSizeEstimate,
  }) {
    apiCallsSession++;
    cacheMissesSession++;
    lastFeature = feature;
    lastCallAt = DateTime.now();
    lastReason = reason;
    lastFromCache = false;
    final ts = DateTime.now().toIso8601String();
    debugPrint(
      '[AiUsage] feature=$feature user=${userId.substring(0, userId.length.clamp(0, 8))}… '
      'source=API reason=$reason ts=$ts '
      'inputHash=$inputHash inputEst=${inputSizeEstimate ?? '-'}',
    );
    unawaited(_persistBump('apiCalls'));
  }

  void logCacheHit({
    required String feature,
    required String userId,
    required String reason,
    required String inputHash,
  }) {
    cacheHitsSession++;
    lastFeature = feature;
    lastCallAt = DateTime.now();
    lastReason = reason;
    lastFromCache = true;
    final ts = DateTime.now().toIso8601String();
    debugPrint(
      '[AiUsage] feature=$feature user=${userId.substring(0, userId.length.clamp(0, 8))}… '
      'source=CACHE_HIT reason=$reason ts=$ts inputHash=$inputHash',
    );
    unawaited(_persistBump('cacheHits'));
  }

  void logSkippedQuota({
    required String feature,
    required String userId,
    required String reason,
    required String inputHash,
  }) {
    skippedQuotaSession++;
    debugPrint(
      '[AiUsage] AI skipped: daily limit reached feature=$feature '
      'user=${userId.substring(0, userId.length.clamp(0, 8))}… reason=$reason hash=$inputHash',
    );
    unawaited(_persistBump('skippedQuota'));
  }

  void logSkippedInFlight({
    required String feature,
    required String userId,
    required String inputHash,
  }) {
    skippedDuplicateInFlightSession++;
    debugPrint(
      '[AiUsage] joined in-flight request feature=$feature hash=$inputHash',
    );
  }

  Future<void> _persistBump(String field) async {
    try {
      final p = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$field';
      final n = (p.getInt(key) ?? 0) + 1;
      await p.setInt(key, n);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> loadPersistedCounters() async {
    try {
      final p = await SharedPreferences.getInstance();
      return {
        'cacheHits': p.getInt('${_prefsKeyPrefix}cacheHits') ?? 0,
        'apiCalls': p.getInt('${_prefsKeyPrefix}apiCalls') ?? 0,
        'skippedQuota': p.getInt('${_prefsKeyPrefix}skippedQuota') ?? 0,
      };
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> sessionSummary(String userId) {
    return {
      'userId': userId,
      'session_cache_hits': cacheHitsSession,
      'session_cache_misses': cacheMissesSession,
      'session_api_calls': apiCallsSession,
      'session_skipped_quota': skippedQuotaSession,
      'session_joined_inflight': skippedDuplicateInFlightSession,
      'last_feature': lastFeature,
      'last_call_at': lastCallAt?.toIso8601String(),
      'last_reason': lastReason,
      'last_from_cache': lastFromCache,
    };
  }

  /// Best-effort JSON size estimate for logging.
  static int jsonEstimate(Object? o) {
    try {
      return jsonEncode(o).length;
    } catch (_) {
      return 0;
    }
  }
}

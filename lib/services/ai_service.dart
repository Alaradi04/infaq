import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/services/ai_request_manager.dart';

export 'package:infaq/services/ai_request_manager.dart'
    show AiCategorizeCallKind, AiQuotaExceededException;

class AiService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Calls Edge Function `generate-home-insights` (Gemini-backed). No API keys in the client.
  Future<List<Map<String, dynamic>>> generateHomeInsights({
    bool forceRefresh = false,
    String reason = 'home_dashboard',
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    return AiRequestManager.instance.runHomeInsights(
      client: _client,
      userId: user.id,
      reason: reason,
      forceRefresh: forceRefresh,
      invoke: () async {
        final response = await _client.functions.invoke(
          'generate-home-insights',
          body: {'user_id': user.id},
        );

        if (kDebugMode) {
          debugPrint(
            'generate-home-insights status=${response.status} data=${response.data}',
          );
        }

        final raw = response.data;
        if (raw is! Map) return [];
        final data = raw is Map<String, dynamic>
            ? raw
            : Map<String, dynamic>.from(raw);
        final cards = data['cards'];
        if (cards is! List) return [];

        final out = <Map<String, dynamic>>[];
        for (final e in cards) {
          if (e is Map<String, dynamic>) {
            out.add(e);
          } else if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
        return out;
      },
    );
  }

  Future<Map<String, dynamic>> categorizeTransaction({
    required String transactionName,
    required double amount,
    required String transactionType,
    String? description,
    required List<String> availableCategories,
    AiCategorizeCallKind callKind = AiCategorizeCallKind.automatic,
    String reason = 'categorize',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Not signed in');
    }
    return AiRequestManager.instance.runCategorize(
      client: _client,
      userId: user.id,
      transactionName: transactionName,
      amount: amount,
      transactionType: transactionType,
      description: description,
      availableCategories: availableCategories,
      kind: callKind,
      reason: reason,
      invoke: () async {
        final response = await _client.functions.invoke(
          'categorize-transaction',
          body: {
            'transaction_name': transactionName,
            'amount': amount,
            'transaction_type': transactionType,
            'description': description,
            'available_categories': availableCategories,
          },
        );

        final data = response.data;
        if (data is Map<String, dynamic>) return data;
        if (data is Map) return Map<String, dynamic>.from(data);
        throw const FormatException(
          'Unexpected response format from categorize-transaction',
        );
      },
    );
  }

  static bool shouldClassifyLeafImpact({
    required String transactionName,
    required String category,
    required String transactionType,
  }) {
    final type = transactionType.toLowerCase().trim();
    final name = transactionName.toLowerCase().trim();
    final cat = category.toLowerCase().trim();
    if (type == 'income') return false;
    final blocked = <String>[
      'transfer',
      'salary',
      'other income',
      'other expense',
      'income',
      'fawri+',
      'benefit',
      'benefitpay',
      'bank transfer',
      'account credit',
      'account was credited',
      'credited by',
    ];
    if (blocked.any((k) => name.contains(k) || cat.contains(k))) return false;
    final purchaseSignals = <String>[
      'food',
      'restaurant',
      'grocer',
      'shopping',
      'transport',
      'fuel',
      'health',
      'medical',
      'pharmacy',
      'entertainment',
      'education',
      'utilities',
      'bill',
      'travel',
      'hotel',
      'subscription',
    ];
    return purchaseSignals.any((k) => name.contains(k) || cat.contains(k));
  }

  Future<Map<String, dynamic>> classifyLeafImpact({
    required String transactionName,
    required String category,
    required String transactionType,
    String reason = 'leaf_classify',

    /// When true, daily leaf quota exhaustion propagates to caller (e.g. stop batch migration).
    bool propagateLeafQuota = false,
  }) async {
    if (!shouldClassifyLeafImpact(
      transactionName: transactionName,
      category: category,
      transactionType: transactionType,
    )) {
      return <String, dynamic>{
        'leaf_color': null,
        'title': null,
        'message': null,
      };
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      return <String, dynamic>{
        'leaf_color': null,
        'title': null,
        'message': null,
      };
    }
    try {
      return await AiRequestManager.instance.runLeafClassify(
        userId: user.id,
        transactionName: transactionName,
        category: category,
        transactionType: transactionType,
        reason: reason,
        invoke: () async {
          final response = await _client.functions.invoke(
            'classify-leaf-impact',
            body: {
              'transaction_name': transactionName,
              'category': category,
              'transaction_type': transactionType,
            },
          );
          final data = response.data;
          if (data is Map<String, dynamic>) return data;
          if (data is Map) return Map<String, dynamic>.from(data);
          throw const FormatException(
            'Unexpected response format from classify-leaf-impact',
          );
        },
      );
    } on AiQuotaExceededException {
      if (propagateLeafQuota) rethrow;
      return <String, dynamic>{
        'leaf_color': null,
        'title': null,
        'message': null,
      };
    }
  }

  Future<List<Map<String, dynamic>>> generateDetailedInsights({
    required String period,
    bool forceRefresh = false,
    String reason = 'insights_tab',
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    if (kDebugMode) {
      debugPrint('generate-detailed-insights requested period=$period');
    }

    return AiRequestManager.instance.runDetailedInsights(
      userId: user.id,
      period: period,
      reason: reason,
      forceRefresh: forceRefresh,
      invoke: () async {
        final response = await _client.functions.invoke(
          'generate-detailed-insights',
          body: {'user_id': user.id, 'period': period},
        );

        final raw = response.data;
        if (raw is! Map) return [];
        final data = raw is Map<String, dynamic>
            ? raw
            : Map<String, dynamic>.from(raw);
        final insightsRaw = data['insights'];
        if (insightsRaw is! List) return [];

        final out = <Map<String, dynamic>>[];
        for (final e in insightsRaw) {
          if (e is Map<String, dynamic>) {
            out.add(e);
          } else if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }

        if (kDebugMode) {
          debugPrint('generate-detailed-insights returned count=${out.length}');
        }
        return out;
      },
    );
  }
}

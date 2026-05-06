import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Calls Edge Function `generate-home-insights` (Gemini-backed). No API keys in the client.
  Future<List<Map<String, dynamic>>> generateHomeInsights() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

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
  }

  Future<Map<String, dynamic>> categorizeTransaction({
    required String transactionName,
    required double amount,
    required String transactionType,
    String? description,
    required List<String> availableCategories,
  }) async {
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
  }

  Future<Map<String, dynamic>> classifyLeafImpact({
    required String transactionName,
    required String category,
    required String transactionType,
  }) async {
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
  }

  Future<List<Map<String, dynamic>>> generateDetailedInsights({
    required String period,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    if (kDebugMode) {
      debugPrint('generate-detailed-insights called period=$period');
    }

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
  }
}

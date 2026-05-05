import 'package:supabase_flutter/supabase_flutter.dart';

class AiService {
  final SupabaseClient _client = Supabase.instance.client;

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
    throw const FormatException('Unexpected response format from categorize-transaction');
  }
}

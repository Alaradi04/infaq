import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:infaq/services/notification_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankNotificationSyncService {
  BankNotificationSyncService._();
  static final BankNotificationSyncService instance =
      BankNotificationSyncService._();

  static const MethodChannel _channel = MethodChannel(
    'infaq/bank_notifications',
  );
  final ValueNotifier<Map<String, dynamic>> debugState =
      ValueNotifier<Map<String, dynamic>>(<String, dynamic>{});

  bool _syncInFlight = false;
  DateTime? _lastSyncCompletedAt;
  static Timer? _debounce;

  /// Coalesces rapid triggers (e.g. startup + home bootstrap) into one sync.
  static void scheduleDebouncedSync({
    String trigger = 'unknown',
    Duration delay = const Duration(milliseconds: 900),
  }) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      unawaited(
        instance.syncPendingBankTransactions(
          trigger: '${trigger}_debounced',
          bypassThrottle: true,
        ),
      );
    });
  }

  Future<void> syncPendingBankTransactions({
    String trigger = 'unknown',
    bool bypassThrottle = false,
  }) async {
    if (_syncInFlight) {
      debugPrint('[BankSync] skipped (in flight) trigger=$trigger');
      return;
    }
    if (!bypassThrottle) {
      final last = _lastSyncCompletedAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 5)) {
        debugPrint(
          '[BankSync] skipped throttle ${DateTime.now().difference(last).inMilliseconds}ms trigger=$trigger',
        );
        return;
      }
    }
    _syncInFlight = true;
    _setDebug('lastTransactionSyncStatus', 'started:$trigger');
    debugPrint('[BankSync] sync started trigger=$trigger');
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('[BankSync] no authenticated user');
        _setDebug('lastTransactionSyncStatus', 'skipped:no_authenticated_user');
        return;
      }

      final prefs = await NotificationPreferencesService.instance
          .loadOrCreateForSettings();
      if (!prefs.smsAutoRecordingEnabled) {
        debugPrint('[BankSync] automatic recording disabled');
        _setDebug(
          'lastTransactionSyncStatus',
          'skipped:automatic_recording_disabled',
        );
        return;
      }

      final listenerEnabled = await isNotificationListenerEnabled();
      debugPrint('[BankSync] listener enabled: $listenerEnabled');
      _setDebug('listenerEnabled', listenerEnabled);
      if (!listenerEnabled) {
        _setDebug('lastTransactionSyncStatus', 'skipped:listener_disabled');
        return;
      }

      final pending = await getPendingBankTransactions();
      pending.sort(
        (a, b) => (_readInt(b['sourcePriority']) ?? 1).compareTo(
          _readInt(a['sourcePriority']) ?? 1,
        ),
      );
      debugPrint('[BankSync] pending count=${pending.length}');
      _setDebug('pendingCount', pending.length);
      if (pending.isEmpty) {
        _setDebug('lastTransactionSyncStatus', 'completed:nothing_to_sync');
        return;
      }

      final syncedIds = <String>[];
      final categoryMap = await _buildCategoryFallbackMap(user.id);
      final seenFingerprints = <String, int>{};
      for (final tx in pending) {
        debugPrint('[BankSync] pending payload=$tx');
        final fp = (tx['duplicateFingerprint'] ?? '').toString();
        final pr = _readInt(tx['sourcePriority']) ?? 1;
        if (fp.isNotEmpty && seenFingerprints.containsKey(fp)) {
          final existingPr = seenFingerprints[fp] ?? 1;
          if (existingPr >= pr) {
            _setDebug(
              'lastDuplicateDecision',
              'ignored lower priority duplicate',
            );
            debugPrint(
              '[BankSync] duplicate pending ignored lower priority fp=$fp',
            );
            syncedIds.add((tx['id'] ?? '').toString());
            continue;
          }
        }
        if (fp.isNotEmpty) seenFingerprints[fp] = pr;
        final ok = await _syncOne(user.id, tx, categoryMap);
        if (ok) syncedIds.add((tx['id'] ?? '').toString());
      }

      if (syncedIds.isNotEmpty) {
        try {
          await _channel.invokeMethod('clearSyncedBankTransactions', syncedIds);
          debugPrint('[BankSync] queue clear success ids=${syncedIds.length}');
        } catch (e, st) {
          debugPrint('[BankSync] queue clear error: $e\n$st');
        }
      }
      _setDebug(
        'lastTransactionSyncStatus',
        'completed:synced_${syncedIds.length}',
      );
    } catch (e, st) {
      debugPrint('[BankSync] sync error: $e\n$st');
      _setDebug('lastTransactionSyncStatus', 'failed:$e');
    } finally {
      _syncInFlight = false;
      _lastSyncCompletedAt = DateTime.now();
    }
  }

  Future<bool> _syncOne(
    String userId,
    Map<String, dynamic> tx,
    Map<String, List<Map<String, String>>> categoriesByType,
  ) async {
    final client = Supabase.instance.client;
    final merchant = (tx['merchant'] ?? 'Bank transaction').toString();
    final amount = _readDouble(tx['amountValue']);
    final transactionType =
        (tx['transactionType'] ?? 'expense').toString().toLowerCase() ==
            'income'
        ? 'income'
        : 'expense';
    final timestampMillis =
        _readInt(tx['timestampMillis']) ??
        DateTime.now().millisecondsSinceEpoch;
    final sourceType = (tx['sourceType'] ?? 'bank_app').toString();
    final sourcePriority = _readInt(tx['sourcePriority']) ?? 1;
    final detectedAtMillis =
        _readInt(tx['detectedAtMillis']) ?? timestampMillis;
    final fingerprint = (tx['duplicateFingerprint'] ?? '').toString();
    if (sourceType == 'benefit_app') {
      final ageMs = DateTime.now().millisecondsSinceEpoch - detectedAtMillis;
      if (ageMs < 45000) {
        _setDebug('lastDuplicateDecision', 'benefit fallback delayed');
        debugPrint('[BankSync] delaying benefit_app sync ageMs=$ageMs');
        return false;
      }
    }

    final existsInSupabase = await _existsLikelyDuplicateInSupabase(
      userId: userId,
      amount: amount,
      transactionType: transactionType,
      merchant: merchant,
      timestampMillis: timestampMillis,
    );
    if (existsInSupabase) {
      _setDebug('lastDuplicateDecision', 'skipped because exists in Supabase');
      debugPrint('[BankSync] skipped duplicate already exists in Supabase');
      return true;
    }

    final date = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
    final balanceValue = _readNullableDouble(tx['balanceValue']);
    final categoryChoice = _pickFallbackCategory(
      merchant: merchant,
      transactionType: transactionType,
      categoriesByType: categoriesByType,
    );
    debugPrint(
      '[BankSync] local category result name=${categoryChoice.$1} '
      'id=${categoryChoice.$2} type=$transactionType sourceType=$sourceType sourcePriority=$sourcePriority',
    );
    debugPrint('[BankSync] duplicateFingerprint=$fingerprint');

    const expectedTransactionColumns = <String>[
      'user_id',
      'amount',
      'category_id',
      'description',
      'date',
      'leaf_color',
      'leaf_title',
      'leaf_message',
    ];
    final payloadBase = <String, dynamic>{
      'user_id': userId,
      'amount': amount,
      'description': merchant,
      'category_id': categoryChoice.$2,
      'leaf_color': null,
      'leaf_title': null,
      'leaf_message': null,
    };
    final payloadWithDateTime = <String, dynamic>{
      ...payloadBase,
      'date': date.toIso8601String(),
    };
    final payloadDateOnly = <String, dynamic>{
      ...payloadBase,
      'date': _formatDateOnly(date),
    };

    debugPrint(
      '[BankSync] expected transactions columns=$expectedTransactionColumns',
    );
    debugPrint(
      '[BankSync] transaction parsed timestampMillis=$timestampMillis',
    );
    debugPrint('[BankSync] transaction parsed datetime=$date');
    debugPrint(
      '[BankSync] transaction insert payload(preferred datetime)=$payloadWithDateTime',
    );
    String? insertedId;
    try {
      dynamic inserted;
      try {
        inserted = await client
            .from('transactions')
            .insert(payloadWithDateTime)
            .select('id')
            .maybeSingle();
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final dateTypeError =
            msg.contains('invalid input syntax for type date') ||
            msg.contains('date/time field value out of range');
        if (!dateTypeError) rethrow;
        debugPrint(
          '[BankSync] datetime insert failed, retrying date-only payload',
        );
        debugPrint(
          '[BankSync] transaction insert payload(fallback date-only)=$payloadDateOnly',
        );
        inserted = await client
            .from('transactions')
            .insert(payloadDateOnly)
            .select('id')
            .maybeSingle();
      }
      insertedId = inserted?['id']?.toString();
      _setDebug('lastDuplicateDecision', 'saved');
      debugPrint('[BankSync] Supabase insert success id=$insertedId');
    } catch (e, st) {
      _setDebug('lastSupabaseInsertError', e.toString());
      debugPrint('[BankSync] Supabase insert error: $e\n$st');
      return false;
    }

    try {
      await _updateBalance(
        userId: userId,
        amount: amount,
        transactionType: transactionType,
        balanceValue: balanceValue,
      );
      debugPrint('[BankSync] balance update success');
    } catch (e, st) {
      debugPrint('[BankSync] balance update error: $e\n$st');
      return false;
    }

    try {
      await client.from('notifications').insert({
        'user_id': userId,
        'title': 'Transaction recorded',
        'body': 'A new transaction from $merchant was recorded automatically.',
        'type': 'sms_transaction_recorded',
        'is_ai': false,
        'target_screen': 'transactions',
        'metadata': {
          'amount': amount,
          'merchant': merchant,
          'timestampMillis': timestampMillis,
          'transactionType': transactionType,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      debugPrint('[BankSync] notification insert success');
    } catch (e, st) {
      debugPrint('[BankSync] notification insert error: $e\n$st');
    }

    unawaited(
      _runOptionalAiEnrichment(transactionId: insertedId, merchant: merchant),
    );
    return true;
  }

  Future<void> _runOptionalAiEnrichment({
    String? transactionId,
    required String merchant,
  }) async {
    if (transactionId == null || transactionId.isEmpty) return;
    try {
      _setDebug('lastAiEnrichmentStatus', 'skipped_optional');
      debugPrint(
        '[BankSync] AI enrichment skipped_optional tx=$transactionId merchant=$merchant',
      );
    } catch (e) {
      _setDebug('lastAiEnrichmentStatus', 'failed');
      debugPrint('[BankSync] AI enrichment error=$e');
    }
  }

  Future<void> _updateBalance({
    required String userId,
    required double amount,
    required String transactionType,
    required double? balanceValue,
  }) async {
    final client = Supabase.instance.client;
    final row = await client
        .from('users')
        .select('Balance,currency')
        .eq('id', userId)
        .maybeSingle();
    final currentBalance = _readDouble(row?['Balance']);
    final currency = (row?['currency'] ?? '').toString().toUpperCase();

    double nextBalance;
    if (balanceValue != null && currency == 'BHD') {
      nextBalance = balanceValue;
    } else {
      nextBalance = transactionType == 'income'
          ? currentBalance + amount.abs()
          : currentBalance - amount.abs();
    }
    await client
        .from('users')
        .update({'Balance': nextBalance})
        .eq('id', userId);
  }

  Future<Map<String, List<Map<String, String>>>> _buildCategoryFallbackMap(
    String userId,
  ) async {
    try {
      final global = await Supabase.instance.client
          .from('categories')
          .select('id,name,type,user_id')
          .isFilter('user_id', null);
      final mine = await Supabase.instance.client
          .from('categories')
          .select('id,name,type,user_id')
          .eq('user_id', userId);
      final rows = [...(global as List<dynamic>), ...(mine as List<dynamic>)];
      final out = <String, List<Map<String, String>>>{
        'income': <Map<String, String>>[],
        'expense': <Map<String, String>>[],
      };
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id']?.toString();
        final name = map['name']?.toString().trim();
        final type =
            (map['type']?.toString().trim().toLowerCase() ?? 'expense');
        if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
        if (type != 'income' && type != 'expense') continue;
        out[type]!.add({'id': id, 'name': name});
      }
      return out;
    } catch (_) {
      return <String, List<Map<String, String>>>{
        'income': <Map<String, String>>[],
        'expense': <Map<String, String>>[],
      };
    }
  }

  String _fallbackCategoryName({
    required String merchant,
    required String transactionType,
  }) {
    final m = merchant.toLowerCase();
    if (m.contains('fawri+'))
      return transactionType == 'income' ? 'Other Income' : 'Other Expense';
    if (m.contains('talabat') ||
        m.contains('jahez') ||
        m.contains('restaurant') ||
        m.contains('cafe') ||
        m.contains('food')) {
      return 'Food';
    }
    if (m.contains('talabat')) return 'Food';
    if (m.contains('uber') || m.contains('careem') || m.contains('taxi'))
      return 'Transport';
    if (m.contains('netflix') || m.contains('spotify')) return 'Entertainment';
    if (m.contains('benefit') || m.contains('fawri') || m.contains('iban'))
      return 'Transfer';
    if (m.contains('salary')) return 'Income';
    return transactionType == 'income' ? 'Income' : 'Other Expense';
  }

  (String, String?) _pickFallbackCategory({
    required String merchant,
    required String transactionType,
    required Map<String, List<Map<String, String>>> categoriesByType,
  }) {
    final m = merchant.toLowerCase();
    final isIncome = transactionType == 'income';
    final typeRows =
        categoriesByType[isIncome ? 'income' : 'expense'] ??
        const <Map<String, String>>[];

    Map<String, String>? pickByNameContains(List<String> keys) {
      for (final row in typeRows) {
        final name = (row['name'] ?? '').toLowerCase();
        if (keys.any((k) => name.contains(k))) return row;
      }
      return null;
    }

    if (isIncome &&
        (m.contains('fawri') || m.contains('benefit') || m.contains('iban'))) {
      if (m.contains('fawri+')) {
        final otherIncome = pickByNameContains(['other income', 'income']);
        if (otherIncome != null)
          return (otherIncome['name']!, otherIncome['id']);
      }
      final transfer = pickByNameContains(['transfer', 'income']);
      if (transfer != null) return (transfer['name']!, transfer['id']);
    }
    if (!isIncome && m.contains('fawri+')) {
      final otherExpense = pickByNameContains(['other expense', 'expense']);
      if (otherExpense != null)
        return (otherExpense['name']!, otherExpense['id']);
    }

    final fallbackName = _fallbackCategoryName(
      merchant: merchant,
      transactionType: transactionType,
    ).toLowerCase();
    final exact = typeRows.where(
      (e) => (e['name'] ?? '').toLowerCase() == fallbackName,
    );
    if (exact.isNotEmpty) return (exact.first['name']!, exact.first['id']);

    final byContains = pickByNameContains([fallbackName]);
    if (byContains != null) return (byContains['name']!, byContains['id']);

    if (typeRows.isNotEmpty)
      return (typeRows.first['name']!, typeRows.first['id']);
    return (isIncome ? 'Income' : 'Other Expense', null);
  }

  Future<void> openNotificationListenerSettings() async {
    await _channel.invokeMethod('openNotificationListenerSettings');
  }

  Future<bool> isNotificationListenerEnabled() async {
    final enabled = await _channel.invokeMethod<bool>(
      'isNotificationListenerEnabled',
    );
    return enabled == true;
  }

  Future<List<Map<String, dynamic>>> getPendingBankTransactions() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>(
          'getPendingBankTransactions',
        ) ??
        <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getRecentRawBankNotifications() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>(
          'getRecentRawBankNotifications',
        ) ??
        <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> setBankNotificationDebugMode(bool enabled) async {
    await _channel.invokeMethod('setBankNotificationDebugMode', enabled);
  }

  Future<Map<String, dynamic>> getNativeDebugState() async {
    final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getBankNotificationDebugState',
    );
    if (map == null) return <String, dynamic>{};
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, dynamic>> combinedDebugState() async {
    final native = await getNativeDebugState();
    return <String, dynamic>{...native, ...debugState.value};
  }

  void _setDebug(String key, dynamic value) {
    final next = <String, dynamic>{...debugState.value, key: value};
    debugState.value = next;
  }

  double _readDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  double? _readNullableDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _formatDateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> _existsLikelyDuplicateInSupabase({
    required String userId,
    required double amount,
    required String transactionType,
    required String merchant,
    required int timestampMillis,
  }) async {
    try {
      final windowStart = DateTime.fromMillisecondsSinceEpoch(
        timestampMillis,
      ).subtract(const Duration(minutes: 10)).toIso8601String();
      final rows = await Supabase.instance.client
          .from('transactions')
          .select('id,amount,description,date,created_at,categories(type,name)')
          .eq('user_id', userId)
          .gte('date', windowStart)
          .limit(50);
      final merchantNorm = merchant.toLowerCase();
      for (final r in (rows as List<dynamic>)) {
        final row = Map<String, dynamic>.from(r as Map);
        final exAmount = _readDouble(row['amount']);
        if ((exAmount - amount).abs() > 0.0009) continue;
        final cat = row['categories'];
        final catType = cat is Map
            ? (cat['type'] ?? '').toString().toLowerCase()
            : '';
        if (catType.isNotEmpty && catType != transactionType) continue;
        final desc = (row['description'] ?? '').toString().toLowerCase();
        final similarMerchant =
            desc.contains(merchantNorm) ||
            merchantNorm.contains(desc) ||
            ((merchantNorm.contains('fawri') ||
                    merchantNorm.contains('benefit')) &&
                (desc.contains('fawri') || desc.contains('benefit')));
        if (!similarMerchant) continue;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

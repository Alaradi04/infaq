import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:infaq/services/bank_notification_sync_service.dart';

class NotificationDebugScreen extends StatefulWidget {
  const NotificationDebugScreen({super.key});

  @override
  State<NotificationDebugScreen> createState() =>
      _NotificationDebugScreenState();
}

class _NotificationDebugScreenState extends State<NotificationDebugScreen> {
  bool _loading = true;
  Map<String, dynamic> _state = <String, dynamic>{};
  List<Map<String, dynamic>> _recent = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _pending = <Map<String, dynamic>>[];
  bool _showAllRawForDebug = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final service = BankNotificationSyncService.instance;
    final state = await service.combinedDebugState();
    final debugMode = state['debugCollectAllRawNotifications'] == true;
    final recent = await service.getRecentRawBankNotifications();
    final pending = await service.getPendingBankTransactions();
    if (!mounted) return;
    setState(() {
      _state = state;
      _showAllRawForDebug = debugMode;
      _recent = recent.take(10).toList();
      _pending = pending;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Debug')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _kv(
                    'listener permission status',
                    '${_state['listenerEnabled'] ?? 'unknown'}',
                  ),
                  _kv('pending local transaction count', '${_pending.length}'),
                  _kv(
                    'last parser error',
                    '${_state['lastParserError'] ?? '-'}',
                  ),
                  _kv(
                    'last parsed result',
                    '${_state['lastParsedResult'] ?? '-'}',
                  ),
                  _kv(
                    'last duplicate decision',
                    '${_state['lastDuplicateDecision'] ?? '-'}',
                  ),
                  _kv(
                    'last transaction sync status',
                    '${_state['lastTransactionSyncStatus'] ?? '-'}',
                  ),
                  _kv(
                    'last Supabase insert error',
                    '${_state['lastSupabaseInsertError'] ?? '-'}',
                  ),
                  _kv(
                    'last AI enrichment status',
                    '${_state['lastAiEnrichmentStatus'] ?? '-'}',
                  ),
                  _kv(
                    'Gemini quota status',
                    '${_state['geminiQuotaStatus'] ?? '-'}',
                  ),
                  _kv(
                    'ignored non-financial notifications count',
                    '${_state['ignoredNonFinancialNotificationsCount'] ?? 0}',
                  ),
                  _kv(
                    'last ignored notification reason',
                    '${_state['lastIgnoredNotificationReason'] ?? '-'}',
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Show all raw notifications for debugging',
                    ),
                    value: _showAllRawForDebug,
                    onChanged: (v) async {
                      await BankNotificationSyncService.instance
                          .setBankNotificationDebugMode(v);
                      if (!mounted) return;
                      setState(() => _showAllRawForDebug = v);
                      await _refresh();
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await BankNotificationSyncService.instance
                          .syncPendingBankTransactions(
                            trigger: 'manual_debug',
                            bypassThrottle: true,
                          );
                      await _refresh();
                    },
                    child: const Text('Sync Pending Transactions'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Last 10 raw notifications',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_recent),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Pending transactions JSON',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    const JsonEncoder.withIndent('  ').convert(_pending),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$key: $value'),
    );
  }
}

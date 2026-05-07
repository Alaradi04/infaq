import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/services/ai_request_manager.dart';
import 'package:infaq/services/ai_usage_logger.dart';

/// Developer-oriented view of AI call caching and daily caps.
class AiUsageDebugScreen extends StatefulWidget {
  const AiUsageDebugScreen({super.key});

  @override
  State<AiUsageDebugScreen> createState() => _AiUsageDebugScreenState();
}

class _AiUsageDebugScreenState extends State<AiUsageDebugScreen> {
  Map<String, dynamic> _snapshot = {};
  Map<String, dynamic> _persisted = {};
  Map<String, dynamic> _session = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _snapshot = {'error': 'Not signed in'};
          _persisted = {};
          _session = {};
        });
      }
      return;
    }
    final snap = await AiRequestManager.instance.debugSnapshot(user.id);
    final persisted = await AiUsageLogger.instance.loadPersistedCounters();
    final session = AiUsageLogger.instance.sessionSummary(user.id);
    if (mounted) {
      setState(() {
        _snapshot = snap;
        _persisted = persisted;
        _session = session;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI usage'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Session (this app run)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_session),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.85),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Lifetime counters (device)',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_persisted),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.85),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Today / fingerprint',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_snapshot),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.85),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Daily caps: ${AiRequestManager.maxInsightsPerDay} insight gens, '
            '${AiRequestManager.maxCategorizePerDay} categorizations, '
            '${AiRequestManager.maxManualRecategorizePerDay} manual recategorize, '
            '${AiRequestManager.maxLeafPerDay} leaf classifications.',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.65),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

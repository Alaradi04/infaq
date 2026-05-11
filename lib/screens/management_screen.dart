import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/goal_local_storage.dart';
import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/category/category_icons.dart';
import 'package:infaq/screens/add_transaction_screen.dart';
import 'package:infaq/screens/add_goal_screen.dart';
import 'package:infaq/screens/add_subscription_screen.dart';
import 'package:infaq/screens/edit_goal_screen.dart';
import 'package:infaq/screens/edit_subscription_screen.dart';
import 'package:infaq/subscription_renewal.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/monthly_spending_budget_card.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kHeaderGreenLight = Color(0xFFE8F2EA);
const Color _kHeaderGreenDark = Color(0xFF1A2520);

enum _SubFilter { all, activeOnly, inactiveOnly }

enum _SubSort { none, amountHigh, amountLow, nameAz }

enum _MgmtMainTab { transactions, subscriptions, goals }

enum _PeriodMode { today, allTime, month, year }

enum _TxTypeFilter { all, income, expense }

enum _AmountSort { none, highToLow, lowToHigh }

enum _GoalSort { none, targetHighToLow, targetLowToHigh }

/// Sentinel for “Uncategorized” in [_ManagementScreenState._categoryFilterKey].
const String _kUncategorizedCategoryKey = '__uncategorized__';

/// Management hub: Transactions, Subscriptions, Goals (replaces legacy “Currency” tab).
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({
    super.key,
    required this.currencyCode,
    required this.initialMonthlyBudget,

    /// Bumped by [HomeScreen] after each successful `_bootstrap()` so this screen refetches from Supabase
    /// (e.g. new transaction from the + button) without an app restart.
    this.transactionsListRefreshToken = 0,
    required this.onDataChanged,
    required this.onEditTransaction,
    this.onMainTabIndexChanged,
  });

  final String? currencyCode;
  final double initialMonthlyBudget;
  final int transactionsListRefreshToken;
  final VoidCallback onDataChanged;
  final void Function(Map<String, dynamic> row) onEditTransaction;
  final ValueChanged<int>? onMainTabIndexChanged;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  static const Color _kSubRenewalWarning = Color(0xFFE65100);

  _MgmtMainTab _mainTab = _MgmtMainTab.transactions;

  /// Spending budget shown in summary (persisted as `users.Balance` when edited).
  double _monthlyBudget = 0;

  _PeriodMode _txPeriodMode = _PeriodMode.month;
  DateTime _txFocusedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  int _txFocusedYear = DateTime.now().year;

  _PeriodMode _subPeriodMode = _PeriodMode.allTime;
  DateTime _subFocusedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  int _subFocusedYear = DateTime.now().year;

  _PeriodMode _goalPeriodMode = _PeriodMode.allTime;
  DateTime _goalFocusedMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  int _goalFocusedYear = DateTime.now().year;

  String _searchQuery = '';
  _TxTypeFilter _typeFilter = _TxTypeFilter.all;
  _AmountSort _amountSort = _AmountSort.none;

  /// `null` = all categories; [_kUncategorizedCategoryKey] = no category; else exact `categories.name`.
  String? _categoryFilterKey;

  String _subSearchQuery = '';
  _SubFilter _subFilter = _SubFilter.all;
  _SubSort _subSort = _SubSort.none;

  String _goalSearchQuery = '';
  _GoalSort _goalSort = _GoalSort.none;

  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _goals = [];

  /// Goal id → Material icon codePoint; same storage as [EditGoalScreen] (`goal_local_v1_<id>` JSON).
  Map<String, int> _goalIconCodePoints = {};
  Map<String, Color> _goalIconColors = {};

  bool _loadingTx = true;
  bool _loadingSub = false;
  bool _loadingGoals = false;
  final Set<String> _deletingTxIds = <String>{};
  final Set<String> _updatingTxIds = <String>{};
  final Set<String> _deletingSubIds = <String>{};
  final Set<String> _updatingSubIds = <String>{};
  final Set<String> _deletingGoalIds = <String>{};
  final Set<String> _updatingGoalIds = <String>{};

  bool _txSelectMode = false;
  final Set<String> _selectedTxIds = <String>{};
  bool _subSelectMode = false;
  final Set<String> _selectedSubIds = <String>{};
  bool _goalSelectMode = false;
  final Set<String> _selectedGoalIds = <String>{};
  bool _bulkDeleting = false;
  final Set<String> _removingTxIds = <String>{};
  final Set<String> _removingSubIds = <String>{};
  final Set<String> _removingGoalIds = <String>{};

  @override
  void initState() {
    super.initState();
    _monthlyBudget = widget.initialMonthlyBudget;
    _loadTransactions();
  }

  @override
  void didUpdateWidget(ManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMonthlyBudget != widget.initialMonthlyBudget) {
      _monthlyBudget = widget.initialMonthlyBudget;
    }
    if (oldWidget.transactionsListRefreshToken !=
        widget.transactionsListRefreshToken) {
      _loadTransactions();
      _loadSubscriptions();
      _loadGoals();
    }
  }

  Future<void> _refreshAll() async {
    await _loadTransactions();
    if (_mainTab == _MgmtMainTab.subscriptions) await _loadSubscriptions();
    if (_mainTab == _MgmtMainTab.goals) await _loadGoals();
    widget.onDataChanged();
  }

  Future<void> _loadTransactions() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingTx = false);
      return;
    }
    setState(() => _loadingTx = true);
    try {
      dynamic res;
      try {
        try {
          res = await Supabase.instance.client
              .from('transactions')
              .select(
                'id, amount, description, date, created_at, category_id, leaf_color, leaf_title, leaf_message, categories(id, name, type, icon_key, color)',
              )
              .eq('user_id', user.id)
              .order('date', ascending: false)
              .limit(500);
        } catch (_) {
          res = await Supabase.instance.client
              .from('transactions')
              .select(
                'id, amount, description, date, created_at, category_id, leaf_color, leaf_title, leaf_message, categories(id, name, type, icon_key)',
              )
              .eq('user_id', user.id)
              .order('date', ascending: false)
              .limit(500);
        }
      } catch (_) {
        res = await Supabase.instance.client
            .from('transactions')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(500);
      }
      final list = (res as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      list.sort((a, b) {
        final ad = _txDate(a);
        final bd = _txDate(b);
        if (ad != null && bd != null) {
          final cmp = bd.compareTo(ad);
          if (cmp != 0) return cmp;
        } else if (bd != null) {
          return 1;
        } else if (ad != null) {
          return -1;
        }
        final ac = DateTime.tryParse((a['created_at'] ?? '').toString());
        final bc = DateTime.tryParse((b['created_at'] ?? '').toString());
        if (ac != null && bc != null) return bc.compareTo(ac);
        return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
      });
      if (!mounted) return;
      setState(() {
        _transactions = list;
        _loadingTx = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingTx = false);
    }
  }

  Future<void> _loadSubscriptions() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _loadingSub = true);
    try {
      final res = await Supabase.instance.client
          .from('subscriptions')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _subscriptions = list;
        _loadingSub = false;
      });
      for (final s in list) {
        SubscriptionRenewal.debugLogRenewal(s);
      }
      unawaited(_syncStaleSubscriptionNextPayments());
    } catch (_) {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  /// Rolls stale `next_payment` forward on the server for active recurring subs.
  Future<void> _syncStaleSubscriptionNextPayments() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) return;
    final client = Supabase.instance.client;
    final updates = <String, String>{};
    for (final s in List<Map<String, dynamic>>.from(_subscriptions)) {
      final id = s['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final anchor = SubscriptionRenewal.anchorDate(s);
      if (anchor == null) continue;
      final rolled = SubscriptionRenewal.displayNextRenewal(s);
      if (rolled == null) continue;
      if (!SubscriptionRenewal.shouldPersistRolledDate(s, anchor, rolled)) {
        continue;
      }
      updates[id] = SubscriptionRenewal.toIsoDate(rolled);
    }
    for (final e in updates.entries) {
      try {
        await client
            .from('subscriptions')
            .update({'next_payment': e.value})
            .eq('id', e.key)
            .eq('user_id', user.id);
      } catch (err) {
        debugPrint('sync subscription ${e.key} next_payment: $err');
      }
    }
    if (!mounted || updates.isEmpty) return;
    setState(() {
      for (final e in updates.entries) {
        final idx = _subscriptions.indexWhere(
          (x) => x['id']?.toString() == e.key,
        );
        if (idx >= 0) {
          final m = Map<String, dynamic>.from(_subscriptions[idx]);
          m['next_payment'] = e.value;
          _subscriptions[idx] = m;
        }
      }
    });
  }

  Future<void> _loadGoals() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _loadingGoals = true);
    try {
      final res = await Supabase.instance.client
          .from('goals')
          .select()
          .eq('created_by', user.id)
          .order('created_at', ascending: false);
      final list = (res as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _goals = list;
        _loadingGoals = false;
      });
      await _syncGoalIconsFromPrefs();
    } catch (_) {
      if (mounted) setState(() => _loadingGoals = false);
    }
  }

  /// Reads per-goal icon from local prefs so list cards match [EditGoalScreen].
  Future<void> _syncGoalIconsFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final next = <String, int>{};
    final nextColors = <String, Color>{};
    for (final g in _goals) {
      final id = g['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final raw = p.getString(goalLocalExtrasPrefsKey(id));
      if (raw == null) continue;
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final cp = (m['icon'] as num?)?.toInt();
        final c = (m['icon_color'] as num?)?.toInt();
        if (cp != null) next[id] = cp;
        if (c != null) nextColors[id] = Color(c);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _goalIconCodePoints = next;
        _goalIconColors = nextColors;
      });
    }
  }

  void _exitBulkSelectionInternal() {
    _txSelectMode = false;
    _selectedTxIds.clear();
    _subSelectMode = false;
    _selectedSubIds.clear();
    _goalSelectMode = false;
    _selectedGoalIds.clear();
  }

  void _exitBulkSelection() {
    setState(_exitBulkSelectionInternal);
  }

  bool get _bulkSelectionActive => switch (_mainTab) {
    _MgmtMainTab.transactions => _txSelectMode,
    _MgmtMainTab.subscriptions => _subSelectMode,
    _MgmtMainTab.goals => _goalSelectMode,
  };

  Widget _wrapListCardExit({required bool exiting, required Widget child}) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInCubic,
      offset: exiting ? const Offset(0, -0.05) : Offset.zero,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInCubic,
        opacity: exiting ? 0.0 : 1.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInCubic,
          scale: exiting ? 0.92 : 1.0,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  void _onTransactionLongPress(String id) {
    if (id.isEmpty) return;
    setState(() {
      _txSelectMode = true;
      _selectedTxIds.add(id);
    });
  }

  void _toggleTransactionSelect(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedTxIds.contains(id)) {
        _selectedTxIds.remove(id);
        if (_selectedTxIds.isEmpty) _txSelectMode = false;
      } else {
        _selectedTxIds.add(id);
      }
    });
  }

  void _selectAllFilteredTransactions() {
    setState(() {
      _txSelectMode = true;
      for (final t in _filteredTransactions) {
        final id = t['id']?.toString();
        if (id != null && id.isNotEmpty) _selectedTxIds.add(id);
      }
    });
  }

  void _clearTransactionSelection() {
    setState(() {
      _selectedTxIds.clear();
      _txSelectMode = false;
    });
  }

  void _onSubscriptionLongPress(String id) {
    if (id.isEmpty) return;
    setState(() {
      _subSelectMode = true;
      _selectedSubIds.add(id);
    });
  }

  void _toggleSubscriptionSelect(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedSubIds.contains(id)) {
        _selectedSubIds.remove(id);
        if (_selectedSubIds.isEmpty) _subSelectMode = false;
      } else {
        _selectedSubIds.add(id);
      }
    });
  }

  void _selectAllFilteredSubscriptions() {
    setState(() {
      _subSelectMode = true;
      for (final s in _filteredSubscriptionsList) {
        final id = s['id']?.toString();
        if (id != null && id.isNotEmpty) _selectedSubIds.add(id);
      }
    });
  }

  void _clearSubscriptionSelection() {
    setState(() {
      _selectedSubIds.clear();
      _subSelectMode = false;
    });
  }

  void _onGoalLongPress(String id) {
    if (id.isEmpty) return;
    setState(() {
      _goalSelectMode = true;
      _selectedGoalIds.add(id);
    });
  }

  void _toggleGoalSelect(String id) {
    if (id.isEmpty) return;
    setState(() {
      if (_selectedGoalIds.contains(id)) {
        _selectedGoalIds.remove(id);
        if (_selectedGoalIds.isEmpty) _goalSelectMode = false;
      } else {
        _selectedGoalIds.add(id);
      }
    });
  }

  void _selectAllFilteredGoals() {
    setState(() {
      _goalSelectMode = true;
      for (final g in _filteredGoalsList) {
        final id = g['id']?.toString();
        if (id != null && id.isNotEmpty) _selectedGoalIds.add(id);
      }
    });
  }

  void _clearGoalSelection() {
    setState(() {
      _selectedGoalIds.clear();
      _goalSelectMode = false;
    });
  }

  Future<Set<String>> _deleteTransactionIdsBatched(List<String> ids) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || ids.isEmpty) return ids.toSet();
    try {
      await Supabase.instance.client
          .from('transactions')
          .delete()
          .inFilter('id', ids)
          .eq('user_id', user.id);
      return <String>{};
    } catch (e, st) {
      debugPrint('Batch delete transactions failed: $e\n$st');
      final failed = <String>{};
      for (final id in ids) {
        try {
          await Supabase.instance.client
              .from('transactions')
              .delete()
              .eq('id', id)
              .eq('user_id', user.id);
        } catch (e2, st2) {
          debugPrint('Delete transaction $id failed: $e2\n$st2');
          failed.add(id);
        }
      }
      return failed;
    }
  }

  Future<Set<String>> _deleteSubscriptionIdsBatched(List<String> ids) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || ids.isEmpty) return ids.toSet();
    try {
      await Supabase.instance.client
          .from('subscriptions')
          .delete()
          .inFilter('id', ids)
          .eq('user_id', user.id);
      return <String>{};
    } catch (e, st) {
      debugPrint('Batch delete subscriptions failed: $e\n$st');
      final failed = <String>{};
      for (final id in ids) {
        try {
          await Supabase.instance.client
              .from('subscriptions')
              .delete()
              .eq('id', id)
              .eq('user_id', user.id);
        } catch (e2, st2) {
          debugPrint('Delete subscription $id failed: $e2\n$st2');
          failed.add(id);
        }
      }
      return failed;
    }
  }

  Future<Set<String>> _deleteGoalIdsBatched(List<String> ids) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || ids.isEmpty) return ids.toSet();
    try {
      await Supabase.instance.client
          .from('goals')
          .delete()
          .inFilter('id', ids)
          .eq('created_by', user.id);
      return <String>{};
    } catch (e, st) {
      debugPrint('Batch delete goals failed: $e\n$st');
      final failed = <String>{};
      for (final id in ids) {
        try {
          await Supabase.instance.client
              .from('goals')
              .delete()
              .eq('id', id)
              .eq('created_by', user.id);
        } catch (e2, st2) {
          debugPrint('Delete goal $id failed: $e2\n$st2');
          failed.add(id);
        }
      }
      return failed;
    }
  }

  Future<void> _onBulkDeleteTransactionsPressed() async {
    final ids = _selectedTxIds.toList();
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n ${n == 1 ? 'transaction' : 'transactions'}?'),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkDeleting = true);
    final failed = await _deleteTransactionIdsBatched(ids);
    final success = ids.where((id) => !failed.contains(id)).toList();
    if (!mounted) return;
    if (success.isEmpty) {
      setState(() => _bulkDeleting = false);
      if (failed.isNotEmpty) {
        showInfaqSnack(
          context,
          'Could not delete selected items. They stay selected.',
        );
      }
      return;
    }
    setState(() {
      _bulkDeleting = false;
      _removingTxIds.addAll(success);
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _transactions.removeWhere((t) => success.contains(t['id']?.toString()));
      _removingTxIds.removeAll(success);
      _selectedTxIds.removeAll(success);
      if (_selectedTxIds.isEmpty) _txSelectMode = false;
    });
    unawaited(_refreshBalanceOnly());
    widget.onDataChanged();
    if (failed.isNotEmpty) {
      showInfaqSnack(
        context,
        'Deleted ${success.length} of $n. ${failed.length} could not be removed — still selected.',
      );
    } else {
      showInfaqSnack(
        context,
        'Deleted ${success.length} ${success.length == 1 ? 'transaction' : 'transactions'}.',
      );
    }
  }

  Future<void> _onBulkDeleteSubscriptionsPressed() async {
    final ids = _selectedSubIds.toList();
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n ${n == 1 ? 'subscription' : 'subscriptions'}?'),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkDeleting = true);
    final failed = await _deleteSubscriptionIdsBatched(ids);
    final success = ids.where((id) => !failed.contains(id)).toList();
    if (!mounted) return;
    if (success.isEmpty) {
      setState(() => _bulkDeleting = false);
      if (failed.isNotEmpty) {
        showInfaqSnack(
          context,
          'Could not delete selected items. They stay selected.',
        );
      }
      return;
    }
    setState(() {
      _bulkDeleting = false;
      _removingSubIds.addAll(success);
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _subscriptions.removeWhere((e) => success.contains(e['id']?.toString()));
      _removingSubIds.removeAll(success);
      _selectedSubIds.removeAll(success);
      if (_selectedSubIds.isEmpty) _subSelectMode = false;
    });
    if (failed.isNotEmpty) {
      showInfaqSnack(
        context,
        'Deleted ${success.length} of $n. ${failed.length} could not be removed — still selected.',
      );
    } else {
      showInfaqSnack(
        context,
        'Deleted ${success.length} ${success.length == 1 ? 'subscription' : 'subscriptions'}.',
      );
    }
  }

  Future<void> _onBulkDeleteGoalsPressed() async {
    final ids = _selectedGoalIds.toList();
    if (ids.isEmpty) return;
    final n = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $n ${n == 1 ? 'goal' : 'goals'}?'),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkDeleting = true);
    final failed = await _deleteGoalIdsBatched(ids);
    final success = ids.where((id) => !failed.contains(id)).toList();
    if (!mounted) return;
    if (success.isEmpty) {
      setState(() => _bulkDeleting = false);
      if (failed.isNotEmpty) {
        showInfaqSnack(
          context,
          'Could not delete selected items. They stay selected.',
        );
      }
      return;
    }
    setState(() {
      _bulkDeleting = false;
      _removingGoalIds.addAll(success);
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      for (final id in success) {
        _goals.removeWhere((e) => e['id']?.toString() == id);
        _goalIconCodePoints.remove(id);
        _goalIconColors.remove(id);
      }
      _removingGoalIds.removeAll(success);
      _selectedGoalIds.removeAll(success);
      if (_selectedGoalIds.isEmpty) _goalSelectMode = false;
    });
    if (failed.isNotEmpty) {
      showInfaqSnack(
        context,
        'Deleted ${success.length} of $n. ${failed.length} could not be removed — still selected.',
      );
    } else {
      showInfaqSnack(
        context,
        'Deleted ${success.length} ${success.length == 1 ? 'goal' : 'goals'}.',
      );
    }
  }

  Widget _buildManagementHeaderTopRow(ColorScheme cs) {
    if (_mainTab == _MgmtMainTab.transactions && _txSelectMode) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Exit selection',
            onPressed: _exitBulkSelection,
            icon: Icon(Icons.close_rounded, color: cs.primary),
          ),
          Expanded(
            child: Text(
              '${_selectedTxIds.length} selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: cs.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: _selectAllFilteredTransactions,
            child: Text(
              'All',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearTransactionSelection,
            child: Text(
              'Clear',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          _bulkDeleting
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedTxIds.isEmpty
                      ? null
                      : _onBulkDeleteTransactionsPressed,
                  icon: Icon(Icons.delete_outline_rounded, color: cs.primary),
                ),
        ],
      );
    }
    if (_mainTab == _MgmtMainTab.subscriptions && _subSelectMode) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Exit selection',
            onPressed: _exitBulkSelection,
            icon: Icon(Icons.close_rounded, color: cs.primary),
          ),
          Expanded(
            child: Text(
              '${_selectedSubIds.length} selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: cs.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: _selectAllFilteredSubscriptions,
            child: Text(
              'All',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearSubscriptionSelection,
            child: Text(
              'Clear',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          _bulkDeleting
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedSubIds.isEmpty
                      ? null
                      : _onBulkDeleteSubscriptionsPressed,
                  icon: Icon(Icons.delete_outline_rounded, color: cs.primary),
                ),
        ],
      );
    }
    if (_mainTab == _MgmtMainTab.goals && _goalSelectMode) {
      return Row(
        children: [
          IconButton(
            tooltip: 'Exit selection',
            onPressed: _exitBulkSelection,
            icon: Icon(Icons.close_rounded, color: cs.primary),
          ),
          Expanded(
            child: Text(
              '${_selectedGoalIds.length} selected',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: cs.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: _selectAllFilteredGoals,
            child: Text(
              'All',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _clearGoalSelection,
            child: Text(
              'Clear',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
          _bulkDeleting
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Delete selected',
                  onPressed: _selectedGoalIds.isEmpty
                      ? null
                      : _onBulkDeleteGoalsPressed,
                  icon: Icon(Icons.delete_outline_rounded, color: cs.primary),
                ),
        ],
      );
    }
    return Row(
      children: [
        Text(
          'Management',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
            height: 1.15,
            color: cs.primary,
          ),
        ),
        const Spacer(),
        if (!_bulkSelectionActive)
          IconButton(
            onPressed: _pickPeriodMode,
            iconSize: 25,
            icon: Icon(Icons.schedule_rounded, color: cs.primary),
            tooltip: 'Date range',
          ),
      ],
    );
  }

  void _onMainTabChanged(_MgmtMainTab t) {
    setState(() {
      _mainTab = t;
      _exitBulkSelectionInternal();
    });
    widget.onMainTabIndexChanged?.call(t.index);
    if (t == _MgmtMainTab.subscriptions &&
        _subscriptions.isEmpty &&
        !_loadingSub) {
      _loadSubscriptions();
    }
    if (t == _MgmtMainTab.goals && _goals.isEmpty && !_loadingGoals) {
      _loadGoals();
    }
  }

  String _currencyPrefix() {
    switch (widget.currencyCode?.toUpperCase()) {
      case 'USD':
        return r'$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'SAR':
        return 'SAR ';
      case 'BHD':
        return 'BHD ';
      case 'JPY':
        return '¥';
      default:
        final c = widget.currencyCode?.trim();
        return c == null || c.isEmpty ? '' : '$c ';
    }
  }

  String _fmtMoney(double v) {
    final p = _currencyPrefix();
    final n = v.abs();
    final s = n >= 1000 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
    return '$p$s';
  }

  static double _readAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  static DateTime? _txDate(Map<String, dynamic> r) {
    final raw = r['date'] ?? r['created_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static bool _isExpenseRow(Map<String, dynamic> data, double amount) {
    final catMap = data['categories'];
    String? catType;
    if (catMap is Map) catType = catMap['type']?.toString().toLowerCase();
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

  static String _categoryDisplayName(Map<String, dynamic> r) {
    final cat = r['categories'];
    if (cat is Map) {
      final n = cat['name']?.toString().trim();
      if (n != null && n.isNotEmpty) return n;
    }
    final legacy = (r['category'] ?? r['category_name'] ?? '')
        .toString()
        .trim();
    return legacy;
  }

  bool _rowMatchesTypeFilter(Map<String, dynamic> r) {
    final amount = _readAmount(r['amount']);
    switch (_typeFilter) {
      case _TxTypeFilter.all:
        return true;
      case _TxTypeFilter.income:
        return !_isExpenseRow(r, amount);
      case _TxTypeFilter.expense:
        return _isExpenseRow(r, amount);
    }
  }

  /// Categories present in the current date range, respecting the selected type (All / Income / Expense).
  ({List<String> named, bool hasUncategorized})
  _categoryOptionsForTypeFilter() {
    final named = <String>{};
    var hasUncategorized = false;
    for (final r in _transactions) {
      final d = _txDate(r);
      if (!_inPeriod(d, _txPeriodMode, _txFocusedMonth, _txFocusedYear)) {
        continue;
      }
      if (!_rowMatchesTypeFilter(r)) continue;
      final label = _categoryDisplayName(r);
      if (label.isEmpty) {
        hasUncategorized = true;
      } else {
        named.add(label);
      }
    }
    final list = named.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return (named: list, hasUncategorized: hasUncategorized);
  }

  bool _inPeriod(
    DateTime? d,
    _PeriodMode mode,
    DateTime focusedMonth,
    int focusedYear,
  ) {
    if (d == null) return false;
    switch (mode) {
      case _PeriodMode.today:
        final now = DateTime.now();
        return d.year == now.year && d.month == now.month && d.day == now.day;
      case _PeriodMode.allTime:
        return true;
      case _PeriodMode.month:
        return d.year == focusedMonth.year && d.month == focusedMonth.month;
      case _PeriodMode.year:
        return d.year == focusedYear;
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    var list = List<Map<String, dynamic>>.from(_transactions);
    list = list.where((r) {
      final d = _txDate(r);
      return _inPeriod(d, _txPeriodMode, _txFocusedMonth, _txFocusedYear);
    }).toList();

    if (_typeFilter == _TxTypeFilter.income) {
      list = list
          .where((r) => !_isExpenseRow(r, _readAmount(r['amount'])))
          .toList();
    } else if (_typeFilter == _TxTypeFilter.expense) {
      list = list
          .where((r) => _isExpenseRow(r, _readAmount(r['amount'])))
          .toList();
    }

    if (_categoryFilterKey != null) {
      list = list.where((r) {
        final name = _categoryDisplayName(r);
        if (_categoryFilterKey == _kUncategorizedCategoryKey) {
          return name.isEmpty;
        }
        return name == _categoryFilterKey;
      }).toList();
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final desc = (r['description'] ?? '').toString().toLowerCase();
        final cat = r['categories'];
        final catName = cat is Map
            ? (cat['name'] ?? '').toString().toLowerCase()
            : '';
        return desc.contains(q) || catName.contains(q);
      }).toList();
    }

    if (_amountSort == _AmountSort.highToLow) {
      list.sort(
        (a, b) => _readAmount(
          b['amount'],
        ).abs().compareTo(_readAmount(a['amount']).abs()),
      );
    } else if (_amountSort == _AmountSort.lowToHigh) {
      list.sort(
        (a, b) => _readAmount(
          a['amount'],
        ).abs().compareTo(_readAmount(b['amount']).abs()),
      );
    }

    return list;
  }

  double _totalSpentInPeriod() {
    var sum = 0.0;
    for (final r in _filteredTransactions.where(
      (x) => _isExpenseRow(x, _readAmount(x['amount'])),
    )) {
      sum += _readAmount(r['amount']).abs();
    }
    return sum;
  }

  String _periodTitle() {
    switch (_txPeriodMode) {
      case _PeriodMode.today:
        return 'Today';
      case _PeriodMode.allTime:
        return 'All time';
      case _PeriodMode.month:
        const months = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return '${months[_txFocusedMonth.month - 1]} ${_txFocusedMonth.year}';
      case _PeriodMode.year:
        return '$_txFocusedYear';
    }
  }

  String _activeHistoryTitle() {
    switch (_mainTab) {
      case _MgmtMainTab.transactions:
        return 'Show transactions';
      case _MgmtMainTab.subscriptions:
        return 'Show subscriptions';
      case _MgmtMainTab.goals:
        return 'Show goals';
    }
  }

  Future<void> _pickPeriodMode() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  _activeHistoryTitle(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              ListTile(
                title: const Text('Today'),
                onTap: () {
                  setState(() {
                    switch (_mainTab) {
                      case _MgmtMainTab.transactions:
                        _txPeriodMode = _PeriodMode.today;
                      case _MgmtMainTab.subscriptions:
                        _subPeriodMode = _PeriodMode.today;
                      case _MgmtMainTab.goals:
                        _goalPeriodMode = _PeriodMode.today;
                    }
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('All time'),
                onTap: () {
                  setState(() {
                    switch (_mainTab) {
                      case _MgmtMainTab.transactions:
                        _txPeriodMode = _PeriodMode.allTime;
                      case _MgmtMainTab.subscriptions:
                        _subPeriodMode = _PeriodMode.allTime;
                      case _MgmtMainTab.goals:
                        _goalPeriodMode = _PeriodMode.allTime;
                    }
                  });
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Single month'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final currentMonth = switch (_mainTab) {
                    _MgmtMainTab.transactions => _txFocusedMonth,
                    _MgmtMainTab.subscriptions => _subFocusedMonth,
                    _MgmtMainTab.goals => _goalFocusedMonth,
                  };
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: currentMonth,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDatePickerMode: DatePickerMode.year,
                    helpText: 'Pick any day in the month',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      switch (_mainTab) {
                        case _MgmtMainTab.transactions:
                          _txPeriodMode = _PeriodMode.month;
                          _txFocusedMonth = DateTime(picked.year, picked.month);
                        case _MgmtMainTab.subscriptions:
                          _subPeriodMode = _PeriodMode.month;
                          _subFocusedMonth = DateTime(
                            picked.year,
                            picked.month,
                          );
                        case _MgmtMainTab.goals:
                          _goalPeriodMode = _PeriodMode.month;
                          _goalFocusedMonth = DateTime(
                            picked.year,
                            picked.month,
                          );
                      }
                    });
                  }
                },
              ),
              ListTile(
                title: const Text('Whole year'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final currentYear = switch (_mainTab) {
                    _MgmtMainTab.transactions => _txFocusedYear,
                    _MgmtMainTab.subscriptions => _subFocusedYear,
                    _MgmtMainTab.goals => _goalFocusedYear,
                  };
                  final y = await showDialog<int>(
                    context: context,
                    builder: (c) {
                      var year = currentYear;
                      return AlertDialog(
                        title: const Text('Year'),
                        content: StatefulBuilder(
                          builder: (context, setS) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () => setS(() => year -= 1),
                                  icon: const Icon(Icons.remove),
                                ),
                                Text(
                                  '$year',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setS(() => year += 1),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            );
                          },
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, year),
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    },
                  );
                  if (y != null && mounted) {
                    setState(() {
                      switch (_mainTab) {
                        case _MgmtMainTab.transactions:
                          _txPeriodMode = _PeriodMode.year;
                          _txFocusedYear = y;
                        case _MgmtMainTab.subscriptions:
                          _subPeriodMode = _PeriodMode.year;
                          _subFocusedYear = y;
                        case _MgmtMainTab.goals:
                          _goalPeriodMode = _PeriodMode.year;
                          _goalFocusedYear = y;
                      }
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _shiftMonth(int delta) {
    setState(() {
      _txPeriodMode = _PeriodMode.month;
      _txFocusedMonth = DateTime(
        _txFocusedMonth.year,
        _txFocusedMonth.month + delta,
      );
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      _txPeriodMode = _PeriodMode.year;
      _txFocusedYear += delta;
    });
  }

  Future<void> _editBudget() async {
    final ctrl = TextEditingController(
      text: _monthlyBudget > 0
          ? _monthlyBudget.toStringAsFixed(_monthlyBudget % 1 == 0 ? 0 : 2)
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'e.g. 1000',
            suffixText: widget.currencyCode ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final v = double.tryParse(ctrl.text.replaceAll(',', ''));
    if (v == null || v < 0) {
      showInfaqSnack(context, 'Enter a valid budget.');
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('users')
          .update({'Balance': v})
          .eq('id', user.id);
      if (!mounted) return;
      setState(() => _monthlyBudget = v);
      widget.onDataChanged();
      showInfaqSnack(context, 'Budget updated');
    } catch (e) {
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not save budget right now. Please try again.',
        );
      }
    }
  }

  Future<bool> _deleteTransaction(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return false;
    final title = (row['description'] ?? 'This transaction').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(
          title.length > 80 ? '${title.substring(0, 80)}…' : title,
          style: TextStyle(
            color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    setState(() => _deletingTxIds.add(id));
    try {
      await Supabase.instance.client
          .from('transactions')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);
      if (!mounted) return false;
      setState(() {
        _deletingTxIds.remove(id);
        _transactions.removeWhere((t) => t['id']?.toString() == id);
      });
      unawaited(_refreshBalanceOnly());
      widget.onDataChanged();
      if (mounted) showInfaqSnack(context, 'Transaction deleted');
      return true;
    } catch (e) {
      if (mounted) setState(() => _deletingTxIds.remove(id));
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not delete transaction right now. Please try again.',
        );
      }
      return false;
    }
  }

  Future<void> _openEditTransactionLocal(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddTransactionScreen(
          currencyCode: widget.currencyCode,
          existingTransaction: Map<String, dynamic>.from(row),
        ),
      ),
    );
    if (changed != true || !mounted) return;
    setState(() => _updatingTxIds.add(id));
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      dynamic fetched;
      try {
        fetched = await Supabase.instance.client
            .from('transactions')
            .select(
              'id, amount, description, date, created_at, category_id, leaf_color, leaf_title, leaf_message, categories(id, name, type, icon_key, color)',
            )
            .eq('id', id)
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (_) {
        fetched = await Supabase.instance.client
            .from('transactions')
            .select(
              'id, amount, description, date, created_at, category_id, leaf_color, leaf_title, leaf_message, categories(id, name, type, icon_key)',
            )
            .eq('id', id)
            .eq('user_id', user.id)
            .maybeSingle();
      }
      if (fetched != null && mounted) {
        final fresh = Map<String, dynamic>.from(fetched as Map);
        setState(() {
          final idx = _transactions.indexWhere(
            (t) => t['id']?.toString() == id,
          );
          if (idx >= 0) _transactions[idx] = fresh;
        });
      }
      unawaited(_refreshBalanceOnly());
      widget.onDataChanged();
      if (mounted) showInfaqSnack(context, 'Transaction updated');
    } catch (e) {
      if (mounted) {
        showInfaqSnack(context, 'Could not refresh edited row right now.');
      }
    } finally {
      if (mounted) setState(() => _updatingTxIds.remove(id));
    }
  }

  Future<void> _refreshBalanceOnly() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('Balance')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _monthlyBudget = _readAmount(row['Balance']));
    } catch (_) {}
  }

  Widget _animatedListItem({required String keyId, required Widget child}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(keyId),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset((1 - t) * 10, 0), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spent = _totalSpentInPeriod();
    final budget = _monthlyBudget;

    final headerTint = isDark ? _kHeaderGreenDark : _kHeaderGreenLight;
    final headerTintActive = _bulkSelectionActive
        ? Color.lerp(headerTint, cs.primary, isDark ? 0.22 : 0.14) ?? headerTint
        : headerTint;

    return PopScope(
      canPop: !_bulkSelectionActive,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        if (!mounted) return;
        _exitBulkSelection();
      },
      child: ColoredBox(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: headerTintActive,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildManagementHeaderTopRow(cs),
                      const SizedBox(height: 12),
                      _MgmtPillTabs(
                        selected: _mainTab,
                        onChanged: _onMainTabChanged,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: cs.primary,
                onRefresh: _refreshAll,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 210),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_mainTab.index),
                    child: _mainTab == _MgmtMainTab.transactions
                        ? _buildTransactionsTab(spent: spent, budget: budget)
                        : _mainTab == _MgmtMainTab.subscriptions
                        ? _buildSubscriptionsTab()
                        : _buildGoalsTab(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsTab({
    required double spent,
    required double budget,
  }) {
    if (_loadingTx) {
      return ListView(
        children: [
          SizedBox(height: 120),
          Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      );
    }

    final list = _filteredTransactions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        MonthlySpendingBudgetCard(
          periodTitle: _periodTitle(),
          onPrev: _txPeriodMode == _PeriodMode.month
              ? () => _shiftMonth(-1)
              : _txPeriodMode == _PeriodMode.year
              ? () => _shiftYear(-1)
              : null,
          onNext: _txPeriodMode == _PeriodMode.month
              ? () => _shiftMonth(1)
              : _txPeriodMode == _PeriodMode.year
              ? () => _shiftYear(1)
              : null,
          onEditBudget: _editBudget,
          spentLabel: 'Total spent',
          budgetLabel: 'Budget',
          showRemainingLine: false,
          spent: spent,
          budget: budget,
          format: _fmtMoney,
        ),
        const SizedBox(height: 14),
        _SearchFilterBar(
          searchHint: 'Search',
          query: _searchQuery,
          onQueryChanged: (v) => setState(() => _searchQuery = v),
          onType: () => _showTypeSheet(),
          onFilter: _showCategoryFilterSheet,
          onSort: () => _showSortSheet(),
          showTypeButton: true,
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No transactions for this view. Change filters or add a transaction.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          )
        else
          for (final t in list)
            _animatedListItem(
              keyId: 'tx-${t['id']}-${t.hashCode}',
              child: _wrapListCardExit(
                exiting: _removingTxIds.contains(t['id']?.toString()),
                child: _MgmtTxTile(
                  data: t,
                  format: _fmtMoney,
                  onTap: () => _openEditTransactionLocal(t),
                  confirmDismissDelete: () => _deleteTransaction(t),
                  isBusy:
                      _deletingTxIds.contains(t['id']?.toString()) ||
                      _updatingTxIds.contains(t['id']?.toString()),
                  selectionMode: _txSelectMode,
                  selected: _selectedTxIds.contains(t['id']?.toString()),
                  onLongPress: () =>
                      _onTransactionLongPress(t['id']?.toString() ?? ''),
                  onToggleSelect: () =>
                      _toggleTransactionSelect(t['id']?.toString() ?? ''),
                ),
              ),
            ),
      ],
    );
  }

  void _showTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Type',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            RadioListTile<_TxTypeFilter>(
              title: const Text('All'),
              value: _TxTypeFilter.all,
              groupValue: _typeFilter,
              onChanged: (v) {
                setState(() {
                  _typeFilter = v ?? _TxTypeFilter.all;
                  _categoryFilterKey = null;
                });
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_TxTypeFilter>(
              title: const Text('Income'),
              value: _TxTypeFilter.income,
              groupValue: _typeFilter,
              onChanged: (v) {
                setState(() {
                  _typeFilter = v ?? _TxTypeFilter.income;
                  _categoryFilterKey = null;
                });
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_TxTypeFilter>(
              title: const Text('Expense'),
              value: _TxTypeFilter.expense,
              groupValue: _typeFilter,
              onChanged: (v) {
                setState(() {
                  _typeFilter = v ?? _TxTypeFilter.expense;
                  _categoryFilterKey = null;
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryFilterSheet() {
    final opts = _categoryOptionsForTypeFilter();
    final typeLabel = switch (_typeFilter) {
      _TxTypeFilter.all => 'All types',
      _TxTypeFilter.income => 'Income',
      _TxTypeFilter.expense => 'Expense',
    };

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sheetOn = Theme.of(ctx).colorScheme.onSurface;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text(
                  'Category',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'For: $typeLabel',
                  style: TextStyle(
                    color: sheetOn.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    RadioListTile<String?>(
                      title: const Text('All categories'),
                      value: null,
                      groupValue: _categoryFilterKey,
                      onChanged: (v) {
                        setState(() => _categoryFilterKey = v);
                        Navigator.pop(ctx);
                      },
                    ),
                    if (opts.hasUncategorized)
                      RadioListTile<String?>(
                        title: const Text('Uncategorized'),
                        value: _kUncategorizedCategoryKey,
                        groupValue: _categoryFilterKey,
                        onChanged: (v) {
                          setState(() => _categoryFilterKey = v);
                          Navigator.pop(ctx);
                        },
                      ),
                    for (final name in opts.named)
                      RadioListTile<String?>(
                        title: Text(name),
                        value: name,
                        groupValue: _categoryFilterKey,
                        onChanged: (v) {
                          setState(() => _categoryFilterKey = v);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort by amount',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            RadioListTile<_AmountSort>(
              title: const Text('Default (date)'),
              value: _AmountSort.none,
              groupValue: _amountSort,
              onChanged: (v) {
                setState(() => _amountSort = v ?? _AmountSort.none);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_AmountSort>(
              title: const Text('Highest first'),
              value: _AmountSort.highToLow,
              groupValue: _amountSort,
              onChanged: (v) {
                setState(() => _amountSort = v ?? _AmountSort.highToLow);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_AmountSort>(
              title: const Text('Lowest first'),
              value: _AmountSort.lowToHigh,
              groupValue: _amountSort,
              onChanged: (v) {
                setState(() => _amountSort = v ?? _AmountSort.lowToHigh);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredSubscriptionsList {
    var list = List<Map<String, dynamic>>.from(_subscriptions);
    list = list.where((s) {
      final raw =
          s['next_payment'] ?? s['next_payment_date'] ?? s['created_at'];
      final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
      return _inPeriod(d, _subPeriodMode, _subFocusedMonth, _subFocusedYear);
    }).toList();
    final q = _subSearchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((s) => (s['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }
    switch (_subFilter) {
      case _SubFilter.activeOnly:
        list = list.where((s) => s['is_active'] == true).toList();
        break;
      case _SubFilter.inactiveOnly:
        list = list.where((s) => s['is_active'] == false).toList();
        break;
      case _SubFilter.all:
        break;
    }
    switch (_subSort) {
      case _SubSort.amountHigh:
        list.sort(
          (a, b) =>
              _readAmount(b['amount']).compareTo(_readAmount(a['amount'])),
        );
        break;
      case _SubSort.amountLow:
        list.sort(
          (a, b) =>
              _readAmount(a['amount']).compareTo(_readAmount(b['amount'])),
        );
        break;
      case _SubSort.nameAz:
        list.sort(
          (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ),
        );
        break;
      case _SubSort.none:
        break;
    }
    return list;
  }

  /// Relative renewal label under subscription price (calendar days).
  ({String? text, Color color}) _subscriptionRenewalLine(
    Map<String, dynamic> s,
  ) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final anchor = SubscriptionRenewal.anchorDate(s);
    if (anchor == null) return (text: null, color: cs.onSurface);

    final active = SubscriptionRenewal.isActive(s);
    if (!active) {
      if (anchor.isBefore(today)) {
        return (text: 'Overdue', color: Colors.red.shade700);
      }
    } else if (SubscriptionRenewal.isInvalidOrNonRollingCycle(s) &&
        anchor.isBefore(today)) {
      return (text: 'Overdue', color: Colors.red.shade700);
    }

    final display = SubscriptionRenewal.displayNextRenewal(s);
    if (display == null) return (text: null, color: cs.onSurface);
    final diff = DateTime(
      display.year,
      display.month,
      display.day,
    ).difference(today).inDays;
    if (diff < 0) {
      return (text: 'Overdue', color: Colors.red.shade700);
    }
    if (diff == 0) {
      return (text: 'Today', color: _kSubRenewalWarning);
    }
    if (diff == 1) {
      return (text: 'Tomorrow', color: _kSubRenewalWarning);
    }
    return (text: '${diff}d left', color: cs.onSurface.withValues(alpha: 0.5));
  }

  String _subscriptionSubtitle(Map<String, dynamic> s) {
    final cycle = (s['billing_cycle'] ?? 'monthly').toString().toLowerCase();
    final cycleLabel = switch (cycle) {
      'yearly' => 'Yearly',
      'weekly' => 'Weekly',
      'daily' => 'Daily',
      'custom' => 'Custom',
      _ => 'Monthly',
    };
    final display = SubscriptionRenewal.displayNextRenewal(s);
    final datePart = display != null ? formatGoalDateLong(display) : '—';
    return '$cycleLabel - $datePart';
  }

  Future<void> _openEditSubscription(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    if (id == null || id.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditSubscriptionScreen(
          subscription: Map<String, dynamic>.from(s),
          allTransactions: List<Map<String, dynamic>>.from(_transactions),
          currencyCode: widget.currencyCode,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _updatingSubIds.add(id));
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;
        final fetched = await Supabase.instance.client
            .from('subscriptions')
            .select()
            .eq('id', id)
            .eq('user_id', user.id)
            .maybeSingle();
        if (fetched != null && mounted) {
          final fresh = Map<String, dynamic>.from(fetched as Map);
          setState(() {
            final idx = _subscriptions.indexWhere(
              (e) => e['id']?.toString() == id,
            );
            if (idx >= 0) _subscriptions[idx] = fresh;
          });
        }
      } finally {
        if (mounted) setState(() => _updatingSubIds.remove(id));
      }
    }
  }

  void _showSubFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Filter',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            RadioListTile<_SubFilter>(
              title: const Text('All'),
              value: _SubFilter.all,
              groupValue: _subFilter,
              onChanged: (v) {
                setState(() => _subFilter = v ?? _SubFilter.all);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_SubFilter>(
              title: const Text('Active only'),
              value: _SubFilter.activeOnly,
              groupValue: _subFilter,
              onChanged: (v) {
                setState(() => _subFilter = v ?? _SubFilter.activeOnly);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_SubFilter>(
              title: const Text('Inactive only'),
              value: _SubFilter.inactiveOnly,
              groupValue: _subFilter,
              onChanged: (v) {
                setState(() => _subFilter = v ?? _SubFilter.inactiveOnly);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSubSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            RadioListTile<_SubSort>(
              title: const Text('Default'),
              value: _SubSort.none,
              groupValue: _subSort,
              onChanged: (v) {
                setState(() => _subSort = v ?? _SubSort.none);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_SubSort>(
              title: const Text('Amount (high to low)'),
              value: _SubSort.amountHigh,
              groupValue: _subSort,
              onChanged: (v) {
                setState(() => _subSort = v ?? _SubSort.amountHigh);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_SubSort>(
              title: const Text('Amount (low to high)'),
              value: _SubSort.amountLow,
              groupValue: _subSort,
              onChanged: (v) {
                setState(() => _subSort = v ?? _SubSort.amountLow);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_SubSort>(
              title: const Text('Name (A–Z)'),
              value: _SubSort.nameAz,
              groupValue: _subSort,
              onChanged: (v) {
                setState(() => _subSort = v ?? _SubSort.nameAz);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _subscriptionSquircleIcon(Map<String, dynamic> s) {
    final resolved = InfaqSubscriptionIconStorage.resolveSubscriptionIconUrl(
      Supabase.instance.client,
      iconKey: s['icon_key']?.toString(),
      iconUrl: s['icon_url']?.toString(),
    );
    final cs = Theme.of(context).colorScheme;
    final placeholderIconColor = Color.lerp(
      cs.onSurfaceVariant,
      cs.primary,
      0.35,
    )!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        color: Color.lerp(
          cs.primaryContainer,
          cs.surface,
          Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.2,
        )!,
        child: resolved != null && resolved.isNotEmpty
            ? Image.network(
                resolved,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.subscriptions_outlined,
                  color: placeholderIconColor,
                ),
              )
            : Icon(Icons.subscriptions_outlined, color: placeholderIconColor),
      ),
    );
  }

  Widget _buildSubscriptionsTab() {
    final listBg = Theme.of(context).colorScheme.surface;
    if (_loadingSub) {
      return ColoredBox(
        color: listBg,
        child: ListView(
          children: [
            SizedBox(height: 120),
            Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }
    if (_subscriptions.isEmpty) {
      return ColoredBox(
        color: listBg,
        child: ListView(
          children: [
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Text(
                    'No subscriptions yet',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => AddSubscriptionScreen(
                            currencyCode: widget.currencyCode,
                          ),
                        ),
                      );
                      if (ok == true && mounted) await _loadSubscriptions();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: const Text('Add subscription'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final list = _filteredSubscriptionsList;

    return ColoredBox(
      color: listBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        children: [
          _SearchFilterBar(
            searchHint: 'Search',
            query: _subSearchQuery,
            onQueryChanged: (v) => setState(() => _subSearchQuery = v),
            onFilter: _showSubFilterSheet,
            onSort: _showSubSortSheet,
            showTypeButton: false,
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No subscriptions match your search or filters.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            )
          else
            for (final s in list)
              _animatedListItem(
                keyId: 'sub-${s['id']}-${s.hashCode}',
                child: _wrapListCardExit(
                  exiting: _removingSubIds.contains(s['id']?.toString()),
                  child: _buildSubscriptionDismissibleCard(
                    s,
                    isBusy:
                        _deletingSubIds.contains(s['id']?.toString()) ||
                        _updatingSubIds.contains(s['id']?.toString()),
                    selectionMode: _subSelectMode,
                    selected: _selectedSubIds.contains(s['id']?.toString()),
                    onLongPress: () =>
                        _onSubscriptionLongPress(s['id']?.toString() ?? ''),
                    onToggleSelect: () =>
                        _toggleSubscriptionSelect(s['id']?.toString() ?? ''),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionDismissibleCard(
    Map<String, dynamic> s, {
    required bool isBusy,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onLongPress,
    VoidCallback? onToggleSelect,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showSelected = selectionMode && selected;
    final selectedTint = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    final cardColor = showSelected
        ? Color.alphaBlend(selectedTint, cs.surfaceContainerLow)
        : cs.surfaceContainerLow;
    final sid = s['id']?.toString() ?? s.hashCode.toString();
    final dimInactive = s['is_active'] == false;
    final renewal = _subscriptionRenewalLine(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('sub-$sid'),
        direction: isBusy || selectionMode
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        confirmDismiss: (_) => _confirmDeleteSubscription(s),
        child: IgnorePointer(
          ignoring: isBusy,
          child: Opacity(
            opacity: dimInactive ? 0.55 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: showSelected ? cs.primary : Colors.transparent,
                  width: showSelected ? 2 : 0,
                ),
              ),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                elevation: 0,
                shadowColor: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: selectionMode
                      ? () => onToggleSelect?.call()
                      : () => _openEditSubscription(s),
                  onLongPress: selectionMode || onLongPress == null
                      ? null
                      : onLongPress,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(
                            alpha:
                                Theme.of(context).brightness == Brightness.dark
                                ? 0.35
                                : 0.07,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                      border: Border.all(
                        color: cs.outline.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.35
                              : 0.12,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _subscriptionSquircleIcon(s),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name']?.toString() ?? 'Subscription',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _subscriptionSubtitle(s),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isBusy)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _fmtMoney(_readAmount(s['amount'])),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  if (renewal.text != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      renewal.text!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10.5,
                                        height: 1.1,
                                        color: renewal.color,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteSubscription(Map<String, dynamic> s) async {
    final id = s['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subscription?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    setState(() => _deletingSubIds.add(id));
    try {
      await Supabase.instance.client
          .from('subscriptions')
          .delete()
          .eq('id', id)
          .eq('user_id', user.id);
      if (mounted) {
        setState(() {
          _deletingSubIds.remove(id);
          _subscriptions.removeWhere((e) => e['id']?.toString() == id);
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _deletingSubIds.remove(id));
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not delete subscription right now. Please try again.',
        );
      }
      return false;
    }
  }

  List<Map<String, dynamic>> get _filteredGoalsList {
    var list = List<Map<String, dynamic>>.from(_goals);
    list = list.where((g) {
      final raw = g['deadline'] ?? g['created_at'];
      final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
      return _inPeriod(d, _goalPeriodMode, _goalFocusedMonth, _goalFocusedYear);
    }).toList();
    final q = _goalSearchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((g) => (g['title'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }
    switch (_goalSort) {
      case _GoalSort.targetHighToLow:
        list.sort(
          (a, b) => _readAmount(
            b['target_amount'],
          ).compareTo(_readAmount(a['target_amount'])),
        );
        break;
      case _GoalSort.targetLowToHigh:
        list.sort(
          (a, b) => _readAmount(
            a['target_amount'],
          ).compareTo(_readAmount(b['target_amount'])),
        );
        break;
      case _GoalSort.none:
        break;
    }
    return list;
  }

  ({double saved, double targets}) _goalsAggregateTotals() {
    var saved = 0.0;
    var targets = 0.0;
    for (final g in _goals) {
      saved += _readAmount(g['current_amount']);
      targets += _readAmount(g['target_amount']);
    }
    return (saved: saved, targets: targets);
  }

  String _goalsHorizonLine() {
    if (_goals.isEmpty) return '';
    DateTime? latest;
    for (final g in _goals) {
      final raw = g['deadline'];
      final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
      if (d == null) continue;
      if (latest == null || d.isAfter(latest)) latest = d;
    }
    if (latest == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(latest.year, latest.month, latest.day);
    if (!end.isAfter(today)) return 'Target window ended';
    var months = (end.year - today.year) * 12 + end.month - today.month;
    if (end.day < today.day) months -= 1;
    if (months < 0) months = 0;
    final y = months ~/ 12;
    final m = months % 12;
    if (y > 0 && m > 0) {
      return '$y ${y == 1 ? 'year' : 'years'} $m ${m == 1 ? 'month' : 'months'}';
    }
    if (y > 0) return '$y ${y == 1 ? 'year' : 'years'}';
    return '$m ${m == 1 ? 'month' : 'months'}';
  }

  String _formatGoalDeadlineShort(dynamic raw) {
    final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
    if (d == null) return '—';
    const months = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    return '${months[d.month - 1]} ${d.day} ${d.year}';
  }

  void _showGoalSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Sort by target amount',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            RadioListTile<_GoalSort>(
              title: const Text('Default (newest first)'),
              value: _GoalSort.none,
              groupValue: _goalSort,
              onChanged: (v) {
                setState(() => _goalSort = v ?? _GoalSort.none);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_GoalSort>(
              title: const Text('High to low'),
              value: _GoalSort.targetHighToLow,
              groupValue: _goalSort,
              onChanged: (v) {
                setState(() => _goalSort = v ?? _GoalSort.targetHighToLow);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<_GoalSort>(
              title: const Text('Low to high'),
              value: _GoalSort.targetLowToHigh,
              groupValue: _goalSort,
              onChanged: (v) {
                setState(() => _goalSort = v ?? _GoalSort.targetLowToHigh);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalDismissibleCard(
    Map<String, dynamic> g, {
    required bool isBusy,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onLongPress,
    VoidCallback? onToggleSelect,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showSelected = selectionMode && selected;
    final selectedTint = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    final cardColor = showSelected
        ? Color.alphaBlend(selectedTint, cs.surfaceContainerLow)
        : cs.surfaceContainerLow;
    final idStr = g['id']?.toString();
    final gid = idStr ?? g.hashCode.toString();
    final title = g['title']?.toString() ?? 'Goal';
    final current = _readAmount(g['current_amount']);
    final target = _readAmount(g['target_amount']);
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final deadline = _formatGoalDeadlineShort(g['deadline']);
    final iconCp = idStr != null ? _goalIconCodePoints[idStr] : null;
    final goalIcon = iconCp != null
        ? IconData(iconCp, fontFamily: 'MaterialIcons')
        : Icons.menu_book_rounded;
    final goalColor = idStr != null
        ? (_goalIconColors[idStr] ?? categoryDisplayColor(title))
        : categoryDisplayColor(title);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('goal-$gid'),
        direction: isBusy || selectionMode
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        confirmDismiss: (_) => _confirmDeleteGoal(g),
        child: IgnorePointer(
          ignoring: isBusy,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: showSelected ? cs.primary : Colors.transparent,
                width: showSelected ? 2 : 0,
              ),
            ),
            child: Material(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              elevation: 0,
              shadowColor: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onLongPress: selectionMode || onLongPress == null
                    ? null
                    : onLongPress,
                onTap: () async {
                  if (selectionMode) {
                    onToggleSelect?.call();
                    return;
                  }
                  if (idStr == null || idStr.isEmpty) return;
                  final changed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => EditGoalScreen(
                        goal: Map<String, dynamic>.from(g),
                        currencyCode: widget.currencyCode,
                      ),
                    ),
                  );
                  if (changed == true && mounted) {
                    setState(() => _updatingGoalIds.add(idStr));
                    try {
                      final user = Supabase.instance.client.auth.currentUser;
                      if (user == null) return;
                      final fetched = await Supabase.instance.client
                          .from('goals')
                          .select()
                          .eq('id', idStr)
                          .eq('created_by', user.id)
                          .maybeSingle();
                      if (fetched != null && mounted) {
                        final fresh = Map<String, dynamic>.from(fetched as Map);
                        setState(() {
                          final idx = _goals.indexWhere(
                            (e) => e['id']?.toString() == idStr,
                          );
                          if (idx >= 0) _goals[idx] = fresh;
                        });
                        unawaited(_syncGoalIconsFromPrefs());
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _updatingGoalIds.remove(idStr));
                      }
                    }
                  }
                },
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(
                          alpha: isDark ? 0.25 : 0.07,
                        ),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    border: Border.all(
                      color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: goalColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: goalColor.withValues(alpha: 0.38),
                                  width: 1,
                                ),
                              ),
                              child: Icon(goalIcon, color: goalColor, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_fmtMoney(current)} · $deadline',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                _fmtMoney(target),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: cs.surfaceContainerHighest,
                            color: goalColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalsTab() {
    final cs = Theme.of(context).colorScheme;
    if (_loadingGoals) {
      return ListView(
        children: [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: cs.primary)),
        ],
      );
    }
    if (_goals.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text(
                  'No goals yet',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            AddGoalScreen(currencyCode: widget.currencyCode),
                      ),
                    );
                    if (ok == true && mounted) {
                      await _loadGoals();
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: cs.primary),
                  child: const Text('Add goal'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final totals = _goalsAggregateTotals();
    final list = _filteredGoalsList;
    final remaining = totals.targets - totals.saved;
    final progress = totals.targets > 0
        ? (totals.saved / totals.targets).clamp(0.0, 1.0)
        : 0.0;
    final horizon = _goalsHorizonLine();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _GoalsSummaryCard(
          totalSaved: totals.saved,
          totalTargets: totals.targets,
          progress: progress,
          format: _fmtMoney,
          remainingMoneyLabel: remaining >= 0
              ? '${_fmtMoney(remaining)} remaining'
              : '${_fmtMoney(-remaining)} over target',
          horizonLine: horizon,
        ),
        const SizedBox(height: 14),
        _SearchFilterBar(
          searchHint: 'Search',
          query: _goalSearchQuery,
          onQueryChanged: (v) => setState(() => _goalSearchQuery = v),
          onFilter: () {},
          onSort: _showGoalSortSheet,
          showTypeButton: false,
          showFilterButton: false,
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No goals match your search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55)),
            ),
          )
        else
          for (final g in list)
            _animatedListItem(
              keyId: 'goal-${g['id']}-${g.hashCode}',
              child: _wrapListCardExit(
                exiting: _removingGoalIds.contains(g['id']?.toString()),
                child: _buildGoalDismissibleCard(
                  g,
                  isBusy:
                      _deletingGoalIds.contains(g['id']?.toString()) ||
                      _updatingGoalIds.contains(g['id']?.toString()),
                  selectionMode: _goalSelectMode,
                  selected: _selectedGoalIds.contains(g['id']?.toString()),
                  onLongPress: () =>
                      _onGoalLongPress(g['id']?.toString() ?? ''),
                  onToggleSelect: () =>
                      _toggleGoalSelect(g['id']?.toString() ?? ''),
                ),
              ),
            ),
      ],
    );
  }

  Future<bool> _confirmDeleteGoal(Map<String, dynamic> g) async {
    final id = g['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    setState(() => _deletingGoalIds.add(id));
    try {
      await Supabase.instance.client
          .from('goals')
          .delete()
          .eq('id', id)
          .eq('created_by', user.id);
      if (mounted) {
        setState(() {
          _deletingGoalIds.remove(id);
          _goals.removeWhere((e) => e['id']?.toString() == id);
          _goalIconCodePoints.remove(id);
          _goalIconColors.remove(id);
        });
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => _deletingGoalIds.remove(id));
      if (mounted) {
        showInfaqSnack(
          context,
          'Could not delete goal right now. Please try again.',
        );
      }
      return false;
    }
  }
}

class _MgmtPillTabs extends StatelessWidget {
  const _MgmtPillTabs({required this.selected, required this.onChanged});

  final _MgmtMainTab selected;
  final void Function(_MgmtMainTab) onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    /// Same shell as [AddTransactionScreen] Expense / Income toggle.
    Widget seg(String label, _MgmtMainTab tab) {
      final on = selected == tab;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(tab),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: on ? kInfaqPrimaryGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.12,
                    letterSpacing: -0.12,
                    color: on
                        ? Colors.white
                        : (isDark
                              ? cs.onSurface.withValues(alpha: 0.65)
                              : Colors.black.withValues(alpha: 0.65)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          seg('Transactions', _MgmtMainTab.transactions),
          const SizedBox(width: 4),
          seg('Subscriptions', _MgmtMainTab.subscriptions),
          const SizedBox(width: 4),
          seg('Goals', _MgmtMainTab.goals),
        ],
      ),
    );
  }
}

class _GoalsSummaryCard extends StatelessWidget {
  const _GoalsSummaryCard({
    required this.totalSaved,
    required this.totalTargets,
    required this.progress,
    required this.format,
    required this.remainingMoneyLabel,
    required this.horizonLine,
  });

  final double totalSaved;
  final double totalTargets;
  final double progress;
  final String Function(double) format;
  final String remainingMoneyLabel;
  final String horizonLine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subLine = horizonLine.isEmpty
        ? remainingMoneyLabel
        : '$remainingMoneyLabel · $horizonLine';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.22 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total saved',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        format(totalSaved),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                child: SizedBox(
                  height: 40,
                  child: Center(
                    child: Container(
                      width: 1,
                      height: 36,
                      color: cs.outline.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Goals',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        format(totalTargets),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: totalTargets > 0 ? progress.clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subLine,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFilterBar extends StatelessWidget {
  const _SearchFilterBar({
    required this.searchHint,
    required this.query,
    required this.onQueryChanged,
    this.onType,
    required this.onFilter,
    required this.onSort,
    this.showTypeButton = true,
    this.showFilterButton = true,
  });

  final String searchHint;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onType;
  final VoidCallback onFilter;
  final VoidCallback onSort;
  final bool showTypeButton;
  final bool showFilterButton;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.22 : 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 22, color: cs.primary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              style: TextStyle(color: cs.onSurface),
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: searchHint,
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.42),
                ),
              ),
            ),
          ),
          if (showTypeButton && onType != null)
            TextButton(
              onPressed: onType,
              child: Text(
                'Type',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontSize: 13,
                ),
              ),
            ),
          if (showFilterButton)
            TextButton(
              onPressed: onFilter,
              child: Text(
                'Filter',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontSize: 13,
                ),
              ),
            ),
          TextButton(
            onPressed: onSort,
            child: Text(
              'Sort',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MgmtTxTile extends StatefulWidget {
  const _MgmtTxTile({
    required this.data,
    required this.format,
    required this.onTap,
    required this.confirmDismissDelete,
    required this.isBusy,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  final Map<String, dynamic> data;
  final String Function(double) format;
  final VoidCallback onTap;
  final Future<bool> Function() confirmDismissDelete;
  final bool isBusy;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  @override
  State<_MgmtTxTile> createState() => _MgmtTxTileState();
}

class _MgmtTxTileState extends State<_MgmtTxTile> {
  static double _parseAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  static bool _isExpense(Map<String, dynamic> data, double amount) {
    final catMap = data['categories'];
    String? catType;
    if (catMap is Map) catType = catMap['type']?.toString().toLowerCase();
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

  String _prettyDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yest = today.subtract(const Duration(days: 1));
    final asDay = DateTime(d.year, d.month, d.day);
    if (asDay == today) return 'today';
    if (asDay == yest) return 'yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showSelected = widget.selectionMode && widget.selected;
    final selectedTint = cs.primary.withValues(alpha: isDark ? 0.18 : 0.1);
    final cardColor = showSelected
        ? Color.alphaBlend(selectedTint, cs.surfaceContainerLow)
        : cs.surfaceContainerLow;
    final amountMaxWidth = (MediaQuery.sizeOf(context).width * 0.28).clamp(
      90.0,
      132.0,
    );
    final title =
        (widget.data['description'] ?? widget.data['title'] ?? 'Transaction')
            .toString();
    var category = (widget.data['category'] ?? '').toString();
    final catMap = widget.data['categories'];
    if (catMap is Map && (catMap['name']?.toString().isNotEmpty ?? false)) {
      category = catMap['name'].toString();
    }
    // Use the transaction date selected by user; fallback for old rows.
    final createdRaw = widget.data['date'] ?? widget.data['created_at'];
    final d = createdRaw != null
        ? DateTime.tryParse(createdRaw.toString())
        : null;
    final subtitle = [
      if (category.isNotEmpty) category,
      if (d != null) _prettyDate(d),
    ].join(' - ');
    final catId =
        (catMap is Map ? catMap['id'] : null)?.toString() ??
        widget.data['category_id']?.toString();
    final savedCategoryColor = catMap is Map
        ? (catMap['color'] ?? catMap['color_value'] ?? catMap['hex_color'])
        : null;
    final categoryLabel = category.isEmpty ? title : category;
    final amount = _parseAmount(widget.data['amount']);
    final isExpense = _isExpense(widget.data, amount);
    final iconColor = categoryDisplayColor(
      categoryLabel,
      categoryId: catId,
      savedColor: savedCategoryColor,
    );
    final iconBg = categoryDisplayTintFor(
      categoryLabel,
      categoryId: catId,
      savedColor: savedCategoryColor,
    );
    final iconBgDark = categoryDisplayDarkContainerFor(
      categoryLabel,
      categoryId: catId,
      savedColor: savedCategoryColor,
      depth: 0.84,
    );
    final categoryType = catMap is Map
        ? (catMap['type']?.toString() ?? '')
        : '';
    final categoryIcon = categoryIconForDisplay(
      iconKey: catMap is Map ? catMap['icon_key']?.toString() : null,
      name: categoryLabel,
      type: categoryType.isEmpty
          ? (isExpense ? 'expense' : 'income')
          : categoryType,
      categoryId: catId,
    );

    Color? leafColorFor(String? value) {
      switch (value?.toLowerCase().trim()) {
        case 'green':
          return const Color(0xFF2E7D32);
        case 'orange':
          return const Color(0xFFF57C00);
        case 'red':
          return const Color(0xFFC62828);
        default:
          return null;
      }
    }

    final leafColor = leafColorFor(widget.data['leaf_color']?.toString());
    final leafTitle = widget.data['leaf_title']?.toString().trim();
    final leafMessage = widget.data['leaf_message']?.toString().trim();
    final showLeaf = isExpense && leafColor != null;

    void showLeafTooltip(Offset anchor) {
      if ((leafTitle == null || leafTitle.isEmpty) &&
          (leafMessage == null || leafMessage.isEmpty)) {
        return;
      }
      _MgmtLeafTooltipOverlay.show(
        context: context,
        anchorGlobalPosition: anchor,
        title: leafTitle?.isNotEmpty == true
            ? leafTitle!
            : 'Environmental impact',
        message: leafMessage?.isNotEmpty == true
            ? leafMessage!
            : 'This transaction has an environmental impact rating.',
      );
    }

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: showSelected ? cs.primary : Colors.transparent,
          width: showSelected ? 2 : 0,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.16
                  : 0.08,
            ),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            _MgmtLeafTooltipOverlay.hide();
            if (widget.selectionMode) {
              widget.onToggleSelect?.call();
            } else {
              widget.onTap();
            }
          },
          onLongPress: widget.selectionMode || widget.onLongPress == null
              ? null
              : () {
                  _MgmtLeafTooltipOverlay.hide();
                  widget.onLongPress!();
                },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? iconBgDark : iconBg.withValues(alpha: 1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? iconColor.withValues(alpha: 0.38)
                          : iconColor.withValues(alpha: 0.12),
                      width: 1,
                    ),
                  ),
                  child: Icon(categoryIcon, size: 22, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.25,
                          letterSpacing: -0.1,
                          color: cs.onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (showLeaf && !widget.selectionMode) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) =>
                              showLeafTooltip(details.globalPosition),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Icon(
                              Icons.eco_outlined,
                              size: 15,
                              color: leafColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: amountMaxWidth),
                        child: Text(
                          isExpense
                              ? '-${widget.format(amount.abs())}'
                              : '+${widget.format(amount.abs())}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            height: 1.1,
                            letterSpacing: -0.15,
                            color: isExpense ? kInfaqExpenseRed : cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final id = widget.data['id']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key('tx-$id-${title.hashCode}'),
        direction: widget.isBusy || widget.selectionMode
            ? DismissDirection.none
            : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        confirmDismiss: (_) {
          _MgmtLeafTooltipOverlay.hide();
          return widget.confirmDismissDelete();
        },
        child: IgnorePointer(ignoring: widget.isBusy, child: tile),
      ),
    );
  }
}

class _MgmtLeafTooltipOverlay {
  static OverlayEntry? _entry;
  static void hide() {
    _entry?.remove();
    _entry = null;
  }

  static void show({
    required BuildContext context,
    required Offset anchorGlobalPosition,
    required String title,
    required String message,
  }) {
    hide();
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final screen = MediaQuery.sizeOf(context);
        const maxWidth = 260.0;
        const margin = 12.0;
        final width = (screen.width - margin * 2).clamp(180.0, maxWidth);
        final left = (anchorGlobalPosition.dx - width / 2).clamp(
          margin,
          screen.width - width - margin,
        );
        final showAbove = anchorGlobalPosition.dy > 180;
        final top = showAbove
            ? anchorGlobalPosition.dy - 152
            : anchorGlobalPosition.dy + 14;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: hide,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: left,
              top: top.clamp(12.0, screen.height - 164),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_entry!);
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/profile/subscription_icon_storage.dart';
import 'package:infaq/screens/add_goal_screen.dart';
import 'package:infaq/screens/add_subscription_screen.dart';
import 'package:infaq/screens/edit_goal_screen.dart';
import 'package:infaq/screens/edit_subscription_screen.dart';
import 'package:infaq/subscription/subscription_analytics.dart';
import 'package:infaq/ui/infaq_service_form_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kMgmtMint = Color(0xFFE6F4EA);
const Color _kSubTabCream = Color(0xFFFFF6E8);
const Color _kGoalsHeaderCyan = Color(0xFFE8F4FA);

enum _SubFilter { all, activeOnly, inactiveOnly }

enum _SubSort { none, amountHigh, amountLow, nameAz }

enum _MgmtMainTab { transactions, subscriptions, goals }

enum _PeriodMode { allTime, month, year }

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
  });

  final String? currencyCode;
  final double initialMonthlyBudget;
  final int transactionsListRefreshToken;
  final VoidCallback onDataChanged;
  final void Function(Map<String, dynamic> row) onEditTransaction;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  _MgmtMainTab _mainTab = _MgmtMainTab.transactions;

  /// Spending budget shown in summary (persisted as `users.Balance` when edited).
  double _monthlyBudget = 0;

  _PeriodMode _periodMode = _PeriodMode.month;
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _focusedYear = DateTime.now().year;

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

  bool _loadingTx = true;
  bool _loadingSub = false;
  bool _loadingGoals = false;

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
    if (oldWidget.transactionsListRefreshToken != widget.transactionsListRefreshToken) {
      _loadTransactions();
      _loadSubscriptions();
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
        res = await Supabase.instance.client
            .from('transactions')
            .select('id, amount, description, date, created_at, category_id, categories(name, type)')
            .eq('user_id', user.id)
            .order('date', ascending: false)
            .limit(500);
      } catch (_) {
        res = await Supabase.instance.client
            .from('transactions')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(500);
      }
      final list = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      final list = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _subscriptions = list;
        _loadingSub = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSub = false);
    }
  }

  Future<void> _loadGoals() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _loadingGoals = true);
    try {
      final res =
          await Supabase.instance.client.from('goals').select().eq('created_by', user.id).order('created_at', ascending: false);
      final list = (res as List<dynamic>).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _goals = list;
        _loadingGoals = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingGoals = false);
    }
  }

  void _onMainTabChanged(_MgmtMainTab t) {
    setState(() => _mainTab = t);
    if (t == _MgmtMainTab.subscriptions && _subscriptions.isEmpty && !_loadingSub) _loadSubscriptions();
    if (t == _MgmtMainTab.goals && _goals.isEmpty && !_loadingGoals) _loadGoals();
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
    final legacyType = (data['type'] ?? data['transaction_type'] ?? '').toString().toLowerCase();
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
    final legacy = (r['category'] ?? r['category_name'] ?? '').toString().trim();
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
  ({List<String> named, bool hasUncategorized}) _categoryOptionsForTypeFilter() {
    final named = <String>{};
    var hasUncategorized = false;
    for (final r in _transactions) {
      final d = _txDate(r);
      if (!_inPeriod(d)) continue;
      if (!_rowMatchesTypeFilter(r)) continue;
      final label = _categoryDisplayName(r);
      if (label.isEmpty) {
        hasUncategorized = true;
      } else {
        named.add(label);
      }
    }
    final list = named.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return (named: list, hasUncategorized: hasUncategorized);
  }

  bool _inPeriod(DateTime? d) {
    if (d == null) return false;
    switch (_periodMode) {
      case _PeriodMode.allTime:
        return true;
      case _PeriodMode.month:
        return d.year == _focusedMonth.year && d.month == _focusedMonth.month;
      case _PeriodMode.year:
        return d.year == _focusedYear;
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    var list = List<Map<String, dynamic>>.from(_transactions);
    list = list.where((r) {
      final d = _txDate(r);
      return _inPeriod(d);
    }).toList();

    if (_typeFilter == _TxTypeFilter.income) {
      list = list.where((r) => !_isExpenseRow(r, _readAmount(r['amount']))).toList();
    } else if (_typeFilter == _TxTypeFilter.expense) {
      list = list.where((r) => _isExpenseRow(r, _readAmount(r['amount']))).toList();
    }

    if (_categoryFilterKey != null) {
      list = list.where((r) {
        final name = _categoryDisplayName(r);
        if (_categoryFilterKey == _kUncategorizedCategoryKey) return name.isEmpty;
        return name == _categoryFilterKey;
      }).toList();
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) {
        final desc = (r['description'] ?? '').toString().toLowerCase();
        final cat = r['categories'];
        final catName = cat is Map ? (cat['name'] ?? '').toString().toLowerCase() : '';
        return desc.contains(q) || catName.contains(q);
      }).toList();
    }

    if (_amountSort == _AmountSort.highToLow) {
      list.sort((a, b) => _readAmount(b['amount']).abs().compareTo(_readAmount(a['amount']).abs()));
    } else if (_amountSort == _AmountSort.lowToHigh) {
      list.sort((a, b) => _readAmount(a['amount']).abs().compareTo(_readAmount(b['amount']).abs()));
    }

    return list;
  }

  double _totalSpentInPeriod() {
    var sum = 0.0;
    for (final r in _filteredTransactions.where((x) => _isExpenseRow(x, _readAmount(x['amount'])))) {
      sum += _readAmount(r['amount']).abs();
    }
    return sum;
  }

  String _periodTitle() {
    switch (_periodMode) {
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
          'December'
        ];
        return '${months[_focusedMonth.month - 1]} ${_focusedMonth.year}';
      case _PeriodMode.year:
        return '$_focusedYear';
    }
  }

  Future<void> _pickPeriodMode() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Show transactions', style: TextStyle(fontWeight: FontWeight.w800))),
              ListTile(
                title: const Text('All time'),
                onTap: () {
                  setState(() => _periodMode = _PeriodMode.allTime);
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                title: const Text('Single month'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _focusedMonth,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDatePickerMode: DatePickerMode.year,
                    helpText: 'Pick any day in the month',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _periodMode = _PeriodMode.month;
                      _focusedMonth = DateTime(picked.year, picked.month);
                    });
                  }
                },
              ),
              ListTile(
                title: const Text('Whole year'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final y = await showDialog<int>(
                    context: context,
                    builder: (c) {
                      var year = _focusedYear;
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
                                Text('$year', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                IconButton(
                                  onPressed: () => setS(() => year += 1),
                                  icon: const Icon(Icons.add),
                                ),
                              ],
                            );
                          },
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
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
                      _periodMode = _PeriodMode.year;
                      _focusedYear = y;
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
      _periodMode = _PeriodMode.month;
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  void _shiftYear(int delta) {
    setState(() {
      _periodMode = _PeriodMode.year;
      _focusedYear += delta;
    });
  }

  Future<void> _editBudget() async {
    final ctrl = TextEditingController(text: _monthlyBudget > 0 ? _monthlyBudget.toStringAsFixed(_monthlyBudget % 1 == 0 ? 0 : 2) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: 'e.g. 1000', suffixText: widget.currencyCode ?? ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
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
      await Supabase.instance.client.from('users').update({'Balance': v}).eq('id', user.id);
      if (!mounted) return;
      setState(() => _monthlyBudget = v);
      widget.onDataChanged();
      showInfaqSnack(context, 'Budget updated');
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not save budget: $e');
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
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.72)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id).eq('user_id', user.id);
      if (!mounted) return false;
      await _loadTransactions();
      widget.onDataChanged();
      if (mounted) showInfaqSnack(context, 'Transaction deleted');
      return false;
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final spent = _totalSpentInPeriod();
    final budget = _monthlyBudget;
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final remaining = budget - spent;

    final Color headerTint;
    switch (_mainTab) {
      case _MgmtMainTab.subscriptions:
        headerTint = isDark ? Color.lerp(cs.tertiaryContainer, cs.surface, 0.35)! : _kSubTabCream;
      case _MgmtMainTab.goals:
        headerTint = isDark ? Color.lerp(cs.secondaryContainer, cs.surface, 0.4)! : _kGoalsHeaderCyan;
      case _MgmtMainTab.transactions:
        headerTint = isDark ? Color.lerp(cs.primaryContainer, cs.surface, 0.35)! : _kMgmtMint;
    }

    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: headerTint,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Management',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.primary),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _pickPeriodMode,
                          icon: Icon(Icons.schedule_rounded, color: cs.primary),
                          tooltip: 'Date range',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
              child: _mainTab == _MgmtMainTab.transactions
                  ? _buildTransactionsTab(
                      spent: spent,
                      budget: budget,
                      progress: progress,
                      remaining: remaining,
                    )
                  : _mainTab == _MgmtMainTab.subscriptions
                      ? _buildSubscriptionsTab()
                      : _buildGoalsTab(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab({
    required double spent,
    required double budget,
    required double progress,
    required double remaining,
  }) {
    if (_loadingTx) {
      return ListView(children: [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      ]);
    }

    final list = _filteredTransactions;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _SummaryCard(
          periodTitle: _periodTitle(),
          onPrev: _periodMode == _PeriodMode.month
              ? () => _shiftMonth(-1)
              : _periodMode == _PeriodMode.year
                  ? () => _shiftYear(-1)
                  : null,
          onNext: _periodMode == _PeriodMode.month
              ? () => _shiftMonth(1)
              : _periodMode == _PeriodMode.year
                  ? () => _shiftYear(1)
                  : null,
          onEditBudget: _editBudget,
          spent: spent,
          budget: budget,
          progress: progress,
          remainingLabel: budget > 0
              ? (remaining >= 0 ? '${_fmtMoney(remaining)} remaining' : 'Over by ${_fmtMoney(remaining.abs())}')
              : 'Set a budget to track spending',
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
            ),
          )
        else
          for (final t in list)
            _MgmtTxTile(
              data: t,
              format: _fmtMoney,
              onTap: () => widget.onEditTransaction(t),
              confirmDismissDelete: () => _deleteTransaction(t),
            ),
      ],
    );
  }

  void _showTypeSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Type', style: TextStyle(fontWeight: FontWeight.w800))),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final sheetOn = Theme.of(ctx).colorScheme.onSurface;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Category', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('For: $typeLabel', style: TextStyle(color: sheetOn.withValues(alpha: 0.55), fontSize: 13)),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Sort by amount', style: TextStyle(fontWeight: FontWeight.w800))),
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
    final q = _subSearchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) => (s['name'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    switch (_subFilter) {
      case _SubFilter.activeOnly:
        list = list.where((s) => parseSubscriptionIsActive(s['is_active'])).toList();
        break;
      case _SubFilter.inactiveOnly:
        list = list.where((s) => !parseSubscriptionIsActive(s['is_active'])).toList();
        break;
      case _SubFilter.all:
        break;
    }
    switch (_subSort) {
      case _SubSort.amountHigh:
        list.sort((a, b) => _readAmount(b['amount']).compareTo(_readAmount(a['amount'])));
        break;
      case _SubSort.amountLow:
        list.sort((a, b) => _readAmount(a['amount']).compareTo(_readAmount(b['amount'])));
        break;
      case _SubSort.nameAz:
        list.sort(
          (a, b) =>
              (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase()),
        );
        break;
      case _SubSort.none:
        break;
    }
    return list;
  }

  String _subscriptionSubtitle(Map<String, dynamic> s) {
    final cycle = (s['billing_cycle'] ?? 'monthly').toString().toLowerCase();
    final cycleLabel = cycle == 'yearly' ? 'Yearly' : 'Monthly';
    final raw = s['next_payment'] ?? s['next_payment_date'];
    final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
    final datePart = d != null ? formatGoalDateLong(d) : '—';
    return '$cycleLabel - $datePart';
  }

  Future<void> _openEditSubscription(Map<String, dynamic> s) async {
    if (_loadingTx) await _loadTransactions();
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
      await _loadSubscriptions();
      widget.onDataChanged();
    }
  }

  void _showSubFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Filter', style: TextStyle(fontWeight: FontWeight.w800))),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Sort', style: TextStyle(fontWeight: FontWeight.w800))),
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
    final resolved = InfaqSubscriptionIconStorage.resolveDisplayUrl(
      Supabase.instance.client,
      s['icon_url']?.toString(),
    );
    final cs = Theme.of(context).colorScheme;
    final placeholderIconColor = Color.lerp(cs.onSurfaceVariant, cs.primary, 0.35)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 54,
        height: 54,
        color: Color.lerp(cs.primaryContainer, cs.surface, Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.2)!,
        child: resolved != null && resolved.isNotEmpty
            ? Image.network(resolved, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.subscriptions_outlined, color: placeholderIconColor))
            : Icon(Icons.subscriptions_outlined, color: placeholderIconColor),
      ),
    );
  }

  Widget _buildSubscriptionsTab() {
    final listBg = Theme.of(context).colorScheme.surface;
    if (_loadingSub) {
      return ColoredBox(
        color: listBg,
        child: ListView(children: [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        ]),
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
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => AddSubscriptionScreen(currencyCode: widget.currencyCode)),
                      );
                      if (ok == true && mounted) await _loadSubscriptions();
                    },
                    style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
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
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            )
          else
            for (final s in list) _buildSubscriptionDismissibleCard(s),
        ],
      ),
    );
  }

  Widget _buildSubscriptionDismissibleCard(Map<String, dynamic> s) {
    final cs = Theme.of(context).colorScheme;
    final sid = s['id']?.toString() ?? s.hashCode.toString();
    final active = parseSubscriptionIsActive(s['is_active']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('sub-$sid'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
        ),
        confirmDismiss: (_) => _confirmDeleteSubscription(s),
        child: Opacity(
          opacity: active ? 1 : 0.55,
          child: Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            elevation: 0,
            shadowColor: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openEditSubscription(s),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: cs.surfaceContainerLow,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                  border: Border.all(color: cs.outline.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      _subscriptionSquircleIcon(s),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s['name']?.toString() ?? 'Subscription',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: cs.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subscriptionSubtitle(s),
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.55)),
                      ),
                    ],
                        ),
                      ),
                      Text(
                        _fmtMoney(_readAmount(s['amount'])),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
                      ),
                    ],
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    try {
      await Supabase.instance.client.from('subscriptions').delete().eq('id', id).eq('user_id', user.id);
      if (mounted) {
        await _loadSubscriptions();
        widget.onDataChanged();
      }
      return false;
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
      return false;
    }
  }

  List<Map<String, dynamic>> get _filteredGoalsList {
    var list = List<Map<String, dynamic>>.from(_goals);
    final q = _goalSearchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((g) => (g['title'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    switch (_goalSort) {
      case _GoalSort.targetHighToLow:
        list.sort((a, b) => _readAmount(b['target_amount']).compareTo(_readAmount(a['target_amount'])));
        break;
      case _GoalSort.targetLowToHigh:
        list.sort((a, b) => _readAmount(a['target_amount']).compareTo(_readAmount(b['target_amount'])));
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
    if (y > 0 && m > 0) return '$y ${y == 1 ? 'year' : 'years'} $m ${m == 1 ? 'month' : 'months'}';
    if (y > 0) return '$y ${y == 1 ? 'year' : 'years'}';
    return '$m ${m == 1 ? 'month' : 'months'}';
  }

  String _formatGoalDeadlineShort(dynamic raw) {
    final d = raw != null ? DateTime.tryParse(raw.toString()) : null;
    if (d == null) return '—';
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    return '${months[d.month - 1]} ${d.day} ${d.year}';
  }

  Color _accentForGoalTitle(String title) {
    final h = title.hashCode.abs();
    const colors = [
      Color(0xFFFF9F6B),
      Color(0xFF6BB3F0),
      Color(0xFFFF8FB8),
      Color(0xFF7FD8BE),
      Color(0xFFB39DFF),
      Color(0xFFFFB86C),
    ];
    return colors[h % colors.length];
  }

  void _showGoalSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Sort by target amount', style: TextStyle(fontWeight: FontWeight.w800))),
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

  Widget _buildGoalDismissibleCard(Map<String, dynamic> g) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gid = g['id']?.toString() ?? g.hashCode.toString();
    final title = g['title']?.toString() ?? 'Goal';
    final current = _readAmount(g['current_amount']);
    final target = _readAmount(g['target_amount']);
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final accent = _accentForGoalTitle(title);
    final deadline = _formatGoalDeadlineShort(g['deadline']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: ValueKey('goal-$gid'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
        ),
        confirmDismiss: (_) => _confirmDeleteGoal(g),
        child: Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          shadowColor: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              final changed = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => EditGoalScreen(
                    goal: Map<String, dynamic>.from(g),
                    currencyCode: widget.currencyCode,
                  ),
                ),
              );
              if (changed == true && mounted) await _loadGoals();
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: cs.surfaceContainerLow,
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.07),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.12)),
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
                            color: accent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.savings_outlined, color: Colors.white, size: 26),
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
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.onSurface),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_fmtMoney(current)} · $deadline',
                                style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.55)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _fmtMoney(target),
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cs.onSurface),
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
                        color: accent,
                      ),
                    ),
                  ],
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
      return ListView(children: [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: cs.primary)),
      ]);
    }
    if (_goals.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text('No goals yet', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55))),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddGoalScreen(currencyCode: widget.currencyCode)));
                    if (ok == true && mounted) await _loadGoals();
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
    final progress = totals.targets > 0 ? (totals.saved / totals.targets).clamp(0.0, 1.0) : 0.0;
    final horizon = _goalsHorizonLine();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _GoalsSummaryCard(
          totalSaved: totals.saved,
          totalTargets: totals.targets,
          progress: progress,
          format: _fmtMoney,
          remainingMoneyLabel: remaining >= 0 ? '${_fmtMoney(remaining)} remaining' : '${_fmtMoney(-remaining)} over target',
          horizonLine: horizon,
          onEdit: () async {
            final ok = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => AddGoalScreen(currencyCode: widget.currencyCode)),
            );
            if (ok == true && mounted) await _loadGoals();
          },
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
          for (final g in list) _buildGoalDismissibleCard(g),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true || !mounted) return false;
    try {
      await Supabase.instance.client.from('goals').delete().eq('id', id).eq('created_by', user.id);
      if (mounted) {
        await _loadGoals();
        widget.onDataChanged();
      }
      return false;
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget seg(String label, _MgmtMainTab tab) {
      final on = selected == tab;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(tab),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: on ? cs.primary : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
                boxShadow: on
                    ? null
                    : [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: on ? cs.onPrimary : cs.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.75 : 0.88),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.periodTitle,
    required this.onPrev,
    required this.onNext,
    required this.onEditBudget,
    required this.spent,
    required this.budget,
    required this.progress,
    required this.remainingLabel,
    required this.format,
  });

  final String periodTitle;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onEditBudget;
  final double spent;
  final double budget;
  final double progress;
  final String remainingLabel;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (onPrev != null)
                IconButton(onPressed: onPrev, icon: Icon(Icons.chevron_left_rounded, color: cs.primary))
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(
                  periodTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cs.primary),
                ),
              ),
              if (onNext != null)
                IconButton(onPressed: onNext, icon: Icon(Icons.chevron_right_rounded, color: cs.primary))
              else
                const SizedBox(width: 48),
              IconButton(
                onPressed: onEditBudget,
                icon: Icon(Icons.edit_outlined, color: cs.primary, size: 22),
                tooltip: 'Edit budget',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total spent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55))),
                    const SizedBox(height: 4),
                    Text(format(spent), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.primary)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Budget', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55))),
                    const SizedBox(height: 4),
                    Text(
                      budget > 0 ? format(budget) : '—',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: budget > 0 ? progress.clamp(0.0, 1.0) : 0,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(remainingLabel, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55))),
          ),
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
    required this.onEdit,
  });

  final double totalSaved;
  final double totalTargets;
  final double progress;
  final String Function(double) format;
  final String remainingMoneyLabel;
  final String horizonLine;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subLine = horizonLine.isEmpty ? remainingMoneyLabel : '$remainingMoneyLabel · $horizonLine';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                    const SizedBox(height: 4),
                    Text(format(totalSaved), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Goals',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                    const SizedBox(height: 4),
                    Text(format(totalTargets), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: totalTargets > 0 ? progress.clamp(0.0, 1.0) : 0,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  subLine,
                  style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.55), fontSize: 13),
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, color: cs.primary, size: 22),
                tooltip: 'Add goal',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
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
                hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.42)),
              ),
            ),
          ),
          if (showTypeButton && onType != null)
            TextButton(
              onPressed: onType,
              child: Text('Type', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 13)),
            ),
          if (showFilterButton)
            TextButton(
              onPressed: onFilter,
              child: Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 13)),
            ),
          TextButton(
            onPressed: onSort,
            child: Text('Sort', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _MgmtTxTile extends StatelessWidget {
  const _MgmtTxTile({
    required this.data,
    required this.format,
    required this.onTap,
    required this.confirmDismissDelete,
  });

  final Map<String, dynamic> data;
  final String Function(double) format;
  final VoidCallback onTap;
  final Future<bool> Function() confirmDismissDelete;

  static double _parseAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  static bool _isExpense(Map<String, dynamic> data, double amount) {
    final catMap = data['categories'];
    String? catType;
    if (catMap is Map) catType = catMap['type']?.toString().toLowerCase();
    final legacyType = (data['type'] ?? data['transaction_type'] ?? '').toString().toLowerCase();
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day} ${d.year}';
  }

  static Color _accentFromTitle(String title) {
    final h = title.hashCode.abs();
    const colors = [
      Color(0xFF6BB3F0),
      Color(0xFFFF8FB8),
      Color(0xFFFFB86C),
      Color(0xFF7FD8BE),
      Color(0xFFB39DFF),
      Color(0xFFB0BEC5),
    ];
    return colors[h % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = (data['description'] ?? data['title'] ?? 'Transaction').toString();
    var category = (data['category'] ?? '').toString();
    final catMap = data['categories'];
    if (catMap is Map && (catMap['name']?.toString().isNotEmpty ?? false)) {
      category = catMap['name'].toString();
    }
    final createdRaw = data['created_at'] ?? data['date'];
    final d = createdRaw != null ? DateTime.tryParse(createdRaw.toString()) : null;
    final subtitle = [
      if (category.isNotEmpty) category,
      if (d != null) _prettyDate(d),
    ].join(' - ');

    final amount = _parseAmount(data['amount']);
    final isExpense = _isExpense(data, amount);

    IconData leafIcon;
    Color leafColor;
    if (isExpense) {
      leafIcon = Icons.eco_outlined;
      leafColor = Colors.orange.shade700;
    } else {
      leafIcon = Icons.eco_outlined;
      leafColor = Colors.green.shade700;
    }

    final tile = Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: cs.surfaceContainerLow,
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: isDark ? 0.25 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _accentFromTitle(title).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isExpense ? Icons.shopping_bag_outlined : Icons.payments_outlined,
                    color: isExpense ? Colors.deepOrange.shade700 : cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                    ],
                  ),
                ),
                Icon(leafIcon, size: 18, color: leafColor),
                const SizedBox(width: 6),
                Text(
                  isExpense ? '-${format(amount.abs())}' : '+${format(amount.abs())}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isExpense ? Colors.red.shade700 : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final id = data['id']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key('tx-$id-${title.hashCode}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
        ),
        confirmDismiss: (_) => confirmDismissDelete(),
        child: tile,
      ),
    );
  }
}

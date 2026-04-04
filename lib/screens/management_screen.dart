import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/screens/add_goal_screen.dart';
import 'package:infaq/screens/add_subscription_screen.dart';
import 'package:infaq/ui/infaq_widgets.dart';

const Color _kMgmtMint = Color(0xFFE6F4EA);
const Color _kPrimary = Color(0xFF3F5F4A);

enum _MgmtMainTab { transactions, subscriptions, goals }

enum _PeriodMode { allTime, month, year }

enum _TxTypeFilter { all, income, expense }

enum _AmountSort { none, highToLow, lowToHigh }

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
      backgroundColor: Colors.white,
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
          style: TextStyle(color: Colors.black.withValues(alpha: 0.7)),
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
    final spent = _totalSpentInPeriod();
    final budget = _monthlyBudget;
    final progress = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
    final remaining = budget - spent;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: _kMgmtMint,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
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
                        const Text(
                          'Management',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _kPrimary),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _pickPeriodMode,
                          icon: const Icon(Icons.schedule_rounded, color: _kPrimary),
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
              color: _kPrimary,
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
      return ListView(children: [SizedBox(height: 120), Center(child: CircularProgressIndicator(color: _kPrimary))]);
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
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No transactions for this view. Change filters or add a transaction.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
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
      backgroundColor: Colors.white,
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
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Category', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('For: $typeLabel', style: TextStyle(color: Colors.black.withValues(alpha: 0.45), fontSize: 13)),
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
      backgroundColor: Colors.white,
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

  Widget _buildSubscriptionsTab() {
    if (_loadingSub) {
      return ListView(children: [SizedBox(height: 120), Center(child: CircularProgressIndicator(color: _kPrimary))]);
    }
    if (_subscriptions.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text('No subscriptions yet', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final ok =
                        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddSubscriptionScreen(currencyCode: widget.currencyCode)));
                    if (ok == true && mounted) await _loadSubscriptions();
                  },
                  style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                  child: const Text('Add subscription'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: _subscriptions.length,
      itemBuilder: (context, i) {
        final s = _subscriptions[i];
        final sid = s['id']?.toString() ?? '$i';
        return Dismissible(
          key: ValueKey('sub-$sid'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
          ),
          confirmDismiss: (_) => _confirmDeleteSubscription(s),
          child: ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
            leading: CircleAvatar(backgroundColor: _kMgmtMint, child: Icon(Icons.subscriptions_outlined, color: Colors.blueGrey.shade700)),
            title: Text(s['name']?.toString() ?? 'Subscription', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${_fmtMoney(_readAmount(s['amount']))} · ${s['billing_cycle'] ?? ''}'),
          ),
        );
      },
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

  Widget _buildGoalsTab() {
    if (_loadingGoals) {
      return ListView(children: [SizedBox(height: 120), Center(child: CircularProgressIndicator(color: _kPrimary))]);
    }
    if (_goals.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Text('No goals yet', style: TextStyle(color: Colors.black.withValues(alpha: 0.5))),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AddGoalScreen(currencyCode: widget.currencyCode)));
                    if (ok == true && mounted) await _loadGoals();
                  },
                  style: FilledButton.styleFrom(backgroundColor: _kPrimary),
                  child: const Text('Add goal'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: _goals.length,
      itemBuilder: (context, i) {
        final g = _goals[i];
        final gid = g['id']?.toString() ?? '$i';
        return Dismissible(
          key: ValueKey('goal-$gid'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
          ),
          confirmDismiss: (_) => _confirmDeleteGoal(g),
          child: ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
            leading: CircleAvatar(backgroundColor: const Color(0xFFE8E2F7), child: Icon(Icons.flag_outlined, color: Colors.deepPurple.shade400)),
            title: Text(g['title']?.toString() ?? 'Goal', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${_fmtMoney(_readAmount(g['current_amount']))} / ${_fmtMoney(_readAmount(g['target_amount']))}',
            ),
          ),
        );
      },
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
                color: on ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: on ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: on ? Colors.white : _kPrimary,
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
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (onPrev != null)
                IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded, color: _kPrimary))
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(
                  periodTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _kPrimary),
                ),
              ),
              if (onNext != null)
                IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded, color: _kPrimary))
              else
                const SizedBox(width: 48),
              IconButton(
                onPressed: onEditBudget,
                icon: const Icon(Icons.edit_outlined, color: _kPrimary, size: 22),
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
                    Text('Total spent', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.45))),
                    const SizedBox(height: 4),
                    Text(format(spent), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _kPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Budget', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.45))),
                    const SizedBox(height: 4),
                    Text(
                      budget > 0 ? format(budget) : '—',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black.withValues(alpha: 0.35)),
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
              backgroundColor: const Color(0xFFE5EAE6),
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(remainingLabel, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black.withValues(alpha: 0.45))),
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
    required this.onType,
    required this.onFilter,
    required this.onSort,
  });

  final String searchHint;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onType;
  final VoidCallback onFilter;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 22, color: _kPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              onChanged: onQueryChanged,
              decoration: InputDecoration(
                hintText: searchHint,
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
          ),
          TextButton(onPressed: onType, child: const Text('Type', style: TextStyle(fontWeight: FontWeight.w700, color: _kPrimary, fontSize: 13))),
          TextButton(onPressed: onFilter, child: const Text('Filter', style: TextStyle(fontWeight: FontWeight.w700, color: _kPrimary, fontSize: 13))),
          TextButton(onPressed: onSort, child: const Text('Sort', style: TextStyle(fontWeight: FontWeight.w700, color: _kPrimary, fontSize: 13))),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
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
                    color: isExpense ? Colors.deepOrange.shade700 : _kPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45))),
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
                    color: isExpense ? Colors.red.shade700 : Colors.black87,
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

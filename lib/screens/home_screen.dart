import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/screens/add_goal_screen.dart';
import 'package:infaq/screens/add_subscription_screen.dart';
import 'package:infaq/screens/add_transaction_screen.dart';
import 'package:infaq/screens/data_privacy_screen.dart';
import 'package:infaq/screens/edit_profile_screen.dart';
import 'package:infaq/screens/help_support_screen.dart';
import 'package:infaq/screens/insights_screen.dart';
import 'package:infaq/screens/manage_categories_screen.dart';
import 'package:infaq/screens/management_screen.dart';
import 'package:infaq/screens/profile_tab_screen.dart';
import 'package:infaq/profile/avatar_storage.dart';
import 'package:infaq/services/ai_service.dart';
import 'package:infaq/ui/ai_insight_card.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';
import 'package:infaq/user_profile_sync.dart';

const Color _kHeaderGreen = Color(0xFFE8F2EA);

/// Home dashboard after login. Loads profile from `users` and transactions from
/// `transactions` when available (expects `user_id`, `amount`, `type`, optional
/// `title`/`description`/`category`, `created_at`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;
  String? _name;
  String? _currency;
  double _balance = 0;
  double _spentToday = 0;
  List<Map<String, dynamic>> _transactions = [];
  /// Incremented after each successful `_bootstrap()` so [ManagementScreen] reloads its transaction list.
  int _transactionsListRefreshToken = 0;
  String? _profilePhotoStoragePath;
  String? _profileAvatarPublicUrl;

  /// 0 home, 1 currency, 2 analytics, 3 profile (center + is separate action).
  int _tabIndex = 0;
  /// Mirrors Management tab: 0 transactions, 1 subscriptions, 2 goals.
  int _managementTabIndex = 0;

  List<Map<String, dynamic>> _aiInsightCards = [];
  bool _loadingAiInsights = false;
  final _aiService = AiService();

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _loadAiHomeInsights();
  }

  Future<void> _loadAiHomeInsights() async {
    if (!mounted) return;
    setState(() => _loadingAiInsights = true);
    try {
      final cards = await _aiService.generateHomeInsights();
      if (!mounted) return;
      setState(() => _aiInsightCards = cards);
    } catch (e, st) {
      debugPrint('AI home insights failed: $e\n$st');
      if (!mounted) return;
      setState(() => _aiInsightCards = []);
    } finally {
      if (mounted) setState(() => _loadingAiInsights = false);
    }
  }

  Future<void> _bootstrap() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await _bootstrapLoadUserData(supabase, user).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Loading your dashboard timed out. Check your connection and tap Retry on the error screen if shown, or pull to refresh.';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _bootstrapLoadUserData(SupabaseClient supabase, User user) async {
    var profile = await supabase
        .from('users')
        .select('name,username,currency,Balance,profile_photo_path')
        .eq('id', user.id)
        .maybeSingle();

    if (profile != null) {
      await syncRegistrationMetadataToUsersRow(supabase, user);
    } else {
      final meta = (user.userMetadata ?? const <String, dynamic>{});
      final rawUsername = (meta['username'] ?? '').toString().trim();
      final rawName = (meta['name'] ?? meta['full_name'] ?? '').toString().trim();
      final email = (user.email ?? '').toString().trim();
      final derivedUsername = rawUsername.isNotEmpty
          ? rawUsername
          : (email.contains('@') ? email.split('@').first : email);
      final derivedName = rawName.isNotEmpty ? rawName : email;
      final safeUsername =
          derivedUsername.isNotEmpty ? derivedUsername : 'user_${user.id.substring(0, 6)}';
      final rawCurrency = (meta['currency'] ?? 'BHD').toString().trim();
      final currency = rawCurrency.isNotEmpty ? rawCurrency : 'BHD';
      final balance = balanceFromMetadata(meta['balance']);

      await supabase.from('users').upsert(
        <String, Object?>{
          'id': user.id,
          'name': derivedName,
          'username': safeUsername,
          'currency': currency,
          'Balance': balance.toDouble(),
        },
        onConflict: 'id',
      );
      await syncRegistrationMetadataToUsersRow(supabase, user);

      profile = await supabase
          .from('users')
          .select('name,username,currency,Balance,profile_photo_path')
          .eq('id', user.id)
          .maybeSingle();
    }

    final tx = await _fetchRecentTransactions(user.id);
    final spent = _computeSpentToday(tx);

    if (!mounted) return;
    final photoPath = (profile?['profile_photo_path'] as String?)?.trim();
    setState(() {
      _name = (profile?['name'] as String?)?.trim();
      _currency = (profile?['currency'] as String?)?.trim() ?? 'BHD';
      _balance = _readBalance(profile?['Balance']);
      _transactions = tx;
      _spentToday = spent;
      _transactionsListRefreshToken++;
      _profilePhotoStoragePath = photoPath != null && photoPath.isNotEmpty ? photoPath : null;
      _profileAvatarPublicUrl = InfaqAvatarStorage.publicUrl(supabase, _profilePhotoStoragePath);
      _loading = false;
      _error = null;
    });
  }

  double _readBalance(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  Future<List<Map<String, dynamic>>> _fetchRecentTransactions(String userId) async {
    try {
      dynamic res;
      try {
        res = await Supabase.instance.client
            .from('transactions')
            .select('id, amount, description, date, created_at, category_id, categories(name, type)')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100);
      } catch (_) {
        res = await Supabase.instance.client
            .from('transactions')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100);
      }
      final list = res as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  double _computeSpentToday(List<Map<String, dynamic>> rows) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    var sum = 0.0;
    for (final r in rows) {
      final createdRaw = r['date'] ?? r['created_at'];
      if (createdRaw == null) continue;
      final d = DateTime.tryParse(createdRaw.toString());
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(start)) continue;

      final amount = _readAmount(r['amount']);
      final cat = r['categories'];
      String? catType;
      if (cat is Map) {
        catType = cat['type']?.toString().toLowerCase();
      }
      if (catType == 'expense') {
        sum += amount.abs();
      } else if (catType == null || catType.isEmpty) {
        final type = (r['type'] ?? r['transaction_type'] ?? '').toString().toLowerCase();
        if (type == 'expense' || type == 'debit' || type == 'out') {
          sum += amount.abs();
        } else if (type.isEmpty && amount < 0) {
          sum += amount.abs();
        }
      }
    }
    return sum;
  }

  double _readAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _currencyPrefix() {
    switch (_currency?.toUpperCase()) {
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
        return '${_currency ?? ''} '.trim().isEmpty ? '' : '${_currency!} ';
    }
  }

  String _fmtMoney(double v) {
    final p = _currencyPrefix();
    final n = v.abs();
    final s = n >= 1000 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
    return '$p$s';
  }

  String _greetingLine() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _firstName() {
    final n = _name?.trim();
    if (n == null || n.isEmpty) return 'there';
    return n.split(RegExp(r'\s+')).first;
  }

  void _soon(String label) {
    showInfaqSnack(context, '$label — coming soon');
  }

  Future<void> _openAddTransaction({bool? initialIncome}) async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<void>(
        builder: (context) => AddTransactionScreen(
          currencyCode: _currency,
          initialIncome: initialIncome,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _bootstrap();
    } else if (result is int && result >= 0 && result <= 3) {
      setState(() => _tabIndex = result);
    }
  }

  Future<void> _openEditTransaction(Map<String, dynamic> row) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => AddTransactionScreen(
          currencyCode: _currency,
          existingTransaction: row,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) await _bootstrap();
  }

  /// For [Dismissible]: returns `true` if the row should be removed, `false` to snap back.
  Future<bool> _confirmDeleteTransactionDismissible(Map<String, dynamic> row) async {
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
      await _bootstrap();
      if (mounted) showInfaqSnack(context, 'Transaction deleted');
      return true;
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
      return false;
    }
  }

  Future<void> _openAddSubscription() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<void>(
        builder: (context) => AddSubscriptionScreen(currencyCode: _currency),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _bootstrap();
    } else if (result is int && result >= 0 && result <= 3) {
      setState(() => _tabIndex = result);
    }
  }

  Future<void> _openAddGoal() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute<void>(
        builder: (context) => AddGoalScreen(currencyCode: _currency),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _bootstrap();
    } else if (result is int && result >= 0 && result <= 3) {
      setState(() => _tabIndex = result);
    }
  }

  Future<void> _handleBottomAdd() async {
    if (_tabIndex == 0) {
      await _openAddTransaction();
      return;
    }

    if (_tabIndex == 1) {
      switch (_managementTabIndex) {
        case 1:
          await _openAddSubscription();
          return;
        case 2:
          await _openAddGoal();
          return;
        case 0:
        default:
          await _openAddTransaction();
          return;
      }
    }

    await _openAddTransaction();
  }

  void _openHelpSupport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const HelpSupportScreen()),
    );
  }

  void _openDataAndPrivacy() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const DataPrivacyScreen()),
    );
  }

  Future<void> _openEditProfile() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => EditProfileScreen(
          initialName: _name,
          initialCurrency: _currency,
          initialProfilePhotoPath: _profilePhotoStoragePath,
          initialAvatarPublicUrl: _profileAvatarPublicUrl,
        ),
      ),
    );
    if (!mounted) return;
    if (changed == true) await _bootstrap();
  }

  Future<void> _openManageCategories() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const ManageCategoriesScreen()),
    );
  }

  void _onServiceTap(String key) {
    switch (key) {
      case 'income':
        _openAddTransaction(initialIncome: true);
        break;
      case 'expense':
        _openAddTransaction(initialIncome: false);
        break;
      case 'subs':
        _openAddSubscription();
        break;
      case 'goals':
        _openAddGoal();
        break;
      case 'categories':
        _openManageCategories();
        break;
      default:
        _soon(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(child: CircularProgressIndicator(color: cs.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Failed to load dashboard\n$_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface),
                ),
                const SizedBox(height: 16),
                TextButton(onPressed: _bootstrap, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final progress = _balance > 0 ? (_spentToday / _balance).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: cs.surface,
      extendBody: true,
      bottomNavigationBar: InfaqBottomNavBar(
        tabIndex: _tabIndex,
        onHome: () => setState(() => _tabIndex = 0),
        onCurrency: () => setState(() => _tabIndex = 1),
        onAdd: _handleBottomAdd,
        onAnalytics: () => setState(() => _tabIndex = 2),
        onProfile: () => setState(() => _tabIndex = 3),
      ),
      body: ColoredBox(
        color: cs.surface,
        child: IndexedStack(
          index: _tabIndex,
          children: [
            RefreshIndicator(
              color: cs.primary,
              onRefresh: () async {
                await _bootstrap();
                await _loadAiHomeInsights();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            isDark ? const Color(0xFF1A2520) : _kHeaderGreen,
                            cs.surface,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _greetingLine(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: cs.onSurface.withValues(alpha: 0.55),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sign out',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => Supabase.instance.client.auth.signOut(),
                                    icon: Icon(Icons.logout_rounded, color: cs.primary, size: 22),
                                  ),
                                ],
                              ),
                              Text(
                                _firstName(),
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _SummaryCard(
                                monthLabel: _monthYearLabel(),
                                dateDayLabel: _todayLabel(),
                                spentToday: _spentToday,
                                balance: _balance,
                                progress: progress,
                                format: _fmtMoney,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Services',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface),
                          ),
                          const SizedBox(height: 12),
                          _ServicesGrid(onServiceTap: _onServiceTap),
                          const SizedBox(height: 28),
                          _SectionHeader(
                            title: 'Insights',
                            action: 'View all',
                            onAction: () => setState(() => _tabIndex = 2),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: _loadingAiInsights
                                ? [AiInsightCard.loading()]
                                : _aiInsightCards.isEmpty
                                    ? [AiInsightCard.fallback()]
                                    : _aiInsightCards
                                        .take(3)
                                        .map(
                                          (c) => Padding(
                                            padding: const EdgeInsets.only(bottom: 10),
                                            child: AiInsightCard.fromMap(c),
                                          ),
                                        )
                                        .toList(),
                          ),
                          const SizedBox(height: 28),
                          _SectionHeader(
                            title: 'Recent transactions',
                            action: 'View all',
                            onAction: () => setState(() => _tabIndex = 1),
                          ),
                          const SizedBox(height: 12),
                          _TransactionsList(
                            transactions: _transactions,
                            format: _fmtMoney,
                            onEdit: _openEditTransaction,
                            onConfirmDismissDelete: _confirmDeleteTransactionDismissible,
                          ),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ManagementScreen(
              currencyCode: _currency,
              initialMonthlyBudget: _balance,
              transactionsListRefreshToken: _transactionsListRefreshToken,
              onDataChanged: _bootstrap,
              onEditTransaction: _openEditTransaction,
              onMainTabIndexChanged: (index) => setState(() => _managementTabIndex = index),
            ),
            InsightsScreen(
              refreshToken: _transactionsListRefreshToken,
              currencyCode: _currency,
            ),
            ProfileTabScreen(
              displayName: _name,
              avatarPublicUrl: _profileAvatarPublicUrl,
              onOpenEditProfile: _openEditProfile,
              onDataRefresh: _bootstrap,
              onHelpAndSupport: _openHelpSupport,
              onDataAndPrivacy: _openDataAndPrivacy,
            ),
          ],
        ),
      ),
    );
  }

  String _monthYearLabel() {
    final d = DateTime.now();
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
    return '${months[d.month - 1]} ${d.year}';
  }

  String _todayLabel() {
    final d = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // weekday 1 = Monday
    final wd = days[d.weekday - 1];
    return '$wd, ${d.day}/${d.month}/${d.year}';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.monthLabel,
    required this.dateDayLabel,
    required this.spentToday,
    required this.balance,
    required this.progress,
    required this.format,
  });

  static const double _cardRadius = 16;
  static const double _amountSize = 17;

  final String monthLabel;
  final String dateDayLabel;
  final double spentToday;
  final double balance;
  final double progress;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = cs.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.22 : 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            monthLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dateDayLabel,
            style: TextStyle(
              fontSize: 11,
              color: onSurface.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total spent (today)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        format(spentToday),
                        style: TextStyle(
                          fontSize: _amountSize,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                          height: 1.1,
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
                      'Balance',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        format(balance),
                        style: TextStyle(
                          fontSize: _amountSize,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withValues(alpha: 0.5),
                          height: 1.1,
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
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({required this.onServiceTap});

  final void Function(String serviceKey) onServiceTap;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.south_west_rounded, 'Income', 'income'),
      (Icons.north_east_rounded, 'Expense', 'expense'),
      (Icons.subscriptions_outlined, 'Subs', 'subs'),
      (Icons.track_changes_rounded, 'Goals', 'goals'),
      (Icons.grid_view_rounded, 'Categories', 'categories'),
      (Icons.edit_calendar_rounded, 'Edit', 'edits'),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final spacing = 10.0;
        final cols = 3;
        final cell = (w - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final (icon, short, key) in items)
              SizedBox(
                width: cell,
                child: _ServiceTile(
                  icon: icon,
                  label: short,
                  onTap: () => onServiceTap(key),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? cs.surfaceContainerHigh : _kHeaderGreen,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.22)),
                ),
                child: Icon(icon, color: cs.primary, size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text('$action →', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({
    required this.transactions,
    required this.format,
    required this.onEdit,
    required this.onConfirmDismissDelete,
  });

  final List<Map<String, dynamic>> transactions;
  final String Function(double) format;
  final void Function(Map<String, dynamic> row) onEdit;
  final Future<bool> Function(Map<String, dynamic> row) onConfirmDismissDelete;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Text(
          'No transactions yet. Add your first income or expense from Services.',
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), height: 1.4),
        ),
      );
    }

    return Column(
      children: [
        for (final t in transactions.take(8))
          _TxRow(
            data: t,
            format: format,
            onTap: () => onEdit(t),
            confirmDismissDelete: () => onConfirmDismissDelete(t),
          ),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({
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
    final amountMaxWidth = (MediaQuery.sizeOf(context).width * 0.28).clamp(90.0, 132.0);
    final title = (data['description'] ?? data['title'] ?? data['merchant'] ?? data['name'] ?? 'Transaction').toString();
    var category = (data['category'] ?? data['category_name'] ?? '').toString();
    final catMap = data['categories'];
    if (catMap is Map && (catMap['name']?.toString().isNotEmpty ?? false)) {
      category = catMap['name'].toString();
    }
    final createdRaw = data['date'] ?? data['created_at'];
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

    final txId = data['id']?.toString() ?? '';
    final canMutate = txId.isNotEmpty;

    final tile = Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: canMutate ? onTap : null,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accentFromTitle(title).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isExpense ? Icons.shopping_bag_outlined : Icons.payments_outlined,
                    size: 22,
                    color: isExpense ? Colors.deepOrange.shade700 : cs.primary,
                  ),
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
                      Icon(leafIcon, size: 15, color: leafColor),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: amountMaxWidth),
                        child: Text(
                          isExpense ? '-${format(amount.abs())}' : '+${format(amount.abs())}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            height: 1.1,
                            letterSpacing: -0.15,
                            color: isExpense ? Colors.red.shade700 : cs.onSurface,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: canMutate
          ? Dismissible(
              key: Key('home-tx-$txId-${title.hashCode}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
              ),
              confirmDismiss: (_) => confirmDismissDelete(),
              child: tile,
            )
          : tile,
    );
  }
}

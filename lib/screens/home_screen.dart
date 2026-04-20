import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/screens/add_goal_screen.dart';
import 'package:infaq/screens/add_subscription_screen.dart';
import 'package:infaq/screens/add_transaction_screen.dart';
import 'package:infaq/screens/edit_profile_screen.dart';
import 'package:infaq/screens/help_support_screen.dart';
import 'package:infaq/screens/manage_categories_screen.dart';
import 'package:infaq/screens/management_screen.dart';
import 'package:infaq/screens/profile_tab_screen.dart';
import 'package:infaq/profile/avatar_storage.dart';
import 'package:infaq/ui/infaq_bottom_nav.dart';
import 'package:infaq/ui/infaq_widgets.dart';
import 'package:infaq/user_profile_sync.dart';

const Color _kPrimary = Color(0xFF3F5F4A);
const Color _kHeaderGreen = Color(0xFFE8F2EA);
const Color _kCardTint = Color(0xFFEEF5F0);

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

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  Future<void> _confirmDeleteTransaction(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;

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
    if (ok != true || !mounted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('transactions').delete().eq('id', id).eq('user_id', user.id);
      if (!mounted) return;
      await _bootstrap();
      if (mounted) showInfaqSnack(context, 'Transaction deleted');
    } catch (e) {
      if (mounted) showInfaqSnack(context, 'Could not delete: $e');
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

  void _openHelpSupport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (context) => const HelpSupportScreen()),
    );
  }

  Future<void> _openEditProfile() async {
    final u = Supabase.instance.client.auth.currentUser;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => EditProfileScreen(
          initialName: _name,
          initialCurrency: _currency,
          initialIncomeType: u?.userMetadata?['income_type']?.toString(),
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

    final remaining = _balance - _spentToday;
    final progress = _balance > 0 ? (_spentToday / _balance).clamp(0.0, 1.0) : 0.0;
    final remainingLabel = remaining >= 0
        ? '${_fmtMoney(remaining)} remaining'
        : 'Over by ${_fmtMoney(remaining.abs())}';

    return Scaffold(
      backgroundColor: cs.surface,
      extendBody: true,
      bottomNavigationBar: InfaqBottomNavBar(
        tabIndex: _tabIndex,
        onHome: () => setState(() => _tabIndex = 0),
        onCurrency: () => setState(() => _tabIndex = 1),
        onAdd: _openAddTransaction,
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
              onRefresh: _bootstrap,
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
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _greetingLine(),
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: cs.onSurface.withValues(alpha: 0.55),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sign out',
                                    onPressed: () => Supabase.instance.client.auth.signOut(),
                                    icon: Icon(Icons.logout_rounded, color: cs.primary),
                                  ),
                                ],
                              ),
                              Text(
                                _firstName(),
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _SummaryCard(
                                monthLabel: _monthYearLabel(),
                                dateDayLabel: _todayLabel(),
                                spentToday: _spentToday,
                                balance: _balance,
                                remainingLabel: remainingLabel,
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
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Services',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                          ),
                          const SizedBox(height: 14),
                          _ServicesGrid(onServiceTap: _onServiceTap),
                          const SizedBox(height: 28),
                          _SectionHeader(
                            title: 'Insights',
                            action: 'View all',
                            onAction: () => _soon('Insights'),
                          ),
                          const SizedBox(height: 12),
                          _InsightsPlaceholder(),
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
                            onDelete: _confirmDeleteTransaction,
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
            ),
            _PlaceholderTab(
              title: 'Analytics',
              subtitle: 'Spending trends and insights will live here.',
              onBackHome: () => setState(() => _tabIndex = 0),
            ),
            ProfileTabScreen(
              displayName: _name,
              avatarPublicUrl: _profileAvatarPublicUrl,
              onOpenEditProfile: _openEditProfile,
              onDataRefresh: _bootstrap,
              onHelpAndSupport: _openHelpSupport,
              onDataAndPrivacy: () => _soon('Data and privacy'),
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

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.title,
    required this.subtitle,
    required this.onBackHome,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBackHome,
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
                label: const Text('Home'),
                style: TextButton.styleFrom(foregroundColor: cs.primary),
              ),
              const SizedBox(height: 24),
              Text(title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 15, color: cs.onSurface.withValues(alpha: 0.55), height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.monthLabel,
    required this.dateDayLabel,
    required this.spentToday,
    required this.balance,
    required this.remainingLabel,
    required this.progress,
    required this.format,
  });

  final String monthLabel;
  final String dateDayLabel;
  final double spentToday;
  final double balance;
  final String remainingLabel;
  final double progress;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Theme.of(context).brightness == Brightness.dark ? Border.all(color: cs.outline.withValues(alpha: 0.2)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.4 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            monthLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateDayLabel,
            style: TextStyle(
              fontSize: 12,
              color: onSurface.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total spent (today)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      format(spentToday),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Balance',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      format(balance),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHigh,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              remainingLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.45),
              ),
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
        final spacing = 12.0;
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
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark ? cs.surfaceContainerHigh : _kHeaderGreen,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cs.outline.withValues(alpha: isDark ? 0.35 : 0.25)),
                ),
                child: Icon(icon, color: cs.primary, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
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
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
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

class _InsightsPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InsightCard(
          icon: Icons.auto_graph_rounded,
          iconColor: _kPrimary,
          iconBg: _kCardTint,
          title: 'Insights coming soon',
          body:
              'When you add income and expenses, this space will show trends, comparisons, and simple recommendations.',
        ),
        const SizedBox(height: 10),
        _InsightCard(
          icon: Icons.eco_rounded,
          iconBg: const Color(0xFFE3F2E5),
          iconColor: _kPrimary,
          title: 'Sustainability tips',
          body: 'Eco-related suggestions will appear here based on your spending patterns.',
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? cs.surfaceContainerHigh : _kCardTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({
    required this.transactions,
    required this.format,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> transactions;
  final String Function(double) format;
  final void Function(Map<String, dynamic> row) onEdit;
  final void Function(Map<String, dynamic> row) onDelete;

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
          'No transactions yet. Add expenses or income from Services when those flows are ready, '
          'or insert rows in the `transactions` table (user_id, amount, type, created_at).',
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
            onEdit: () => onEdit(t),
            onDelete: () => onDelete(t),
          ),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({
    required this.data,
    required this.format,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final String Function(double) format;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ??
            data['description'] ??
            data['merchant'] ??
            data['name'] ??
            'Transaction')
        .toString();
    var category = (data['category'] ?? data['category_name'] ?? '').toString();
    final catMap = data['categories'];
    if (catMap is Map && (catMap['name']?.toString().isNotEmpty ?? false)) {
      category = catMap['name'].toString();
    }
    // Prefer user-selected transaction date; fallback to created_at for legacy rows.
    final createdRaw = data['date'] ?? data['created_at'];
    final d = createdRaw != null ? DateTime.tryParse(createdRaw.toString()) : null;
    final sub = [
      if (category.isNotEmpty) category,
      if (d != null) _shortDate(d),
    ].join(' · ');

    final amount = _parseAmount(data['amount']);
    String? catType;
    if (catMap is Map) {
      catType = catMap['type']?.toString().toLowerCase();
    }
    final legacyType = (data['type'] ?? data['transaction_type'] ?? '').toString().toLowerCase();
    final isExpense = catType == 'expense' ||
        (catType == null &&
            (legacyType == 'expense' ||
                legacyType == 'debit' ||
                legacyType == 'out' ||
                (legacyType.isEmpty && amount < 0)));
    final displayAmount = isExpense ? -amount.abs() : amount.abs();
    final txId = data['id']?.toString();
    final canMutate = txId != null && txId.isNotEmpty;

    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isExpense ? Colors.deepOrange.withValues(alpha: 0.18) : cs.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isExpense ? Icons.shopping_bag_outlined : Icons.payments_outlined,
              color: isExpense ? Colors.orangeAccent : cs.primary,
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
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45)),
                  ),
              ],
            ),
          ),
          Text(
            isExpense ? '-${format(displayAmount.abs())}' : '+${format(displayAmount)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isExpense ? Colors.red.shade300 : cs.primary,
            ),
          ),
          if (canMutate) ...[
            IconButton(
              tooltip: 'Edit',
              onPressed: onEdit,
              icon: Icon(Icons.edit_outlined, color: cs.primary, size: 22),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700, size: 22),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }

  double _parseAmount(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0;
  }

  String _shortDate(DateTime d) {
    return '${d.day}/${d.month}';
  }
}

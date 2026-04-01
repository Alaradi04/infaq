import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          .select('name,username,currency,Balance')
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
            .select('name,username,currency,Balance')
            .eq('id', user.id)
            .maybeSingle();
      }

      final tx = await _fetchRecentTransactions(user.id);
      final spent = _computeSpentToday(tx);

      if (!mounted) return;
      setState(() {
        _name = (profile?['name'] as String?)?.trim();
        _currency = (profile?['currency'] as String?)?.trim() ?? 'BHD';
        _balance = _readBalance(profile?['Balance']);
        _transactions = tx;
        _spentToday = spent;
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
      final res = await Supabase.instance.client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
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
      final createdRaw = r['created_at'] ?? r['date'];
      if (createdRaw == null) continue;
      final d = DateTime.tryParse(createdRaw.toString());
      if (d == null || d.isBefore(start)) continue;

      final type = (r['type'] ?? r['transaction_type'] ?? '').toString().toLowerCase();
      final amount = _readAmount(r['amount']);
      if (type == 'expense' || type == 'debit' || type == 'out') {
        sum += amount.abs();
      } else if (type.isEmpty && amount < 0) {
        sum += amount.abs();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: _kPrimary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Failed to load dashboard\n$_error', textAlign: TextAlign.center),
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
      backgroundColor: Colors.white,
      extendBody: true,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _soon('Voice'),
        backgroundColor: _kPrimary,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.mic_rounded, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: const CircularNotchedRectangle(),
        color: Colors.white,
        elevation: 12,
        shadowColor: Colors.black26,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Home',
              onPressed: () {},
              icon: const Icon(Icons.home_rounded, color: _kPrimary),
            ),
            IconButton(
              tooltip: 'Currency',
              onPressed: () => _soon('Currency'),
              icon: Icon(Icons.attach_money_rounded, color: Colors.grey.shade600),
            ),
            const Spacer(),
            SizedBox(width: MediaQuery.sizeOf(context).width * 0.06),
            const Spacer(),
            IconButton(
              tooltip: 'Analytics',
              onPressed: () => _soon('Analytics'),
              icon: Icon(Icons.show_chart_rounded, color: Colors.grey.shade600),
            ),
            IconButton(
              tooltip: 'Profile',
              onPressed: () => _soon('Profile'),
              icon: Icon(Icons.person_outline_rounded, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _bootstrap,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kHeaderGreen, Colors.white],
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
                                  color: Colors.black.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Sign out',
                              onPressed: () => Supabase.instance.client.auth.signOut(),
                              icon: const Icon(Icons.logout_rounded, color: _kPrimary),
                            ),
                          ],
                        ),
                        Text(
                          _firstName(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: _kPrimary,
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
                    const Text(
                      'Services',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    _ServicesGrid(onTap: _soon),
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
                      onAction: () => _soon('Transactions'),
                    ),
                    const SizedBox(height: 12),
                    _TransactionsList(
                      transactions: _transactions,
                      format: _fmtMoney,
                    ),
                    const SizedBox(height: 88),
                  ],
                ),
              ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3F5F4A).withValues(alpha: 0.12),
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
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateDayLabel,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withValues(alpha: 0.38),
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
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      format(spentToday),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _kPrimary,
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
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      format(balance),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.45),
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
              backgroundColor: const Color(0xFFE5EAE6),
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              remainingLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({required this.onTap});

  final void Function(String label) onTap;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.south_west_rounded, 'Income', 'Income'),
      (Icons.north_east_rounded, 'Expense', 'Expense'),
      (Icons.subscriptions_outlined, 'Subs', 'Subscriptions'),
      (Icons.track_changes_rounded, 'Goals', 'Goals'),
      (Icons.grid_view_rounded, 'Categories', 'Categories'),
      (Icons.edit_calendar_rounded, 'Edit', 'Edits'),
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
            for (final (icon, short, full) in items)
              SizedBox(
                width: cell,
                child: _ServiceTile(
                  icon: icon,
                  label: short,
                  onTap: () => onTap(full),
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
                  color: _kHeaderGreen,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD4E3D8)),
                ),
                child: Icon(icon, color: _kPrimary, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCardTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDEE8E1)),
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.35,
                    color: Colors.black.withValues(alpha: 0.55),
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
  });

  final List<Map<String, dynamic>> transactions;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8F7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8ECE9)),
        ),
        child: Text(
          'No transactions yet. Add expenses or income from Services when those flows are ready, '
          'or insert rows in the `transactions` table (user_id, amount, type, created_at).',
          style: TextStyle(color: Colors.black.withValues(alpha: 0.55), height: 1.4),
        ),
      );
    }

    return Column(
      children: [
        for (final t in transactions.take(8)) _TxRow(data: t, format: format),
      ],
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.data, required this.format});

  final Map<String, dynamic> data;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ??
            data['description'] ??
            data['merchant'] ??
            data['name'] ??
            'Transaction')
        .toString();
    final category = (data['category'] ?? data['category_name'] ?? '').toString();
    final createdRaw = data['created_at'] ?? data['date'];
    final d = createdRaw != null ? DateTime.tryParse(createdRaw.toString()) : null;
    final sub = [
      if (category.isNotEmpty) category,
      if (d != null) _shortDate(d),
    ].join(' · ');

    final amount = _parseAmount(data['amount']);
    final type = (data['type'] ?? data['transaction_type'] ?? '').toString().toLowerCase();
    final isExpense =
        type == 'expense' || type == 'debit' || type == 'out' || (type.isEmpty && amount < 0);
    final displayAmount = isExpense ? -amount.abs() : amount.abs();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isExpense ? const Color(0xFFFFF3E8) : const Color(0xFFE8F2EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isExpense ? Icons.shopping_bag_outlined : Icons.payments_outlined,
              color: isExpense ? Colors.deepOrange : _kPrimary,
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                  ),
              ],
            ),
          ),
          Text(
            isExpense ? '-${format(displayAmount.abs())}' : '+${format(displayAmount)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isExpense ? Colors.red.shade700 : _kPrimary,
            ),
          ),
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

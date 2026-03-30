import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/ui/infaq_widgets.dart';

enum _PasswordTier { weak, moderate, strong }

class RegisterFlowScreen extends StatefulWidget {
  const RegisterFlowScreen({super.key});

  @override
  State<RegisterFlowScreen> createState() => _RegisterFlowScreenState();
}

class _RegisterFlowScreenState extends State<RegisterFlowScreen> {
  int _step = 1;
  bool _loading = false;
  bool _obscure = true;

  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _currency = 'BHD';
  final _income = TextEditingController();
  final _subscriptionName = TextEditingController();
  final _subscriptionBilling = TextEditingController();
  final _subscriptionAmount = TextEditingController();
  DateTime _subscriptionNextPayment = DateTime.now();
  final _goals = TextEditingController();
  final List<_SubscriptionDraft> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPasswordChanged);
    // Default recurring cycle so validation doesn't fail if user doesn't change dropdown.
    _subscriptionBilling.text = 'monthly';
    _subscriptionNextPayment = _defaultNextPaymentForBilling(_subscriptionBilling.text);
  }

  void _onPasswordChanged() {
    // Rebuild so the strength label updates while typing.
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _income.dispose();
    _subscriptionName.dispose();
    _subscriptionBilling.dispose();
    _subscriptionAmount.dispose();
    _goals.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  _PasswordTier get _passwordTier {
    final p = _password.text;
    if (p.isEmpty) return _PasswordTier.weak;

    final hasLower = RegExp(r'[a-z]').hasMatch(p);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(p);
    final hasDigit = RegExp(r'\d').hasMatch(p);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(p);

    final categories = [hasLower, hasUpper, hasDigit, hasSymbol].where((v) => v).length;

    if (p.length < 8 || categories < 2) return _PasswordTier.weak;
    if (categories == 2) return _PasswordTier.moderate;
    return _PasswordTier.strong; // categories >= 3 (and length >= 8 by previous checks)
  }

  void _showPasswordHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Strong password tips'),
          content: const Text(
            'Strong passwords are at least 8 characters and include at least 3 of: '
            'uppercase (A-Z), lowercase (a-z), a number (0-9), and a symbol (!@#\$...).\n\n'
            'Example: Abcdef1!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  DateTime _addMonthsClamped(DateTime date, int months) {
    final newMonthIndex = (date.month - 1) + months;
    final newYear = date.year + (newMonthIndex ~/ 12);
    final newMonth = (newMonthIndex % 12) + 1;
    final lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = date.day <= lastDayOfNewMonth ? date.day : lastDayOfNewMonth;
    return DateTime(newYear, newMonth, newDay);
  }

  DateTime _addYearsClamped(DateTime date, int years) {
    final newYear = date.year + years;
    final lastDayOfNewMonth = DateTime(newYear, date.month + 1, 0).day;
    final newDay = date.day <= lastDayOfNewMonth ? date.day : lastDayOfNewMonth;
    return DateTime(newYear, date.month, newDay);
  }

  DateTime _defaultNextPaymentForBilling(String billingCycle) {
    if (billingCycle == 'yearly') {
      return _addYearsClamped(DateTime.now(), 1);
    }
    // Default to monthly.
    return _addMonthsClamped(DateTime.now(), 1);
  }

  void _addSubscription() {
    final name = _subscriptionName.text.trim();
    final billing = _subscriptionBilling.text.trim();
    final nextPayment = _subscriptionNextPayment;
    final amountText = _subscriptionAmount.text.trim();

    if (name.isEmpty || billing.isEmpty || amountText.isEmpty) {
      showInfaqSnack(context, 'Fill subscription name, billing, and amount.');
      return;
    }

    final parsed = double.tryParse(amountText);
    if (parsed == null) {
      showInfaqSnack(context, 'Amount must be a number.');
      return;
    }

    setState(() {
      _subscriptions.add(
        _SubscriptionDraft(
          name: name,
          billing: billing,
          amount: parsed,
          nextPayment: nextPayment,
        ),
      );
      _subscriptionName.clear();
      _subscriptionBilling.text = 'monthly';
      _subscriptionNextPayment = _defaultNextPaymentForBilling('monthly');
      _subscriptionAmount.clear();
    });
  }

  void _removeSubscription(int index) {
    setState(() {
      _subscriptions.removeAt(index);
    });
  }

  Future<void> _next() async {
    if (_step == 1) {
      if (_username.text.trim().isEmpty ||
          _fullName.text.trim().isEmpty ||
          _email.text.trim().isEmpty ||
          !_isValidEmail(_email.text.trim()) ||
          _password.text.isEmpty ||
          _passwordTier != _PasswordTier.strong) {
        if (_email.text.trim().isNotEmpty && !_isValidEmail(_email.text.trim())) {
          showInfaqSnack(context, 'Please enter a valid email address.');
          return;
        }
        final tier = _passwordTier;
        final message = tier == _PasswordTier.moderate
            ? 'Password is moderate. Add one more type (uppercase, lowercase, number, or symbol) to make it strong.'
            : 'Password is too weak. Use at least 8 characters and include at least 2 of: uppercase, lowercase, number, symbol.';
        showInfaqSnack(
          context,
          message,
        );
        return;
      }
      setState(() => _step = 2);
      return;
    }

    await _signUp();
  }

  Future<void> _signUp() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {
          'username': _username.text.trim(),
          'name': _fullName.text.trim(),
          'full_name': _fullName.text.trim(),
          'currency': _currency,
          'monthly_income': num.tryParse(_income.text.trim()),
          'subscriptions': _subscriptions
              .map(
                (s) => <String, Object?>{
                  'name': s.name,
                  'billing': s.billing,
                  'billing_cycle': s.billing,
                  'amount': s.amount,
                  'next_payment': _formatDate(s.nextPayment),
                },
              )
              .toList(),
          'goals': _goals.text.trim(),
        },
      );
      if (!mounted) return;
      showInfaqSnack(
        context,
        'Account created. Check your email to confirm (if enabled).',
      );
      Navigator.of(context).maybePop();
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showInfaqSnack(context, 'Sign up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const InfaqHeader(showBack: true),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create account',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _step == 1 ? 'Start your journey to better financial health' : 'Just a little more',
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 20),
                if (_step == 1) ..._buildStep1(context) else ..._buildStep2(context),
                const SizedBox(height: 20),
                if (_step > 1) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InfaqTextButton(
                      label: 'Back',
                      onTap: () => setState(() => _step--),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                InfaqPrimaryButton(
                  label: _step == 1 ? 'Next' : 'Sign up',
                  isLoading: _loading,
                  onPressed: _next,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already have an account? ', style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
                    InfaqTextButton(
                      label: 'Sign in',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStep1(BuildContext context) {
    return [
      const _FieldLabel('Username'),
      InfaqPillField(
        controller: _username,
        hintText: 'user name (e.g., Ahmed03)',
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
      ),
      const SizedBox(height: 14),
      const _FieldLabel('name'),
      InfaqPillField(
        controller: _fullName,
        hintText: 'full name (e.g., Ahmed Ali)',
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
      ),
      const SizedBox(height: 14),
      const _FieldLabel('email'),
      InfaqPillField(
        controller: _email,
        hintText: 'example@gmail.com',
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
      ),
      const SizedBox(height: 14),
      const _FieldLabel('Password'),
      InfaqPillField(
        controller: _password,
        hintText: 'Create a strong password',
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        suffix: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.center,
        child: Text(
          _passwordTier == _PasswordTier.strong
              ? 'strong'
              : _passwordTier == _PasswordTier.moderate
                  ? 'moderate'
                  : 'weak',
          style: TextStyle(
            color: _passwordTier == _PasswordTier.strong
                ? Colors.green.withValues(alpha: 0.85)
                : _passwordTier == _PasswordTier.moderate
                    ? Colors.orange.withValues(alpha: 0.85)
                    : Colors.red.withValues(alpha: 0.85),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _showPasswordHelpDialog(context),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: const Text(
            'How to write a strong password',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildStep2(BuildContext context) {
    return [
      const _FieldLabel('currency'),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x223F5F4A),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: DropdownMenu<String>(
          initialSelection: _currency,
          onSelected: (v) => setState(() => _currency = v),
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: 'BHD', label: 'BHD'),
            DropdownMenuEntry(value: 'USD', label: 'USD'),
            DropdownMenuEntry(value: 'EUR', label: 'EUR'),
            DropdownMenuEntry(value: 'SAR', label: 'SAR'),
          ],
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F8F7),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _SectionPillLabel(
        label: 'Add your monthly incomes',
        icon: Icons.attach_money_rounded,
      ),
      InfaqPillField(
        controller: _income,
        hintText: 'income',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      _SectionPillLabel(
        label: 'Add your subscription',
        icon: Icons.subscriptions_rounded,
      ),
      InfaqPillField(
        controller: _subscriptionName,
        hintText: 'subscription (e.g., Netflix)',
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x223F5F4A),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: DropdownMenu<String>(
            initialSelection:
                _subscriptionBilling.text.trim().isNotEmpty ? _subscriptionBilling.text.trim() : 'monthly',
            onSelected: (v) {
              if (v == null) return;
              setState(() {
                _subscriptionBilling.text = v;
                _subscriptionNextPayment = _defaultNextPaymentForBilling(v);
              });
            },
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: 'monthly', label: 'Monthly'),
              DropdownMenuEntry(value: 'yearly', label: 'Yearly'),
            ],
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF7F8F7),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      SizedBox(
        height: 56,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _subscriptionNextPayment,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            setState(() => _subscriptionNextPayment = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: const Color(0xFFF7F8F7),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x223F5F4A),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFF3F5F4A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Next payment: ${_formatDate(_subscriptionNextPayment)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.edit_calendar_rounded, size: 18, color: Color(0xFF3F5F4A)),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      InfaqPillField(
        controller: _subscriptionAmount,
        hintText: 'amount (e.g., 6.5)',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 44,
        child: FilledButton(
          onPressed: _addSubscription,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3F5F4A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            elevation: 0,
          ),
          child: const Text('Add subscription', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      if (_subscriptions.isEmpty) ...[
        const SizedBox(height: 16),
        Text(
          'No subscriptions added yet.',
          style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontWeight: FontWeight.w600),
        ),
      ] else ...[
        const SizedBox(height: 14),
        ..._subscriptions.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _SubscriptionPreviewTile(
                  title: entry.value.name,
                  subtitle:
                      '${entry.value.billing == 'yearly' ? 'Yearly' : 'Monthly'} • ${_formatDate(entry.value.nextPayment)}',
                  amount: _currency == null ? '\$${entry.value.amount}' : '${_currency!} ${entry.value.amount}',
                  onRemove: () => _removeSubscription(entry.key),
                ),
              ),
            ),
      ],
      const SizedBox(height: 14),
      _SectionPillLabel(
        label: 'Add your Goals',
        icon: Icons.track_changes_rounded,
      ),
      InfaqPillField(
        controller: _goals,
        hintText: 'Goals',
        textInputAction: TextInputAction.done,
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: FilledButton(
          onPressed: () => showInfaqSnack(context, 'SMS access not wired yet.'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: const Text('Add SMS Access', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}

class _SubscriptionDraft {
  const _SubscriptionDraft({
    required this.name,
    required this.billing,
    required this.amount,
    required this.nextPayment,
  });

  final String name;
  final String billing;
  final double amount;
  final DateTime nextPayment;
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.7),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionPillLabel extends StatelessWidget {
  const _SectionPillLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EFEA),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Icon(icon, size: 18),
        ],
      ),
    );
  }
}

class _SubscriptionPreviewTile extends StatelessWidget {
  const _SubscriptionPreviewTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    this.onRemove,
  });

  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                title.isNotEmpty ? title[0].toUpperCase() : 'S',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (onRemove != null) ...[
                const SizedBox(height: 8),
                IconButton(
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF3F5F4A)),
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }
}


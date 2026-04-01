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

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _currency = 'BHD';
  final _balance = TextEditingController();

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    // Rebuild so the strength label updates while typing.
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _balance.dispose();
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

  Future<void> _next() async {
    if (_step == 1) {
      if (_fullName.text.trim().isEmpty ||
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

    final balanceText = _balance.text.trim();
    if (balanceText.isEmpty) {
      showInfaqSnack(context, 'Enter your balance.');
      return;
    }
    if (double.tryParse(balanceText) == null) {
      showInfaqSnack(context, 'Balance must be a number.');
      return;
    }

    await _signUp();
  }

  Future<void> _signUp() async {
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final usernameFromEmail =
          email.contains('@') ? email.split('@').first : email;
      final parsedBalance = num.tryParse(_balance.text.trim());
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _password.text,
        data: {
          'username': usernameFromEmail,
          'name': _fullName.text.trim(),
          'full_name': _fullName.text.trim(),
          'currency': _currency,
          // String + numeric both survive JWT/user_metadata round-trips reliably.
          'balance': _balance.text.trim(),
        },
      );
      final signedInUser = response.session?.user ?? response.user;
      if (signedInUser != null && parsedBalance != null) {
        try {
          await _upsertUserRow(
            userId: signedInUser.id,
            name: _fullName.text.trim(),
            username: usernameFromEmail,
            currency: _currency,
            balance: parsedBalance,
          );
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(data: const {'registration_synced': true}),
          );
        } catch (_) {
          // No session after sign-up (e.g. email confirm) or RLS: first login syncs in main.dart.
        }
      }
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

  Future<void> _upsertUserRow({
    required String userId,
    required String name,
    required String username,
    required String? currency,
    required num? balance,
  }) async {
    await Supabase.instance.client.from('users').upsert(
      <String, Object?>{
        'id': userId,
        'name': name,
        'username': username,
        'currency': currency ?? 'BHD',
        'Balance': (balance ?? 0).toDouble(),
      },
      onConflict: 'id',
    );
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
        child: SizedBox(
          width: double.infinity,
          child: DropdownMenu<String>(
            key: ValueKey<String?>(_currency),
            initialSelection: _currency,
            expandedInsets: EdgeInsets.zero,
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
      ),
      const SizedBox(height: 14),
      const _FieldLabel('Balance'),
      InfaqPillField(
        controller: _balance,
        hintText: '0.00',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
      ),
    ];
  }
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



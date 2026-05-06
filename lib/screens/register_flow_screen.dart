import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Strong password: at least this many characters (12–16+ recommended in UI copy).
const int _kPasswordMinLength = 12;

class RegisterFlowScreen extends StatefulWidget {
  const RegisterFlowScreen({super.key});

  @override
  State<RegisterFlowScreen> createState() => _RegisterFlowScreenState();
}

class _RegisterFlowScreenState extends State<RegisterFlowScreen> {
  int _step = 1;
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;

  StreamSubscription<AuthState>? _authSub;

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _currency = 'BHD';
  final _balance = TextEditingController();

  @override
  void initState() {
    super.initState();
    _password.addListener(_onPasswordChanged);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session == null) return;
      if (!mounted) return;
      if (!Navigator.of(context).canPop()) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      });
    });
  }

  void _onPasswordChanged() {
    // Rebuild so the strength label updates while typing.
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _fullName.dispose();
    _email.dispose();
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kOAuthRedirectTo,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  bool get _passwordStrong {
    final p = _password.text;
    if (p.length < _kPasswordMinLength) return false;
    if (!RegExp(r'[A-Z]').hasMatch(p)) return false;
    if (!RegExp(r'[a-z]').hasMatch(p)) return false;
    if (!RegExp(r'\d').hasMatch(p)) return false;
    return true;
  }

  String? _passwordRequirementHint() {
    final p = _password.text;
    if (p.isEmpty) return null;
    final missing = <String>[];
    if (p.length < _kPasswordMinLength) {
      missing.add('at least $_kPasswordMinLength characters (longer is better)');
    }
    if (!RegExp(r'[A-Z]').hasMatch(p)) missing.add('an uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(p)) missing.add('a lowercase letter');
    if (!RegExp(r'\d').hasMatch(p)) missing.add('a number');
    if (missing.isEmpty) return null;
    return 'Add: ${missing.join(', ')}.';
  }

  void _showPasswordHelpDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Strong password tips'),
          content: Text(
            'Length: use at least $_kPasswordMinLength characters; 12–16 or longer is recommended.\n\n'
            'Complexity: include uppercase (A–Z), lowercase (a–z), and numbers (0–9). '
            'Adding symbols (!@#\$%^&*, etc.) is optional but improves strength.\n\n'
            'Example: MyFamilyBudget2026',
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
      final name = _fullName.text.trim();
      final email = _email.text.trim();

      if (name.isEmpty) {
        showInfaqSnack(context, 'Name is empty. Please enter your full name.');
        return;
      }
      if (email.isEmpty) {
        showInfaqSnack(context, 'Email is empty. Please enter your email address.');
        return;
      }
      if (!_isValidEmail(email)) {
        showInfaqSnack(context, 'Please enter a valid email address.');
        return;
      }
      if (_password.text.isEmpty) {
        showInfaqSnack(context, 'Password is empty. Please create a password.');
        return;
      }
      if (!_passwordStrong) {
        final hint = _passwordRequirementHint();
        showInfaqSnack(
          context,
          hint ??
              'Password must be at least $_kPasswordMinLength characters with uppercase, lowercase, and a number.',
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

  void _onRegistrationBack() {
    if (_step > 1) {
      setState(() => _step--);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onRegistrationBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              InfaqHeader(showBack: true, onBack: _onRegistrationBack),
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
                    onPressed: _googleLoading ? null : _next,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ', style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
                      InfaqTextButton(
                        label: 'Sign in',
                        onTap: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  List<Widget> _buildStep1(BuildContext context) {
    return [
      const _FieldLabel('Name'),
      InfaqPillField(
        controller: _fullName,
        hintText: 'full name (e.g., Ahmed Ali)',
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
      ),
      const SizedBox(height: 14),
      const _FieldLabel('Email'),
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
          _password.text.isEmpty
              ? 'weak'
              : _passwordStrong
                  ? 'strong'
                  : 'weak',
          style: TextStyle(
            color: _password.text.isEmpty || !_passwordStrong
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.green.withValues(alpha: 0.85),
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
      const SizedBox(height: 22),
      _OrDividerLine(color: Colors.black.withValues(alpha: 0.12)),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final gap = maxW < 340 ? 14.0 : 20.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(
                icon: FontAwesomeIcons.apple,
                onTap: _loading || _googleLoading
                    ? null
                    : () => showInfaqSnack(context, 'Apple sign-in is not available yet.'),
              ),
              SizedBox(width: gap),
              _SocialIcon(
                icon: FontAwesomeIcons.google,
                onTap: _loading || _googleLoading ? null : _signUpWithGoogle,
                loading: _googleLoading,
              ),
              SizedBox(width: gap),
              _SocialIcon(
                icon: FontAwesomeIcons.facebookF,
                onTap: _loading || _googleLoading
                    ? null
                    : () => showInfaqSnack(context, 'Facebook sign-in is not available yet.'),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 4),
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

/// Matches [LoginScreen] divider + social control styling without editing the sign-in file.
class _OrDividerLine extends StatelessWidget {
  const _OrDividerLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: color)),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: loading || onTap == null ? null : onTap,
      radius: 26,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: Color(0x11000000), blurRadius: 12, offset: Offset(0, 6)),
          ],
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3F5F4A)),
              )
            : FaIcon(icon, size: 20, color: Colors.black87),
      ),
    );
  }
}



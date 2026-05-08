import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/services/auth_navigation_service.dart';
import 'package:infaq/services/bank_notification_sync_service.dart';
import 'package:infaq/services/notification_preferences_service.dart';
import 'package:infaq/ui/infaq_currency_meta.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Strong password: at least this many characters (12–16+ recommended in UI copy).
const int _kPasswordMinLength = 12;

/// Matches [NotificationSettingsScreen] guidance / primary green for consistency.
const Color _kRegisterGuidancePrimary = Color(0xFF4D6658);
const Color _kRegisterGuidanceBgLight = Color(0xFFEEF7F0);
const Color _kRegisterGuidanceBorderLight = Color(0xFFD4E3D8);

bool get _isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class RegisterFlowScreen extends StatefulWidget {
  const RegisterFlowScreen({super.key});

  @override
  State<RegisterFlowScreen> createState() => _RegisterFlowScreenState();
}

class _RegisterFlowScreenState extends State<RegisterFlowScreen>
    with WidgetsBindingObserver {
  int _step = 1;
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;

  /// When true, after sign-up we enable automatic bank-notification recording in Supabase prefs.
  bool _autoBankTransactions = false;
  bool _notificationListenerEnabled = false;

  StreamSubscription<AuthState>? _authSub;

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _currency = 'BHD';
  final _balance = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _password.addListener(_onPasswordChanged);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint(
        '[AuthNav] register onAuthStateChange event=${data.event} '
        'hasSession=${data.session != null}',
      );
      if (data.session == null) return;
      if (!mounted) return;
      AuthNavigationService.clearAuthOverlaysIfSignedIn(
        context,
        reason: 'register_listener_${data.event.name}',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        mounted &&
        _step == 2 &&
        _autoBankTransactions) {
      unawaited(_refreshNotificationListenerStatus());
    }
  }

  Future<void> _refreshNotificationListenerStatus() async {
    final enabled = await BankNotificationSyncService.instance
        .isNotificationListenerEnabled();
    if (!mounted) return;
    setState(() => _notificationListenerEnabled = enabled);
  }

  void _onAutoBankTransactionsChanged(bool v) {
    setState(() => _autoBankTransactions = v);
    if (v) {
      unawaited(_refreshNotificationListenerStatus());
    }
  }

  void _onPasswordChanged() {
    // Rebuild so the strength label updates while typing.
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _fullName.dispose();
    _email.dispose();
    _password.removeListener(_onPasswordChanged);
    _password.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _signUpWithGoogle() async {
    debugPrint('[AuthNav] sign-up start (Google OAuth)');
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
    debugPrint('[AuthNav] sign-up start (email/password)');
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
      var session = response.session;
      final user = response.user;

      if (session == null && user != null) {
        debugPrint('[AuthNav] sign-up: response session null, polling…');
        session = await AuthNavigationService.waitForSession(
          timeout: const Duration(seconds: 2),
        );
      }
      if (!mounted) return;

      if (user != null && parsedBalance != null && session != null) {
        try {
          debugPrint('[AuthNav] profile upsert start user=${user.id}');
          await _upsertUserRow(
            userId: user.id,
            name: _fullName.text.trim(),
            username: usernameFromEmail,
            currency: _currency,
            balance: parsedBalance,
          );
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(data: const {'registration_synced': true}),
          );
          debugPrint('[AuthNav] profile upsert + metadata update success');
          if (_autoBankTransactions) {
            try {
              await NotificationPreferencesService.instance
                  .loadOrCreateForSettings();
              await NotificationPreferencesService.instance
                  .updateSmsAutoRecordingEnabled(true);
              unawaited(
                BankNotificationSyncService.instance
                    .syncPendingBankTransactions(
                  trigger: 'register_auto_recording_enabled',
                  bypassThrottle: true,
                ),
              );
            } catch (e, st) {
              debugPrint(
                '[AuthNav] register auto-recording prefs failed: $e\n$st',
              );
            }
          }
        } catch (e, st) {
          debugPrint(
            '[AuthNav] profile upsert failed (AuthGate may show setup): $e\n$st',
          );
        }
      }

      if (!mounted) return;

      if (session != null) {
        debugPrint('[AuthNav] sign-up success with session user=${user?.id}');
        if (mounted) {
          showInfaqSnack(context, 'Welcome! Finishing sign-up…');
        }
        AuthNavigationService.clearAuthOverlaysIfSignedIn(
          context,
          reason: 'email_sign_up',
        );
      } else if (user != null) {
        debugPrint(
          '[AuthNav] sign-up: no session (email confirmation) user=${user.id}',
        );
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: const Text('Verify your email'),
              content: const Text(
                'Please verify your email before signing in. We sent you a link — '
                'open it to activate your account, then use Sign in.\n\n'
                'You are not signed in yet in this app.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'OK',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                  child: const Text('Go to Sign in'),
                ),
              ],
            );
          },
        );
      } else {
        debugPrint('[AuthNav] sign-up: no user in response');
        showInfaqSnack(
          context,
          'Could not complete sign-up. Check your details and try again.',
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('[AuthNav] sign-up AuthException: ${e.message}');
      showInfaqSnack(context, e.message);
    } catch (e, st) {
      debugPrint('[AuthNav] sign-up error: $e\n$st');
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onRegistrationBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: theme.scaffoldBackgroundColor,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: ListView(
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
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _step == 1
                        ? 'Start your journey to better financial health'
                        : 'Set your budget currency and optional auto-import',
                    style: TextStyle(color: muted),
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
                      Text('Already have an account? ', style: TextStyle(color: muted)),
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
          icon: Icon(
            _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
          icon: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          label: Text(
            'How to write a strong password',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      const _OrDividerLine(),
      const SizedBox(height: 16),
      InfaqGoogleAuthButton(
        onPressed: _loading || _googleLoading ? null : _signUpWithGoogle,
        isLoading: _googleLoading,
        label: 'Sign up with Google',
      ),
      const SizedBox(height: 4),
    ];
  }

  List<Widget> _buildStep2(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final guidanceBg =
        isDark ? cs.surfaceContainerHigh : _kRegisterGuidanceBgLight;
    final guidanceBorder = isDark
        ? cs.outline.withValues(alpha: 0.35)
        : _kRegisterGuidanceBorderLight;

    return [
      const _FieldLabel('Balance'),
      InfaqPillField(
        controller: _balance,
        hintText: '0.00',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 14),
      const _FieldLabel('currency'),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Color(isDark ? 0x59000000 : 0x223F5F4A),
              blurRadius: 14,
              offset: const Offset(0, 6),
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
            dropdownMenuEntries: [
              for (final c in InfaqCurrencyMeta.orderedCodes)
                DropdownMenuEntry<String>(
                  value: c,
                  label: InfaqCurrencyMeta.menuLabel(c),
                  leadingIcon: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InfaqCurrencyMeta.flagOrFallback(context, c, size: 20),
                  ),
                ),
            ],
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: cs.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Add transactions from bank alerts',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: cs.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Text(
            'Let INFAQ read transaction notifications from your bank (for example SMS or payment alerts) '
            'and turn them into expenses in your account. You stay in control: you can turn this off anytime in Profile → Notifications.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: muted,
            ),
          ),
        ),
        value: _autoBankTransactions,
        onChanged: _loading ? null : _onAutoBankTransactionsChanged,
        activeTrackColor: isDark ? cs.primary : _kRegisterGuidancePrimary,
        activeThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade300,
        inactiveThumbColor: Colors.grey.shade400,
      ),
      if (_autoBankTransactions) ...[
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            _notificationListenerEnabled
                ? 'Notification access enabled'
                : 'Notification access not enabled yet',
            style: TextStyle(
              color: _notificationListenerEnabled ? cs.primary : cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          trailing: Icon(
            _notificationListenerEnabled
                ? Icons.check_circle
                : Icons.error_outline,
            color: _notificationListenerEnabled ? cs.primary : Colors.orange,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: guidanceBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: guidanceBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: isDark ? cs.primary : _kRegisterGuidancePrimary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isAndroidPlatform
                      ? 'To finish setup after you create your account:\n'
                          '1. Tap Open Android settings below.\n'
                          '2. Choose INFAQ and allow notification access.\n'
                          '3. Keep notifications from your banking apps turned on so alerts can be detected.\n\n'
                          'INFAQ only uses this to spot payment amounts and merchants from alerts you already receive — not to read unrelated messages.'
                      : 'After you sign up, open Profile → Notifications to allow notification access where your device supports automatic import (for example on Android). '
                          'You can finish setup there anytime.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isAndroidPlatform) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading
                ? null
                : () async {
                    await BankNotificationSyncService.instance
                        .openNotificationListenerSettings();
                  },
            child: const Text('Open Android settings'),
          ),
        ],
      ],
    ];
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.72),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Matches [LoginScreen] divider + social control styling without editing the sign-in file.
class _OrDividerLine extends StatelessWidget {
  const _OrDividerLine();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final line = cs.outline.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.22);

    return Row(
      children: [
        Expanded(child: Divider(height: 1, thickness: 1, color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(child: Divider(height: 1, thickness: 1, color: line)),
      ],
    );
  }
}



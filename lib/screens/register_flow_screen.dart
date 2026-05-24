import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/auth/password_recovery_state.dart';
import 'package:infaq/auth/password_policy.dart';
import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/services/auth_navigation_service.dart';
import 'package:infaq/services/bank_notification_sync_service.dart';
import 'package:infaq/services/email_confirm_deep_link_service.dart';
import 'package:infaq/services/notification_preferences_service.dart';
import 'package:infaq/ui/infaq_currency_meta.dart';
import 'package:infaq/ui/infaq_password_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

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
  bool _awaitingEmailConfirmation = false;
  bool _emailConfirmDialogOpen = false;
  bool _resendingEmail = false;
  bool _registrationEmailVerified = false;
  bool _ownsEmailConfirmHandler = false;

  StreamSubscription<AuthState>? _authSub;

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _currency = 'BHD';
  final _balance = TextEditingController();

  String? _emailInlineError;

  static const List<String> _kDuplicateEmailPhrases = [
    'already registered',
    'already exists',
    'user already registered',
    'email already registered',
    'email already exists',
    'user already exists',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _password.addListener(_onPasswordChanged);
    _email.addListener(_onEmailChanged);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint(
        '[AuthNav] register onAuthStateChange event=${data.event} '
        'hasSession=${data.session != null}',
      );
      if (data.event == AuthChangeEvent.passwordRecovery) {
        PasswordRecoveryState.markPending();
        return;
      }
      if (PasswordRecoveryState.isPasswordRecoveryMode) {
        return;
      }
      final session = data.session;
      if (session == null) return;
      if (!mounted) return;
      if (_awaitingEmailConfirmation || _registrationEmailVerified) {
        unawaited(_handleEmailVerificationSession(session));
        return;
      }
      AuthNavigationService.clearAuthOverlaysIfSignedIn(
        context,
        reason: 'register_listener_${data.event.name}',
      );
    });
    EmailConfirmDeepLinkService.instance.onResult = _onEmailConfirmDeepLinkResult;
    _ownsEmailConfirmHandler = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      if (_step == 2 && _autoBankTransactions) {
        unawaited(_refreshNotificationListenerStatus());
      }
      if (_awaitingEmailConfirmation) {
        debugPrint('[EmailConfirm] verification link opened');
        unawaited(_tryCompleteEmailConfirmation(fromResume: true));
      }
    }
  }

  void _onEmailConfirmDeepLinkResult(EmailConfirmDeepLinkResult result) {
    if (!mounted) return;
    if (PasswordRecoveryState.isPasswordRecoveryMode) return;
    switch (result) {
      case EmailConfirmDeepLinkResult.notHandled:
      case EmailConfirmDeepLinkResult.failed:
        return;
      case EmailConfirmDeepLinkResult.verifiedWithSession:
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null &&
            (_awaitingEmailConfirmation ||
                _registrationEmailVerified ||
                _step == 2)) {
          unawaited(_handleEmailVerificationSession(session));
        }
        return;
      case EmailConfirmDeepLinkResult.verifiedNoSession:
        if (_awaitingEmailConfirmation ||
            _emailConfirmDialogOpen ||
            _step == 2) {
          _showEmailVerifiedSignInFallback();
        }
        return;
      case EmailConfirmDeepLinkResult.passwordRecovery:
        return;
    }
  }

  void _showEmailVerifiedSignInFallback() {
    if (!mounted) return;
    debugPrint('[EmailConfirm] fallback to sign in');
    if (_emailConfirmDialogOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _emailConfirmDialogOpen = false;
    _awaitingEmailConfirmation = false;
    showInfaqSnack(context, 'Email verified. Please sign in to continue.');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  bool _isEmailConfirmed(User user) {
    return user.emailConfirmedAt != null && user.emailConfirmedAt!.isNotEmpty;
  }

  Future<void> _tryCompleteEmailConfirmation({bool fromResume = false}) async {
    await EmailConfirmDeepLinkService.refreshAuthAfterCallback();
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint('[EmailConfirm] session exists=${session != null}');
    if (session == null) {
      if (fromResume) return;
      return;
    }
    await _handleEmailVerificationSession(session);
  }

  Future<void> _handleEmailVerificationSession(Session session) async {
    await EmailConfirmDeepLinkService.refreshAuthAfterCallback();
    session = Supabase.instance.client.auth.currentSession ?? session;
    final user = session.user;
    final confirmed = _isEmailConfirmed(user);
    debugPrint('[EmailConfirm] session exists=true');
    debugPrint('[EmailConfirm] email confirmed=$confirmed');
    if (!confirmed && !_awaitingEmailConfirmation) return;

    if (!mounted) return;

    if (_emailConfirmDialogOpen && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _emailConfirmDialogOpen = false;
    _awaitingEmailConfirmation = false;
    _registrationEmailVerified = true;

    var setupComplete = await _isRegistrationSetupComplete(user.id);
    if (setupComplete) {
      debugPrint('[EmailConfirm] moving to home');
      if (!mounted) return;
      AuthNavigationService.clearAuthOverlaysIfSignedIn(
        context,
        reason: 'email_confirmed_setup_complete',
      );
      return;
    }

    debugPrint('[EmailConfirm] continuing to setup');
    setState(() => _step = 2);

    final parsedBalance = num.tryParse(_balance.text.trim());
    if (parsedBalance != null) {
      await _completeRegistrationForUser(user, session);
      if (!mounted) return;
      setupComplete = await _isRegistrationSetupComplete(user.id);
      if (setupComplete) {
        debugPrint('[EmailConfirm] moving to home');
        if (!mounted) return;
        AuthNavigationService.clearAuthOverlaysIfSignedIn(
          context,
          reason: 'email_confirmed_after_upsert',
        );
        return;
      }
    }

    if (!mounted) return;
    showInfaqSnack(
      context,
      'Email verified! Review your details and tap Sign up to finish.',
    );
  }

  Future<bool> _isRegistrationSetupComplete(String userId) async {
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return row != null;
    } catch (e, st) {
      debugPrint('[EmailConfirm] users row check failed: $e\n$st');
      return false;
    }
  }

  Future<void> _completeRegistrationForUser(User user, Session session) async {
    final email = _email.text.trim();
    final usernameFromEmail =
        email.contains('@') ? email.split('@').first : email;
    final parsedBalance = num.tryParse(_balance.text.trim());

    if (parsedBalance == null) return;

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
          await NotificationPreferencesService.instance.loadOrCreateForSettings();
          await NotificationPreferencesService.instance
              .updateSmsAutoRecordingEnabled(true);
          unawaited(
            BankNotificationSyncService.instance.syncPendingBankTransactions(
              trigger: 'register_auto_recording_enabled',
              bypassThrottle: true,
            ),
          );
        } catch (e, st) {
          debugPrint('[AuthNav] register auto-recording prefs failed: $e\n$st');
        }
      }
      if (mounted) {
        showInfaqSnack(context, 'Email verified! Finishing sign-up…');
      }
    } catch (e, st) {
      debugPrint(
        '[AuthNav] profile upsert failed (AuthGate may show setup): $e\n$st',
      );
    }
  }

  Future<void> _resendConfirmationEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    debugPrint('[EmailConfirm] resend called');
    debugPrint('[EmailConfirm] resend redirect=com.infaq.app://login-callback');
    setState(() => _resendingEmail = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kOAuthRedirectTo,
      );
      if (!mounted) return;
      showInfaqSnack(context, 'Verification email sent again.');
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, 'Could not resend email. Try again.');
    } finally {
      if (mounted) setState(() => _resendingEmail = false);
    }
  }

  Future<void> _showEmailConfirmationDialog() async {
    _awaitingEmailConfirmation = true;
    _emailConfirmDialogOpen = true;
    debugPrint('[EmailConfirm] verify email waiting state shown');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Confirm your email'),
            content: Text(
              'We sent a verification link to your email.\n\n'
              'Please check your email and tap the verification link to continue.',
              style: TextStyle(
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _resendingEmail
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _awaitingEmailConfirmation = false;
                          _emailConfirmDialogOpen = false;
                          _step = 1;
                        });
                      },
                child: Text(
                  'Change email',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: _resendingEmail ? null : () => _resendConfirmationEmail(),
                child: _resendingEmail
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Resend email'),
              ),
              FilledButton(
                onPressed: () async {
                  await _tryCompleteEmailConfirmation();
                  if (!ctx.mounted) return;
                  if (!_awaitingEmailConfirmation) return;
                  if (!mounted) return;
                  showInfaqSnack(
                    context,
                    'Still waiting for verification. Check your email and tap the link.',
                  );
                },
                child: const Text('Check again'),
              ),
            ],
          ),
        );
      },
    );
    if (mounted) {
      setState(() {
        _emailConfirmDialogOpen = false;
        if (_awaitingEmailConfirmation) _awaitingEmailConfirmation = false;
      });
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

  void _onEmailChanged() {
    if (_emailInlineError == null) return;
    if (!mounted) return;
    setState(() => _emailInlineError = null);
  }

  bool _authMessageIndicatesDuplicateEmail(String message) {
    final lower = message.toLowerCase();
    return _kDuplicateEmailPhrases.any(lower.contains);
  }

  bool _isDuplicateEmailSignUpResponse(AuthResponse response) {
    final user = response.user;
    if (user == null) return false;
    final identities = user.identities;
    return identities == null || identities.isEmpty;
  }

  void _handleDuplicateEmailSignUp() {
    debugPrint('[SignupValidation] duplicate email detected');
    debugPrint('[SignupValidation] email inline error set=Email already exists.');
    debugPrint('[SignupValidation] stopped before confirm email dialog');
    setState(() {
      _emailInlineError = 'Email already exists.';
      _step = 1;
      _awaitingEmailConfirmation = false;
      _emailConfirmDialogOpen = false;
    });
  }

  @override
  void dispose() {
    if (_ownsEmailConfirmHandler) {
      EmailConfirmDeepLinkService.instance.onResult = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _fullName.dispose();
    _email.removeListener(_onEmailChanged);
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

  bool get _passwordValid => isInfaqPasswordValid(_password.text);

  String? _passwordRequirementHint() =>
      infaqPasswordRequirementMessage(_password.text);

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
      if (!_passwordValid) {
        final hint = _passwordRequirementHint();
        showInfaqSnack(
          context,
          hint ??
              'Password must be at least $kInfaqPasswordMinLength characters with uppercase, lowercase, a number, and a symbol.',
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
    debugPrint('[EmailConfirm] signup called');
    debugPrint('[EmailConfirm] signup redirect=com.infaq.app://login-callback');
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final usernameFromEmail =
          email.contains('@') ? email.split('@').first : email;
      final parsedBalance = num.tryParse(_balance.text.trim());

      var session = Supabase.instance.client.auth.currentSession;
      if (session != null &&
          (_registrationEmailVerified || _isEmailConfirmed(session.user))) {
        await EmailConfirmDeepLinkService.refreshAuthAfterCallback();
        session = Supabase.instance.client.auth.currentSession ?? session;
        debugPrint('[EmailConfirm] session exists=true');
        debugPrint(
          '[EmailConfirm] email confirmed=${_isEmailConfirmed(session.user)}',
        );
        if (parsedBalance != null) {
          await _completeRegistrationForUser(session.user, session);
        }
        if (!mounted) return;
        final setupComplete =
            await _isRegistrationSetupComplete(session.user.id);
        if (setupComplete) {
          debugPrint('[EmailConfirm] moving to home');
          AuthNavigationService.clearAuthOverlaysIfSignedIn(
            context,
            reason: 'email_sign_up_after_confirm',
          );
        } else {
          debugPrint('[EmailConfirm] continuing to setup');
          setState(() => _step = 2);
          showInfaqSnack(
            context,
            'Email verified! Review your details and tap Sign up to finish.',
          );
        }
        return;
      }

      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _password.text,
        emailRedirectTo: kOAuthRedirectTo,
        data: {
          'username': usernameFromEmail,
          'name': _fullName.text.trim(),
          'full_name': _fullName.text.trim(),
          'currency': _currency,
          // String + numeric both survive JWT/user_metadata round-trips reliably.
          'balance': _balance.text.trim(),
        },
      );

      final signupUser = response.user;
      debugPrint('[SignupValidation] signup response userId=${signupUser?.id}');
      debugPrint(
        '[SignupValidation] signup response identitiesCount=${signupUser?.identities?.length}',
      );

      if (_isDuplicateEmailSignUpResponse(response)) {
        _handleDuplicateEmailSignUp();
        return;
      }

      session = response.session;
      final user = signupUser;

      if (session == null && user != null) {
        debugPrint('[AuthNav] sign-up: response session null, polling…');
        session = await AuthNavigationService.waitForSession(
          timeout: const Duration(seconds: 2),
        );
      }
      if (!mounted) return;

      if (user != null && parsedBalance != null && session != null) {
        await _completeRegistrationForUser(user, session);
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
        await _showEmailConfirmationDialog();
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
      if (_authMessageIndicatesDuplicateEmail(e.message)) {
        _handleDuplicateEmailSignUp();
        return;
      }
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
      if (_emailInlineError != null) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            _emailInlineError!,
            style: TextStyle(
              color: Colors.red.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
      InfaqPasswordStrengthIndicator(password: _password.text),
      const SizedBox(height: 6),
      const InfaqPasswordHelpLink(),
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



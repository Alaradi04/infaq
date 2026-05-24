import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/auth/password_recovery_state.dart';
import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/screens/forgot_password_dialog.dart';
import 'package:infaq/screens/register_flow_screen.dart';
import 'package:infaq/services/auth_navigation_service.dart';
import 'package:infaq/ui/infaq_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Google (and other OAuth) can set the session after the browser returns; pop this route then.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint(
        '[AuthNav] login onAuthStateChange event=${data.event} '
        'hasSession=${data.session != null}',
      );
      if (data.event == AuthChangeEvent.passwordRecovery) {
        PasswordRecoveryState.markPending();
        return;
      }
      if (PasswordRecoveryState.isPasswordRecoveryMode) {
        return;
      }
      if (data.session == null) return;
      if (!mounted) return;
      AuthNavigationService.clearAuthOverlaysIfSignedIn(
        context,
        reason: 'login_listener_${data.event.name}',
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (email.isEmpty || password.isEmpty) {
      showInfaqSnack(context, 'Please enter email and password.');
      return;
    }

    debugPrint('[AuthNav] sign-in start (password) email=$email');
    setState(() => _loading = true);
    var signedIn = false;
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;

      var session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        debugPrint('[AuthNav] sign-in: session null after await, polling…');
        session = await AuthNavigationService.waitForSession();
      }
      if (!mounted) return;

      if (session == null) {
        debugPrint(
          '[AuthNav] sign-in: no session after poll — email verification likely',
        );
        if (mounted) {
          showInfaqSnack(
            context,
            'Please verify your email before signing in, then try again.',
          );
        }
        return;
      }

      debugPrint('[AuthNav] sign-in success user=${session.user.id}');
      signedIn = true;
      AuthNavigationService.clearAuthOverlaysIfSignedIn(
        context,
        reason: 'password_sign_in',
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      debugPrint('[AuthNav] sign-in AuthException: ${e.message}');
      showInfaqSnack(context, e.message);
    } catch (e, st) {
      debugPrint('[AuthNav] sign-in error: $e\n$st');
      if (!mounted) return;
      showInfaqSnack(context, 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted || !signedIn) return;
  }

  Future<void> _signInWithGoogle() async {
    debugPrint('[AuthNav] sign-in start (Google OAuth)');
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

  void _forgotPassword() {
    final prefilled = _email.text.trim();
    showForgotPasswordDialog(
      context,
      initialEmail: prefilled.isEmpty ? null : prefilled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    final linkColor = scheme.primary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
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
          InfaqHeader(showBack: Navigator.of(context).canPop()),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to continue managing your finances',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 26),
                InfaqPillField(
                  controller: _email,
                  hintText: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: 14),
                InfaqPillField(
                  controller: _password,
                  hintText: 'Password',
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _signIn(),
                  autofillHints: const [AutofillHints.password],
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    'Sign in with',
                    style: TextStyle(color: muted),
                  ),
                ),
                const SizedBox(height: 10),
                InfaqGoogleAuthButton(
                  onPressed: _loading ? null : _signInWithGoogle,
                  isLoading: _googleLoading,
                  label: 'Continue with Google',
                ),
                const SizedBox(height: 16),
                Center(
                  child: InkWell(
                    onTap: _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: linkColor,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: linkColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                InfaqPrimaryButton(
                  label: 'Sign in',
                  isLoading: _loading,
                  onPressed: _googleLoading ? null : _signIn,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Don’t have an account? ', style: TextStyle(color: muted)),
                    InfaqTextButton(
                      label: 'Sign up',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterFlowScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}


import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/screens/register_flow_screen.dart';
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

    setState(() => _loading = true);
    var signedIn = false;
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (Supabase.instance.client.auth.currentSession == null) {
        showInfaqSnack(context, 'No active session. Confirm your email if sign-up required verification.');
        return;
      }
      signedIn = true;
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showInfaqSnack(context, 'Sign in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted || !signedIn) return;
    // AuthGate shows home under this route, but login was pushed above welcome — clear the stack.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _signInWithGoogle() async {
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showInfaqSnack(context, 'Enter your email first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      showInfaqSnack(context, 'Password reset email sent.');
    } on AuthException catch (e) {
      if (!mounted) return;
      showInfaqSnack(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showInfaqSnack(context, 'Could not send reset email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                const Text('Welcome back', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Sign in to continue managing your finances',
                  style: TextStyle(color: Colors.black.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 26),
                InfaqPillField(
                  controller: _email,
                  hintText: 'username or email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
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
                    icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: Text(
                    'Sign in with',
                    style: TextStyle(color: Colors.black.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SocialIcon(
                      icon: FontAwesomeIcons.apple,
                      onTap: () => showInfaqSnack(context, 'Apple sign-in is not available yet.'),
                    ),
                    const SizedBox(width: 20),
                    _SocialIcon(
                      icon: FontAwesomeIcons.google,
                      onTap: _loading ? null : _signInWithGoogle,
                      loading: _googleLoading,
                    ),
                    const SizedBox(width: 20),
                    _SocialIcon(
                      icon: FontAwesomeIcons.facebookF,
                      onTap: () => showInfaqSnack(context, 'Facebook sign-in is not available yet.'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: InkWell(
                    onTap: _forgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: const Color(0xFF3F5F4A),
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFF3F5F4A),
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
                    Text('Don’t have an account? ', style: TextStyle(color: Colors.black.withValues(alpha: 0.55))),
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


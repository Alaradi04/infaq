import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/auth/password_policy.dart';
import 'package:infaq/auth/password_recovery_state.dart';
import 'package:infaq/screens/login_screen.dart';
import 'package:infaq/ui/infaq_password_widgets.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Shown after the user opens a password recovery deep link (recovery session).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.rootNavigatorKey});

  /// Used to open [LoginScreen] after sign-out when this screen is the [AuthGate] home.
  final GlobalKey<NavigatorState>? rootNavigatorKey;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  String? _newPasswordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _newPassword.addListener(_onNewPasswordChanged);
  }

  void _onNewPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newPassword.removeListener(_onNewPasswordChanged);
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    final newPw = _newPassword.text;
    final confirmPw = _confirmPassword.text;

    String? newErr;
    String? confirmErr;

    if (newPw.isEmpty) {
      newErr = 'Please enter a new password.';
    } else if (!isInfaqPasswordValid(newPw)) {
      newErr = infaqPasswordRequirementMessage(newPw) ??
          'Password must be at least $kInfaqPasswordMinLength characters with uppercase, lowercase, a number, and a symbol.';
    }

    if (confirmPw.isEmpty) {
      confirmErr = 'Please confirm your new password.';
    } else if (newPw != confirmPw) {
      confirmErr = 'Passwords do not match.';
    }

    if (newErr != null || confirmErr != null) {
      setState(() {
        _newPasswordError = newErr;
        _confirmPasswordError = confirmErr;
      });
      return;
    }

    setState(() {
      _newPasswordError = null;
      _confirmPasswordError = null;
      _loading = true;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPw),
      );
      if (!mounted) return;

      showInfaqSnack(context, 'Password updated successfully.');

      PasswordRecoveryState.clear();
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e, st) {
        debugPrint('[PasswordRecovery] signOut after reset: $e\n$st');
      }

      if (!mounted) return;

      final nav = widget.rootNavigatorKey?.currentState;
      if (nav != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (route) => route.isFirst,
        );
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } on AuthException catch (e, st) {
      debugPrint('[PasswordRecovery] updateUser failed: ${e.message}\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      showInfaqSnack(context, 'Could not update password. Please try again.');
    } catch (e, st) {
      debugPrint('[PasswordRecovery] updateUser error: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      showInfaqSnack(context, 'Could not update password. Please try again.');
    }
  }

  Future<void> _backToSignIn() async {
    PasswordRecoveryState.clear();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e, st) {
      debugPrint('[PasswordRecovery] signOut on cancel: $e\n$st');
    }
    if (!mounted) return;
    final nav = widget.rootNavigatorKey?.currentState;
    if (nav != null) {
      nav.push(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    }
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
            InfaqHeader(showBack: true, onBack: _backToSignIn),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reset password',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your new password below.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 26),
                  InfaqPillField(
                    controller: _newPassword,
                    hintText: 'New Password',
                    obscureText: _obscureNew,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    suffix: IconButton(
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_newPasswordError != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        _newPasswordError!,
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  InfaqPasswordStrengthIndicator(password: _newPassword.text),
                  const SizedBox(height: 6),
                  const InfaqPasswordHelpLink(),
                  const SizedBox(height: 14),
                  InfaqPillField(
                    controller: _confirmPassword,
                    hintText: 'Confirm New Password',
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_loading) _updatePassword();
                    },
                    autofillHints: const [AutofillHints.newPassword],
                    suffix: IconButton(
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_confirmPasswordError != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        _confirmPasswordError!,
                        style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  InfaqPrimaryButton(
                    label: 'Update password',
                    isLoading: _loading,
                    onPressed: _updatePassword,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: InkWell(
                      onTap: _loading ? null : _backToSignIn,
                      child: Text(
                        'Back to Sign in',
                        style: TextStyle(
                          color: linkColor,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: linkColor,
                        ),
                      ),
                    ),
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

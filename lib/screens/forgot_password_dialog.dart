import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/auth/password_policy.dart';
import 'package:infaq/oauth_redirect.dart';
import 'package:infaq/ui/infaq_widgets.dart';

/// Asks for email and sends a Supabase password reset link.
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String? initialEmail,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _ForgotPasswordDialog(
      parentContext: context,
      initialEmail: initialEmail,
    ),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({
    required this.parentContext,
    this.initialEmail,
  });

  final BuildContext parentContext;
  final String? initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _email;
  String? _emailError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Please enter your email address.');
      return;
    }
    if (!isValidEmailFormat(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _emailError = null;
      _loading = true;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kOAuthRedirectTo,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      showInfaqSnack(
        widget.parentContext,
        'Password reset link sent. Please check your email.',
      );
    } on AuthException {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      showInfaqSnack(
        widget.parentContext,
        'Password reset link sent. Please check your email.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showInfaqSnack(context, 'Could not send reset email. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);

    return AlertDialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Forgot password?',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your email and we’ll send you a link to reset your password.',
              style: TextStyle(color: muted, height: 1.35),
            ),
            const SizedBox(height: 18),
            InfaqPillField(
              controller: _email,
              hintText: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_loading) _submit();
              },
              autofillHints: const [AutofillHints.email],
            ),
            if (_emailError != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _emailError!,
                  style: TextStyle(
                    color: Colors.red.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.primary,
          ),
          child: _loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimary,
                  ),
                )
              : const Text('Send reset link'),
        ),
      ],
    );
  }
}

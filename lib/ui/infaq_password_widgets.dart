import 'package:flutter/material.dart';

import 'package:infaq/auth/password_policy.dart';

/// Strength label shown under a password field (Weak / Moderate / Strong).
class InfaqPasswordStrengthIndicator extends StatelessWidget {
  const InfaqPasswordStrengthIndicator({
    super.key,
    required this.password,
  });

  final String password;

  Color _colorForStrength(InfaqPasswordStrength strength) {
    switch (strength) {
      case InfaqPasswordStrength.weak:
        return Colors.red.withValues(alpha: 0.85);
      case InfaqPasswordStrength.moderate:
        return const Color(0xFFE08A2E);
      case InfaqPasswordStrength.strong:
        return Colors.green.withValues(alpha: 0.85);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = infaqPasswordStrength(password);
    final label = password.isEmpty
        ? infaqPasswordStrengthLabel(InfaqPasswordStrength.weak)
        : infaqPasswordStrengthLabel(strength);

    return Align(
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: _colorForStrength(
            password.isEmpty ? InfaqPasswordStrength.weak : strength,
          ),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Opens the shared password tips dialog.
void showInfaqPasswordHelpDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Create a strong password'),
        content: const Text(
          'Use at least 8 characters and include all of the following:\n'
          '• One uppercase letter\n'
          '• One lowercase letter\n'
          '• One number\n'
          '• One symbol, such as ! @ # \$ %\n\n'
          'For better security, avoid using your name, email, phone number, or common words.\n\n'
          'Example:\n'
          'Infaq@2026',
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

/// Help link below the password strength indicator.
class InfaqPasswordHelpLink extends StatelessWidget {
  const InfaqPasswordHelpLink({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => showInfaqPasswordHelpDialog(context),
        icon: Icon(Icons.info_outline_rounded, size: 18, color: primary),
        label: Text(
          'How to write a strong password',
          style: TextStyle(fontWeight: FontWeight.w700, color: primary),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/screens/welcome_screen.dart';
import 'package:infaq/ui/infaq_widgets.dart';

class AuthLogoutService {
  const AuthLogoutService._();

  static Future<void> logoutAndResetNavigation(
    BuildContext context, {
    Future<void> Function()? onBeforeSignOut,
  }) async {
    try {
      await onBeforeSignOut?.call();
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (context.mounted) {
        showInfaqSnack(context, 'Could not log out right now. Please try again.');
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }
}

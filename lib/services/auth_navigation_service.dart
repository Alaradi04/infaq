import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Clears routes pushed above [AuthGate] (login / register) once a session exists.
/// Single debounced entry point so auth forms and auth listeners do not fight each other.
class AuthNavigationService {
  AuthNavigationService._();

  static DateTime? _lastPopAt;

  /// Short poll for session right after sign-in/sign-up (handles rare async timing gaps).
  static Future<Session?> waitForSession({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final s = Supabase.instance.client.auth.currentSession;
      if (s != null) {
        debugPrint('[AuthNav] session found after poll user=${s.user.id}');
        return s;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    final last = Supabase.instance.client.auth.currentSession;
    debugPrint('[AuthNav] session poll finished hasSession=${last != null}');
    return last;
  }

  /// Pops all routes until the root (MaterialApp home / [AuthGate]) when [currentSession] is non-null.
  /// Safe to call from password sign-in, sign-up, or [onAuthStateChange] (e.g. OAuth).
  static void clearAuthOverlaysIfSignedIn(
    BuildContext context, {
    required String reason,
  }) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      debugPrint('[AuthNav] clearAuthOverlays skipped: no session ($reason)');
      return;
    }
    if (!context.mounted) {
      debugPrint('[AuthNav] clearAuthOverlays skipped: unmounted ($reason)');
      return;
    }

    final now = DateTime.now();
    if (_lastPopAt != null &&
        now.difference(_lastPopAt!) < const Duration(milliseconds: 500)) {
      debugPrint('[AuthNav] clearAuthOverlays debounced ($reason)');
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        debugPrint('[AuthNav] clearAuthOverlays postFrame: unmounted ($reason)');
        return;
      }
      final s = Supabase.instance.client.auth.currentSession;
      if (s == null) {
        debugPrint('[AuthNav] clearAuthOverlays postFrame: session gone ($reason)');
        return;
      }
      final nav = Navigator.of(context, rootNavigator: true);
      if (!nav.canPop()) {
        debugPrint('[AuthNav] clearAuthOverlays: nothing to pop ($reason)');
        _lastPopAt = DateTime.now();
        return;
      }
      debugPrint(
        '[AuthNav] navigation decision: popUntil(isFirst) reason=$reason user=${s.user.id}',
      );
      nav.popUntil((route) => route.isFirst);
      _lastPopAt = DateTime.now();
    });
  }
}

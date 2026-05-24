import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tracks password recovery until the user sets a new password.
class PasswordRecoveryState extends ChangeNotifier {
  PasswordRecoveryState._();

  static final PasswordRecoveryState instance = PasswordRecoveryState._();

  static GlobalKey<NavigatorState>? _rootNavigatorKey;

  bool _pendingPasswordReset = false;

  /// True while the user must complete [ResetPasswordScreen] before normal auth routing.
  static bool get isPasswordRecoveryMode => instance._pendingPasswordReset;

  static bool get pendingPasswordReset => isPasswordRecoveryMode;

  /// Binds the app root navigator so recovery can dismiss Login/Register overlays.
  static void bindRootNavigator(GlobalKey<NavigatorState> key) {
    _rootNavigatorKey = key;
  }

  static void markPending() {
    if (instance._pendingPasswordReset) {
      _popRoutesAboveAuthGate();
      return;
    }
    instance._pendingPasswordReset = true;
    debugPrint('[PasswordRecovery] isPasswordRecoveryMode=true');
    _popRoutesAboveAuthGate();
    instance.notifyListeners();
  }

  static void clear() {
    if (!instance._pendingPasswordReset) return;
    instance._pendingPasswordReset = false;
    debugPrint('[PasswordRecovery] isPasswordRecoveryMode=false');
    instance.notifyListeners();
  }

  /// Removes routes pushed above [AuthGate] (e.g. [LoginScreen] after forgot password).
  static void _popRoutesAboveAuthGate() {
    void pop() {
      final nav = _rootNavigatorKey?.currentState;
      if (nav == null || !nav.canPop()) return;
      debugPrint('[PasswordRecovery] popUntil root — show ResetPassword under AuthGate');
      nav.popUntil((route) => route.isFirst);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      pop();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => pop());
    }
  }
}

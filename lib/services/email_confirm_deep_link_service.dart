import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/auth/password_recovery_state.dart';
import 'package:infaq/oauth_redirect.dart';

enum EmailConfirmDeepLinkResult {
  notHandled,
  verifiedWithSession,
  verifiedNoSession,
  failed,
  passwordRecovery,
}

/// Handles `com.infaq.app://login-callback` from signup email confirmation and OAuth.
///
/// Supabase [{{ .ConfirmationURL }}] may arrive as PKCE `?code=...` (handled via
/// [GoTrueClient.getSessionFromUrl]) or as `.../auth/confirm?token_hash=...`
/// (handled via [GoTrueClient.verifyOTP]).
class EmailConfirmDeepLinkService {
  EmailConfirmDeepLinkService._();

  static final EmailConfirmDeepLinkService instance =
      EmailConfirmDeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _uriSub;
  StreamSubscription<AuthState>? _authRecoverySub;
  final Set<String> _handledUris = <String>{};

  void Function(EmailConfirmDeepLinkResult result)? onResult;

  /// Fired when a password recovery deep link establishes a session (not signup confirm).
  void Function()? onPasswordRecovery;

  /// Refreshes Supabase session/user after an auth callback (email confirm or OAuth).
  static Future<void> refreshAuthAfterCallback() async {
    debugPrint('[EmailConfirm] session refresh started');
    final auth = Supabase.instance.client.auth;
    try {
      await auth.refreshSession();
    } on AuthException catch (e, st) {
      debugPrint('[EmailConfirm] refreshSession failed: ${e.message}\n$st');
    } catch (e, st) {
      debugPrint('[EmailConfirm] refreshSession error: $e\n$st');
    }
    try {
      await auth.getUser();
    } on AuthException catch (e, st) {
      debugPrint('[EmailConfirm] getUser failed: ${e.message}\n$st');
    } catch (e, st) {
      debugPrint('[EmailConfirm] getUser error: $e\n$st');
    }
  }

  Future<void> start() async {
    // Must be registered before [getInitialLink] / PKCE exchange so
    // [AuthChangeEvent.passwordRecovery] is not missed on cold start.
    await _authRecoverySub?.cancel();
    _authRecoverySub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        debugPrint('[PasswordRecovery] auth event received');
        PasswordRecoveryState.markPending();
        onPasswordRecovery?.call();
      }
    });

    await _uriSub?.cancel();
    _uriSub = _appLinks.uriLinkStream.listen(
      _onUri,
      onError: (Object e, StackTrace st) {
        debugPrint('[EmailConfirm] deeplink stream error: $e\n$st');
      },
    );

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _onUri(initial);
      }
    } catch (e, st) {
      debugPrint('[EmailConfirm] getInitialLink error: $e\n$st');
    }
  }

  void dispose() {
    _uriSub?.cancel();
    _uriSub = null;
    _authRecoverySub?.cancel();
    _authRecoverySub = null;
    onResult = null;
    onPasswordRecovery = null;
  }

  /// Recovery / reset-password callback (backup when [AuthChangeEvent.passwordRecovery] is delayed).
  @visibleForTesting
  static bool isPasswordRecoveryUri(Uri uri) {
    if (!isInfaqLoginCallback(uri)) return false;

    final queryType = uri.queryParameters['type'];
    if (queryType != null && queryType.toLowerCase() == 'recovery') {
      return true;
    }
    if (uri.fragment.isNotEmpty) {
      final frag = Uri.splitQueryString(uri.fragment);
      final fragType = frag['type'];
      if (fragType != null && fragType.toLowerCase() == 'recovery') {
        return true;
      }
    }

    final lower = uri.toString().toLowerCase();
    if (lower.contains('type=recovery')) return true;
    if (lower.contains('recovery')) return true;
    if (lower.contains('reset')) return true;
    return false;
  }

  /// Any redirect to the mobile app callback host.
  @visibleForTesting
  static bool isInfaqLoginCallback(Uri uri) {
    return uri.scheme == 'com.infaq.app' && uri.host == 'login-callback';
  }

  /// `.../auth/confirm?token_hash=...&type=email` style link.
  @visibleForTesting
  static bool hasEmailConfirmTokenHash(Uri uri) {
    if (!isInfaqLoginCallback(uri)) return false;
    final tokenHash = uri.queryParameters['token_hash'];
    if (tokenHash == null || tokenHash.isEmpty) return false;
    final path = uri.path;
    return path.contains('auth/confirm') ||
        uri.pathSegments.contains('confirm');
  }

  static OtpType mapOtpType(String? rawType) {
    switch (rawType?.toLowerCase()) {
      case 'signup':
        return OtpType.signup;
      case 'email':
        return OtpType.email;
      case 'recovery':
        return OtpType.recovery;
      case 'magiclink':
        return OtpType.magiclink;
      case 'email_change':
      case 'emailchange':
        return OtpType.emailChange;
      default:
        return OtpType.signup;
    }
  }

  Future<void> _onUri(Uri uri) async {
    if (!isInfaqLoginCallback(uri)) return;

    final uriKey = uri.toString();
    if (_handledUris.contains(uriKey)) return;
    _handledUris.add(uriKey);

    final isRecovery = isPasswordRecoveryUri(uri);
    debugPrint(
      '[EmailConfirm] deep link received recovery=$isRecovery',
    );

    if (isRecovery) {
      PasswordRecoveryState.markPending();
    }

    var handled = false;
    if (hasEmailConfirmTokenHash(uri)) {
      handled = await _verifyTokenHashUri(uri, recoveryOnly: isRecovery);
    } else {
      handled = await _exchangeSessionFromUrl(uri);
    }

    // Supabase Flutter may have already exchanged the PKCE code; honor pending recovery.
    await Future<void>.delayed(Duration.zero);
    final recoveryFlow =
        isRecovery || PasswordRecoveryState.pendingPasswordReset;

    if (!handled) {
      if (recoveryFlow && Supabase.instance.client.auth.currentSession != null) {
        handled = true;
      } else {
        onResult?.call(EmailConfirmDeepLinkResult.failed);
        return;
      }
    }

    if (recoveryFlow) {
      PasswordRecoveryState.markPending();
      await refreshAuthAfterCallback();
      debugPrint('[PasswordRecovery] session ready for password update');
      onResult?.call(EmailConfirmDeepLinkResult.passwordRecovery);
      onPasswordRecovery?.call();
      return;
    }

    await _notifyFromCurrentSession();
  }

  Future<bool> _exchangeSessionFromUrl(Uri uri) async {
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      return true;
    } on AuthException catch (e, st) {
      debugPrint('[EmailConfirm] getSessionFromUrl failed: ${e.message}\n$st');
      // Built-in Supabase deeplink handler may have redeemed the code first.
      if (Supabase.instance.client.auth.currentSession != null &&
          PasswordRecoveryState.pendingPasswordReset) {
        return true;
      }
    } catch (e, st) {
      debugPrint('[EmailConfirm] getSessionFromUrl error: $e\n$st');
    }
    return false;
  }

  Future<bool> _verifyTokenHashUri(
    Uri uri, {
    bool recoveryOnly = false,
  }) async {
    final tokenHash = uri.queryParameters['token_hash'];
    if (tokenHash == null || tokenHash.isEmpty) return false;

    final primaryType = mapOtpType(uri.queryParameters['type']);
    final typesToTry = recoveryOnly
        ? <OtpType>[OtpType.recovery]
        : <OtpType>[
            primaryType,
            if (primaryType == OtpType.email) OtpType.signup,
            if (primaryType == OtpType.signup) OtpType.email,
          ];

    for (final type in typesToTry.toSet()) {
      try {
        await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: type,
          redirectTo: kOAuthRedirectTo,
        );
        return true;
      } on AuthException catch (e, st) {
        debugPrint(
          '[EmailConfirm] verifyOtp failed type=${type.name}: ${e.message}\n$st',
        );
      } catch (e, st) {
        debugPrint('[EmailConfirm] verifyOtp error type=${type.name}: $e\n$st');
      }
    }
    return false;
  }

  Future<void> _notifyFromCurrentSession() async {
    if (PasswordRecoveryState.pendingPasswordReset) {
      debugPrint(
        '[EmailConfirm] skip email-confirm notify: password recovery pending',
      );
      return;
    }
    await refreshAuthAfterCallback();

    final session = Supabase.instance.client.auth.currentSession;
    final hasSession = session != null;
    debugPrint('[EmailConfirm] session exists=$hasSession');

    if (!hasSession) {
      onResult?.call(EmailConfirmDeepLinkResult.verifiedNoSession);
      return;
    }

    final confirmed = isEmailConfirmed(session.user);
    debugPrint('[EmailConfirm] email confirmed=$confirmed');

    onResult?.call(EmailConfirmDeepLinkResult.verifiedWithSession);
  }

  static bool isEmailConfirmed(User user) {
    return user.emailConfirmedAt != null && user.emailConfirmedAt!.isNotEmpty;
  }
}

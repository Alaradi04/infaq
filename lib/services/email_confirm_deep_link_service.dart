import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:infaq/oauth_redirect.dart';

enum EmailConfirmDeepLinkResult {
  notHandled,
  verifiedWithSession,
  verifiedNoSession,
  failed,
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
  final Set<String> _handledUris = <String>{};

  void Function(EmailConfirmDeepLinkResult result)? onResult;

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
    onResult = null;
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

    debugPrint('[EmailConfirm] deep link received');

    var handled = false;
    if (hasEmailConfirmTokenHash(uri)) {
      handled = await _verifyTokenHashUri(uri);
    } else {
      handled = await _exchangeSessionFromUrl(uri);
    }

    if (!handled) {
      onResult?.call(EmailConfirmDeepLinkResult.failed);
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
    } catch (e, st) {
      debugPrint('[EmailConfirm] getSessionFromUrl error: $e\n$st');
    }
    return false;
  }

  Future<bool> _verifyTokenHashUri(Uri uri) async {
    final tokenHash = uri.queryParameters['token_hash'];
    if (tokenHash == null || tokenHash.isEmpty) return false;

    final primaryType = mapOtpType(uri.queryParameters['type']);
    final typesToTry = <OtpType>[
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

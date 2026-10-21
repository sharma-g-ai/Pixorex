import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

import 'auth_tokens.dart';
import 'config.dart';

/// Why a sign-in did not produce tokens.
enum OidcFailure { cancelled, failed }

class OidcException implements Exception {
  OidcException(this.failure, [this.message]);
  final OidcFailure failure;
  final String? message;
  @override
  String toString() => 'OidcException($failure, $message)';
}

/// Keycloak sign-in through the system browser: Authorization Code + PKCE.
/// The code entry, resend and 30-minute lock screens are Keycloak's own pages
/// (CONSTITUTION 2.7: the app and API hold no code or lockout logic).
abstract class OidcClient {
  /// [loginHint] is the invited / typed email or E.164 phone number.
  Future<AuthTokens> signIn({String? loginHint});
  Future<AuthTokens> refresh(String refreshToken);
  Future<void> endSession({String? idToken});
}

class AppAuthOidcClient implements OidcClient {
  AppAuthOidcClient([FlutterAppAuth? appAuth]) : _appAuth = appAuth ?? const FlutterAppAuth();
  final FlutterAppAuth _appAuth;

  @override
  Future<AuthTokens> signIn({String? loginHint}) async {
    try {
      final r = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConfig.clientId,
          AppConfig.redirectUrl,
          issuer: AppConfig.keycloakIssuer,
          scopes: AppConfig.scopes,
          loginHint: loginHint,
          allowInsecureConnections: AppConfig.allowInsecureHttp,
        ),
      );
      return _toTokens(r.accessToken, r.accessTokenExpirationDateTime, r.refreshToken, r.idToken);
    } on PlatformException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    try {
      final r = await _appAuth.token(
        TokenRequest(
          AppConfig.clientId,
          AppConfig.redirectUrl,
          issuer: AppConfig.keycloakIssuer,
          refreshToken: refreshToken,
          scopes: AppConfig.scopes,
          allowInsecureConnections: AppConfig.allowInsecureHttp,
        ),
      );
      return _toTokens(
        r.accessToken,
        r.accessTokenExpirationDateTime,
        r.refreshToken ?? refreshToken,
        r.idToken,
      );
    } on PlatformException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> endSession({String? idToken}) async {
    try {
      await _appAuth.endSession(
        EndSessionRequest(
          idTokenHint: idToken,
          postLogoutRedirectUrl: AppConfig.postLogoutRedirectUrl,
          issuer: AppConfig.keycloakIssuer,
          allowInsecureConnections: AppConfig.allowInsecureHttp,
        ),
      );
    } on PlatformException {
      // The local session is cleared either way; a user closing the browser
      // sheet must not leave the app signed in.
    }
  }

  AuthTokens _toTokens(String? access, DateTime? expires, String? refresh, String? id) {
    if (access == null) throw OidcException(OidcFailure.failed, 'No access token returned');
    return AuthTokens(
      accessToken: access,
      expiresAt: expires ?? DateTime.now().add(const Duration(minutes: 5)),
      refreshToken: refresh,
      idToken: id,
    );
  }

  OidcException _map(PlatformException e) {
    final text = '${e.code} ${e.message}'.toLowerCase();
    final cancelled = text.contains('cancel') || text.contains('user_cancel');
    return OidcException(cancelled ? OidcFailure.cancelled : OidcFailure.failed, e.message);
  }
}

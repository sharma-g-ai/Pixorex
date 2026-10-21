import 'dart:convert';

import 'secure_store.dart';

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
  });

  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;
  final String? idToken;

  /// Refresh a little early so a call never leaves with a token about to lapse.
  bool isExpiring(DateTime now, {Duration skew = const Duration(seconds: 30)}) =>
      !expiresAt.subtract(skew).isAfter(now);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'refresh_token': refreshToken,
        'id_token': idToken,
      };

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken: j['access_token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        refreshToken: j['refresh_token'] as String?,
        idToken: j['id_token'] as String?,
      );
}

/// Tokens live only in the Keychain / Keystore (A0: architect sign-off needed).
class TokenStore {
  TokenStore(this._store);
  final SecureStore _store;
  static const _key = 'auth_tokens';

  Future<AuthTokens?> load() async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    try {
      return AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _store.delete(_key);
      return null;
    }
  }

  Future<void> save(AuthTokens t) => _store.write(_key, jsonEncode(t.toJson()));
  Future<void> clear() => _store.delete(_key);
}

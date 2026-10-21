import 'package:flutter/foundation.dart';

/// Build-time settings. Override with --dart-define, e.g.
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api/v1
///           --dart-define=KEYCLOAK_ISSUER=http://192.168.1.20:8080/realms/pixorex
/// (docs/mobile-api.md section 1: a phone cannot use localhost.)
class AppConfig {
  const AppConfig._();

  // 10.0.2.2 is the host machine as seen from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
  static const keycloakIssuer = String.fromEnvironment(
    'KEYCLOAK_ISSUER',
    defaultValue: 'http://10.0.2.2:8080/realms/pixorex',
  );

  // docs/mobile-api.md section 2.
  static const clientId = 'pixorex-mobile';
  static const redirectUrl = 'com.pixorex.mobile:/oauth2redirect';
  static const postLogoutRedirectUrl = 'com.pixorex.mobile:/logout';
  static const scopes = ['openid', 'profile', 'email', 'offline_access'];

  /// Plain http is allowed in debug builds only (local Compose stack).
  static const allowInsecureHttp = kDebugMode;
}

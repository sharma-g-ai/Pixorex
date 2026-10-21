import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/auth_tokens.dart';
import '../../core/oidc_client.dart';
import 'me.dart';

enum SessionStatus { restoring, signedOut, signingIn, signedIn }

/// Owns the signed-in state: tokens, silent refresh, `GET /me`, sign-out.
/// A0 code (CONSTITUTION 5): token handling needs architect sign-off.
class SessionController extends ChangeNotifier {
  SessionController({
    required OidcClient oidc,
    required TokenStore tokens,
    DateTime Function()? clock,
  })  : _oidc = oidc,
        _tokens = tokens,
        _now = clock ?? DateTime.now;

  final OidcClient _oidc;
  final TokenStore _tokens;
  final DateTime Function() _now;

  /// Set after construction because [ApiClient] needs [accessToken] first.
  late ApiClient api;

  SessionStatus _status = SessionStatus.restoring;
  Me? _me;
  String? _error;
  AuthTokens? _current;
  Future<AuthTokens?>? _refreshing;

  SessionStatus get status => _status;
  Me? get me => _me;

  /// Last user-facing problem, shown on the sign-in screen. Cleared by [clearError].
  String? get error => _error;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// On launch: reuse stored tokens, refresh if needed, then confirm with `/me`.
  Future<void> restore() async {
    _current = await _tokens.load();
    if (_current == null) {
      _set(SessionStatus.signedOut);
      return;
    }
    try {
      await _loadMe();
      _set(SessionStatus.signedIn);
    } on ApiException catch (e) {
      // Offline at launch keeps the session; the app can still show the cached state later.
      if (e.isNetwork) {
        _set(SessionStatus.signedOut);
        _error = e.message;
        notifyListeners();
      } else {
        await _drop();
      }
    }
  }

  /// Opens Keycloak in the system browser. [loginHint] is an email or E.164 phone.
  Future<bool> signIn({String? loginHint}) async {
    _error = null;
    _set(SessionStatus.signingIn);
    try {
      _current = await _oidc.signIn(loginHint: loginHint);
      await _tokens.save(_current!);
      await _loadMe();
      if (!_me!.isTechnician) {
        await signOut(message: 'This app is for field technicians. Administrators sign in on the web dashboard.');
        return false;
      }
      _set(SessionStatus.signedIn);
      return true;
    } on OidcException catch (e) {
      _error = e.failure == OidcFailure.cancelled ? null : "Sign-in didn't finish. Please try again.";
      await _drop(keepError: true);
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      await _drop(keepError: true);
      return false;
    }
  }

  Future<void> signOut({String? message}) async {
    final idToken = _current?.idToken;
    try {
      if (_current != null) await api.post('/me/sign-out');
    } on ApiException {
      // The device still signs out locally.
    }
    await _oidc.endSession(idToken: idToken);
    await _drop();
    if (message != null) {
      _error = message;
      notifyListeners();
    }
  }

  /// Token for API calls; refreshes it first when it is about to lapse.
  Future<String?> accessToken() async {
    final t = _current;
    if (t == null) return null;
    if (!t.isExpiring(_now())) return t.accessToken;
    return (await _refresh())?.accessToken;
  }

  Future<AuthTokens?> _refresh() {
    // One refresh at a time: parallel calls share the same result.
    return _refreshing ??= () async {
      final refreshToken = _current?.refreshToken;
      if (refreshToken == null) {
        await _drop();
        return null;
      }
      try {
        _current = await _oidc.refresh(refreshToken);
        await _tokens.save(_current!);
        return _current;
      } on OidcException {
        await _drop();
        return null;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _loadMe() async {
    final json = await api.get('/me');
    _me = Me.fromJson(json);
  }

  Future<void> _drop({bool keepError = false}) async {
    await _tokens.clear();
    _current = null;
    _me = null;
    if (!keepError) _error = null;
    _set(SessionStatus.signedOut);
  }

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }
}

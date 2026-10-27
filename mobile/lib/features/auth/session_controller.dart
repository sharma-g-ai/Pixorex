import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/auth_tokens.dart';
import '../../core/oidc_client.dart';
import 'me.dart';

enum SessionStatus { restoring, signedOut, signingIn, signedIn }

/// Owns the signed-in state: tokens, silent refresh, `GET /me`, the active unit, sign-out.
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

  static const notTechnicianMessage =
      'This app is for field technicians. Administrators sign in on the web dashboard.';
  static const noTechnicianUnitMessage =
      "You're no longer a field technician in any unit. Contact your administrator if this is a mistake.";
  static const sessionEndedMessage = 'Your session ended. Sign in again.';
  static const accessRemovedMessage =
      'Your access to Pixorex was removed. Contact your administrator if this is a mistake.';

  late ApiClient _api;

  /// Set after construction because [ApiClient] needs [accessToken] first.
  ApiClient get api => _api;
  set api(ApiClient client) {
    _api = client;
    client.onAccessLost = _onAccessLost;
  }

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

  /// A sign-in the OS interrupted is resumed only this soon after; Keycloak's session
  /// cookie (30 min idle) then finishes it without a new code.
  static const resumeWindow = Duration(minutes: 10);

  bool _resumedSignIn = false;

  /// True when this launch's [restore] resumed an interrupted sign-in.
  bool get resumedSignIn => _resumedSignIn;

  /// On launch: reuse stored tokens, refresh if needed, then confirm with `/me`.
  /// With no tokens, resumes a sign-in the OS cut off while the browser was open.
  Future<void> restore() async {
    _current = await _tokens.load();
    if (_current == null) {
      final pending = await _tokens.takeSignInPending();
      if (pending != null && _now().difference(pending.at) < resumeWindow) {
        _resumedSignIn = true;
        await signIn(loginHint: pending.loginHint);
        return;
      }
      _set(SessionStatus.signedOut);
      return;
    }
    try {
      await _loadMe();
      if (!_me!.isTechnician) {
        await signOut(message: noTechnicianUnitMessage);
        return;
      }
      _set(SessionStatus.signedIn);
    } on ApiException catch (e) {
      // Offline at launch keeps the session; the app can still show the cached state later.
      if (e.isNetwork) {
        _set(SessionStatus.signedOut);
        _error = e.message;
        notifyListeners();
      } else {
        await _drop(keepError: true);
      }
    }
  }

  /// Opens Keycloak in the system browser. [loginHint] is an email or E.164 phone.
  Future<bool> signIn({String? loginHint}) async {
    _error = null;
    _set(SessionStatus.signingIn);
    await _tokens.markSignInPending(loginHint, _now());
    try {
      _current = await _oidc.signIn(loginHint: loginHint);
      await _tokens.save(_current!);
      await _loadMe();
      if (!_me!.isTechnician) {
        await signOut(message: notTechnicianMessage);
        return false;
      }
      _set(SessionStatus.signedIn);
      return true;
    } on OidcException catch (e) {
      _error = e.failure == OidcFailure.cancelled ? null : "Sign-in didn't finish. Please try again.";
      await _drop(keepError: true);
      return false;
    } on ApiException catch (e) {
      _error ??= e.message;
      await _drop(keepError: true);
      return false;
    } finally {
      // Still here, so the result arrived (or failed): nothing to resume.
      await _tokens.clearSignInPending();
    }
  }

  /// Unit switch (contract 1.2): no new sign-in. Throws [ApiException]; on a 403 (removed
  /// from that unit meanwhile) `/me` is reloaded first so the list is current.
  Future<void> switchUnit(String buId) async {
    try {
      _me = Me.fromJson(await api.put('/me/active-unit', body: {'bu_id': buId}));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isForbidden) await refresh();
      rethrow;
    }
  }

  /// Reloads `/me` (the app calls this when it comes back to the foreground), so a unit
  /// removal or a lost technician role shows up without a relaunch.
  Future<void> refresh() async {
    if (_status != SessionStatus.signedIn) return;
    try {
      await _loadMe();
      if (!_me!.isTechnician) {
        await signOut(message: noTechnicianUnitMessage);
        return;
      }
      notifyListeners();
    } on ApiException {
      // Offline keeps the session; a lost session was handled by [_onAccessLost].
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

  /// A newly issued token, for the API client's one retry after a 401.
  Future<String?> freshAccessToken() async => (await _refresh())?.accessToken;

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

  /// `/me`, then makes sure the active unit is one where this person is a technician.
  Future<void> _loadMe() async {
    _me = Me.fromJson(await api.get('/me'));
    final me = _me!;
    final target = me.activeUnit == null ? me.preferredTechnicianUnit : null;
    if (target != null) {
      _me = Me.fromJson(await api.put('/me/active-unit', body: {'bu_id': target.buId}));
    }
  }

  /// The API says this person can no longer work here: local sign-out with the reason.
  /// No API or Keycloak call: the session is already gone on the server.
  void _onAccessLost(ApiException e) {
    _error = e.isAccountRemoved ? accessRemovedMessage : sessionEndedMessage;
    _drop(keepError: true);
  }

  /// Signed out at once (no moment where the screens think a token is still there),
  /// then the stored tokens are cleared.
  Future<void> _drop({bool keepError = false}) async {
    _current = null;
    _me = null;
    if (!keepError) _error = null;
    _set(SessionStatus.signedOut);
    await _tokens.clear();
  }

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }
}

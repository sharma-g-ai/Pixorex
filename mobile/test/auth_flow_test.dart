import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixorex_mobile/app.dart';
import 'package:pixorex_mobile/core/api_client.dart';
import 'package:pixorex_mobile/core/auth_tokens.dart';
import 'package:pixorex_mobile/core/device_id.dart';
import 'package:pixorex_mobile/core/oidc_client.dart';
import 'package:pixorex_mobile/core/secure_store.dart';
import 'package:provider/provider.dart';
import 'package:pixorex_mobile/features/auth/activate_screen.dart';
import 'package:pixorex_mobile/features/auth/activation_controller.dart';
import 'package:pixorex_mobile/features/auth/invite_repository.dart';
import 'package:pixorex_mobile/features/auth/session_controller.dart';

class FakeOidc implements OidcClient {
  String? lastHint;
  OidcException? failWith;
  int signIns = 0;
  int refreshes = 0;
  bool ended = false;

  @override
  Future<AuthTokens> signIn({String? loginHint}) async {
    signIns++;
    lastHint = loginHint;
    if (failWith != null) throw failWith!;
    return AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1', idToken: 'id-1', expiresAt: DateTime.now().add(const Duration(hours: 1)));
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    refreshes++;
    return AuthTokens(accessToken: 'access-2', refreshToken: refreshToken, expiresAt: DateTime.now().add(const Duration(hours: 1)));
  }

  @override
  Future<void> endSession({String? idToken}) async => ended = true;
}

class NoLinks implements LinkSource {
  @override
  Future<Uri?> initialLink() async => null;
  @override
  Stream<Uri> get links => const Stream.empty();
}

Map<String, dynamic> meJson({String role = 'field_technician'}) => {
      'user_id': 'u1',
      'full_name': 'Jorge Martinez',
      'email': 'j.martinez@ppg-plant04.com',
      'status': 'active',
      'tenant_name': 'PPG',
      'active_bu_id': 'b1',
      'last_bu_id': null,
      'units': [
        {'bu_id': 'b1', 'name': 'PPG Plant 04 — Coatings', 'role': role, 'is_primary': true},
      ],
    };

class Rig {
  Rig(this.handler) {
    final tokenStore = TokenStore(mem);
    session = SessionController(oidc: oidc, tokens: tokenStore);
    api = ApiClient(
      http: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        return handler(r);
      }),
      deviceId: DeviceIdStore(mem),
      accessToken: session.accessToken,
      baseUrl: 'http://api.test/api/v1',
    );
    session.api = api;
    invites = InviteRepository(api);
  }

  final Future<http.Response> Function(http.BaseRequest) handler;
  final mem = MemorySecureStore();
  final oidc = FakeOidc();
  final calls = <String>[];
  late final SessionController session;
  late final ApiClient api;
  late final InviteRepository invites;
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response problem(int status, String code) =>
    json({'type': '/problems/$code', 'title': code, 'status': status, 'detail': 'detail for $code'}, status);

Future<void> pumpApp(WidgetTester t, Rig rig) async {
  await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
    value: rig.session,
    child: PixorexApp(invites: rig.invites, linkSource: NoLinks()),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('SessionController', () {
    test('restore with no tokens lands signed out', () async {
      final rig = Rig((_) async => json({}));
      await rig.session.restore();
      expect(rig.session.status, SessionStatus.signedOut);
    });

    test('sign-in stores tokens and loads /me', () async {
      final rig = Rig((r) async => json(meJson()));
      final ok = await rig.session.signIn(loginHint: '+12165550148');
      expect(ok, isTrue);
      expect(rig.oidc.lastHint, '+12165550148');
      expect(rig.session.status, SessionStatus.signedIn);
      expect(rig.session.me?.fullName, 'Jorge Martinez');
      expect(await TokenStore(rig.mem).load(), isNotNull);
    });

    test('an administrator is refused and signed out', () async {
      final rig = Rig((r) async => json(r.url.path.endsWith('/me/sign-out') ? {} : meJson(role: 'bu_admin')));
      final ok = await rig.session.signIn(loginHint: 'a@b.co');
      expect(ok, isFalse);
      expect(rig.session.status, SessionStatus.signedOut);
      expect(rig.session.error, contains('field technicians'));
      expect(await TokenStore(rig.mem).load(), isNull);
    });

    test('cancelling the browser is silent', () async {
      final rig = Rig((_) async => json({}));
      rig.oidc.failWith = OidcException(OidcFailure.cancelled);
      expect(await rig.session.signIn(loginHint: 'a@b.co'), isFalse);
      expect(rig.session.error, isNull);
      expect(rig.session.status, SessionStatus.signedOut);
    });

    test('a failed sign-in shows a message', () async {
      final rig = Rig((_) async => json({}));
      rig.oidc.failWith = OidcException(OidcFailure.failed);
      await rig.session.signIn(loginHint: 'a@b.co');
      expect(rig.session.error, isNotNull);
    });

    test('an expiring token is refreshed once for parallel calls', () async {
      final rig = Rig((_) async => json(meJson()));
      await rig.mem.write(
        'auth_tokens',
        jsonEncode(AuthTokens(accessToken: 'old', refreshToken: 'r', expiresAt: DateTime.now().subtract(const Duration(minutes: 1))).toJson()),
      );
      await rig.session.restore();
      expect(rig.oidc.refreshes, 1);
      final tokens = await Future.wait([rig.session.accessToken(), rig.session.accessToken()]);
      expect(tokens, ['access-2', 'access-2']);
      expect(rig.oidc.refreshes, 1);
    });

    test('sign-out calls the API, ends the Keycloak session and clears tokens', () async {
      final rig = Rig((r) async => json(r.url.path.endsWith('/me') ? meJson() : {}));
      await rig.session.signIn(loginHint: 'a@b.co');
      await rig.session.signOut();
      expect(rig.calls, contains('POST /api/v1/me/sign-out'));
      expect(rig.oidc.ended, isTrue);
      expect(rig.session.status, SessionStatus.signedOut);
      expect(await TokenStore(rig.mem).load(), isNull);
    });
  });

  group('ActivationController', () {
    final preview = {
      'role': 'field_technician',
      'email': 'j.martinez@ppg-plant04.com',
      'invited_by_name': 'R. Kowalski',
      'expires_at': '2026-10-21T09:00:00Z',
      'units': [
        {'bu_id': 'b1', 'name': 'PPG Plant 04 — Coatings'}
      ],
    };

    test('a valid technician invite is ready', () async {
      final rig = Rig((_) async => json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      expect(c.status, ActivationStatus.ready);
      expect(c.preview?.units.single.name, 'PPG Plant 04 — Coatings');
    });

    test('an administrator invite is refused', () async {
      final rig = Rig((_) async => json({...preview, 'role': 'bu_admin'}));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      expect(c.status, ActivationStatus.wrongRole);
    });

    for (final code in ['invite-expired', 'invite-used', 'invite-cancelled']) {
      test('409 $code shows the expired screen', () async {
        final rig = Rig((_) async => problem(409, code));
        final c = ActivationController(repository: rig.invites, token: 't');
        await c.load();
        expect(c.status, ActivationStatus.linkInvalid);
        expect(c.linkProblem, code);
      });
    }

    test('offline load offers retry', () async {
      final rig = Rig((_) async => throw http.ClientException('down'));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      expect(c.status, ActivationStatus.loadFailed);
    });

    test('empty name or incomplete phone blocks submit without calling the API', () async {
      final rig = Rig((_) async => json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      final errors = await c.submit(fullName: ' ', phoneE164: null);
      expect(errors?.name, isNotNull);
      expect(errors?.phone, isNotNull);
      expect(rig.calls.where((c) => c.contains('accept')), isEmpty);
    });

    test('accept for a technician signs in with the phone number', () async {
      final rig = Rig((r) async => r.url.path.endsWith('/accept')
          ? json({'user_id': 'u1', 'next_step': 'verify_phone'}, 201)
          : json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      final errors = await c.submit(fullName: 'Jorge Martinez', phoneE164: '+12165550148');
      expect(errors, isNull);
      expect(c.status, ActivationStatus.accepted);
      expect(c.signInHint, '+12165550148');
    });

    test('accept falling to verify_email signs in with the email', () async {
      final rig = Rig((r) async => r.url.path.endsWith('/accept')
          ? json({'user_id': 'u1', 'next_step': 'verify_email'}, 201)
          : json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      await c.submit(fullName: 'Jorge', phoneE164: '+12165550148');
      expect(c.signInHint, 'j.martinez@ppg-plant04.com');
    });

    test('a 409 on accept (used meanwhile) shows the expired screen', () async {
      final rig = Rig((r) async => r.url.path.endsWith('/accept') ? problem(409, 'invite-used') : json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      await c.submit(fullName: 'Jorge', phoneE164: '+12165550148');
      expect(c.status, ActivationStatus.linkInvalid);
      expect(c.linkProblem, 'invite-used');
    });

    test('a 400 on accept returns to the form with the server message', () async {
      final rig = Rig((r) async => r.url.path.endsWith('/accept')
          ? json({
              'type': '/problems/validation',
              'title': 'Invalid',
              'status': 400,
              'errors': [
                {'field': 'phone_number', 'message': 'Not a valid number'}
              ],
            }, 400)
          : json(preview));
      final c = ActivationController(repository: rig.invites, token: 't');
      await c.load();
      final errors = await c.submit(fullName: 'Jorge', phoneE164: '+12165550148');
      expect(c.status, ActivationStatus.ready);
      expect(errors?.phone, 'Not a valid number');
    });
  });

  group('screens', () {
    testWidgets('signed out shows Sign in; bad phone shows an error and never opens the browser', (t) async {
      final rig = Rig((_) async => json({}));
      await pumpApp(t, rig);
      expect(find.text('Sign in'), findsOneWidget);
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(find.text('Enter your full mobile number'), findsOneWidget);
      expect(rig.oidc.signIns, 0);
    });

    testWidgets('a valid phone starts sign-in with an E.164 hint and lands signed in', (t) async {
      final rig = Rig((_) async => json(meJson()));
      await pumpApp(t, rig);
      await t.enterText(find.byType(TextField), '2165550148');
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(rig.oidc.lastHint, '+12165550148');
      expect(find.text('You are signed in.'), findsOneWidget);
    });

    testWidgets('Email tab validates and signs in with the email', (t) async {
      final rig = Rig((_) async => json(meJson()));
      await pumpApp(t, rig);
      await t.tap(find.text('Email'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'nope');
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'j.martinez@ppg-plant04.com');
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(rig.oidc.lastHint, 'j.martinez@ppg-plant04.com');
    });

    testWidgets('an expired invite shows the expired screen', (t) async {
      final rig = Rig((_) async => problem(409, 'invite-expired'));
      final ctrl = ActivationController(repository: rig.invites, token: 'x');
      await t.pumpWidget(ChangeNotifierProvider<SessionController>.value(
        value: rig.session,
        child: MaterialApp(home: ActivateScreen(controller: ctrl)),
      ));
      await t.pumpAndSettle();
      expect(find.text('This invite link has expired'), findsOneWidget);
    });
  });
}

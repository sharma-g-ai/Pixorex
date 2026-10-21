import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixorex_mobile/core/api_client.dart';
import 'package:pixorex_mobile/core/api_exception.dart';
import 'package:pixorex_mobile/core/auth_tokens.dart';
import 'package:pixorex_mobile/core/device_id.dart';
import 'package:pixorex_mobile/core/invite_link.dart';
import 'package:pixorex_mobile/core/phone.dart';
import 'package:pixorex_mobile/core/secure_store.dart';

ApiClient clientFor(MockClient m, {String? token = 'tok', MemorySecureStore? store}) => ApiClient(
      http: m,
      deviceId: DeviceIdStore(store ?? MemorySecureStore()),
      accessToken: () async => token,
      baseUrl: 'http://api.test/api/v1',
    );

void main() {
  group('parseInviteToken', () {
    test('reads the fragment form used by the web link', () {
      expect(parseInviteToken(Uri.parse('pixorex://activate#token=abc123')), 'abc123');
    });
    test('reads the query form', () {
      expect(parseInviteToken(Uri.parse('pixorex://activate?token=abc123')), 'abc123');
    });
    test('ignores other links and empty tokens', () {
      expect(parseInviteToken(Uri.parse('pixorex://home')), isNull);
      expect(parseInviteToken(Uri.parse('pixorex://activate')), isNull);
      expect(parseInviteToken(Uri.parse('pixorex://activate#token=')), isNull);
    });
  });

  group('phone', () {
    const us = Country('+1', 10);
    test('toE164 needs a complete national number', () {
      expect(toE164(us, '(216) 555-0148'), '+12165550148');
      expect(toE164(us, '216555'), isNull);
      expect(toE164(us, ''), isNull);
    });
    test('maskPhone hides all but the last 4 digits', () {
      expect(maskPhone('+12165550148'), '+1 ••• ••• 0148');
    });
    test('formatter shapes digits as the user types', () {
      final f = NationalPhoneFormatter();
      final out = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '21655501489999'),
      );
      expect(out.text, '(216) 555-0148');
    });
    test('isValidEmail', () {
      expect(isValidEmail('j.martinez@ppg-plant04.com'), isTrue);
      expect(isValidEmail('not-an-email'), isFalse);
    });
  });

  group('ApiClient', () {
    test('authenticated calls carry bearer, device id and idempotency key', () async {
      late http.BaseRequest seen;
      final c = clientFor(MockClient((r) async {
        seen = r;
        return http.Response('{}', 200);
      }));
      await c.post('/x', body: {'a': 1}, idempotencyKey: 'k1');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['X-Device-Id'], isNotEmpty);
      expect(seen.headers['Idempotency-Key'], 'k1');
    });

    test('public calls (invites) send neither bearer nor device id', () async {
      late http.BaseRequest seen;
      final c = clientFor(MockClient((r) async {
        seen = r;
        return http.Response('{}', 200);
      }));
      await c.post('/invites/preview', body: {'token': 't'}, authenticated: false);
      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(seen.headers.containsKey('X-Device-Id'), isFalse);
    });

    test('device id is made once and reused', () async {
      final store = MemorySecureStore();
      final a = await DeviceIdStore(store).get();
      final b = await DeviceIdStore(store).get();
      expect(a, b);
    });

    test('maps problem+json to ApiException', () async {
      final c = clientFor(MockClient((r) async => http.Response(
            jsonEncode({
              'type': '/problems/invite-expired',
              'title': 'Invite expired',
              'status': 409,
              'detail': 'This invite has expired.',
            }),
            409,
            headers: {'content-type': 'application/problem+json'},
          )));
      await expectLater(
        c.post('/invites/preview', body: {'token': 't'}, authenticated: false),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'invite-expired')
            .having((e) => e.status, 'status', 409)
            .having((e) => e.message, 'message', 'This invite has expired.')),
      );
    });

    test('a dropped connection becomes a network error', () async {
      final c = clientFor(MockClient((r) async => throw http.ClientException('down')));
      await expectLater(c.get('/me'), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
    });

    test('no token means 401 without calling the server', () async {
      var called = false;
      final c = clientFor(MockClient((r) async {
        called = true;
        return http.Response('{}', 200);
      }), token: null);
      await expectLater(c.get('/me'), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)));
      expect(called, isFalse);
    });
  });

  group('TokenStore', () {
    test('round-trips and clears', () async {
      final store = TokenStore(MemorySecureStore());
      final t = AuthTokens(accessToken: 'a', refreshToken: 'r', idToken: 'i', expiresAt: DateTime.utc(2030));
      await store.save(t);
      final back = await store.load();
      expect(back?.accessToken, 'a');
      expect(back?.refreshToken, 'r');
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('corrupt data is discarded, not thrown', () async {
      final mem = MemorySecureStore()..values['auth_tokens'] = 'not json';
      expect(await TokenStore(mem).load(), isNull);
      expect(mem.values.containsKey('auth_tokens'), isFalse);
    });

    test('isExpiring uses a safety margin', () {
      final now = DateTime.utc(2030, 1, 1, 12);
      expect(AuthTokens(accessToken: 'a', expiresAt: now.add(const Duration(seconds: 10))).isExpiring(now), isTrue);
      expect(AuthTokens(accessToken: 'a', expiresAt: now.add(const Duration(minutes: 5))).isExpiring(now), isFalse);
    });
  });
}

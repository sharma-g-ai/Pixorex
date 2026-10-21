import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'config.dart';
import 'device_id.dart';

typedef AccessTokenProvider = Future<String?> Function();

/// Thin JSON client. Adds the headers every call needs
/// (docs/mobile-api.md section 3) and turns problem+json into [ApiException].
class ApiClient {
  ApiClient({
    required http.Client http,
    required DeviceIdStore deviceId,
    required this.accessToken,
    String baseUrl = AppConfig.apiBaseUrl,
    this.timeout = const Duration(seconds: 20),
  })  : _http = http,
        _deviceId = deviceId,
        _baseUrl = baseUrl;

  final http.Client _http;
  final DeviceIdStore _deviceId;
  final String _baseUrl;
  final Duration timeout;
  final AccessTokenProvider accessToken;

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  /// [authenticated] is false only for invite preview and accept: they carry
  /// neither the bearer token nor X-Device-Id.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? idempotencyKey,
  }) =>
      _send('POST', path, body: body, authenticated: authenticated, idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated) {
      final token = await accessToken();
      if (token == null) {
        throw ApiException(status: 401, code: 'unauthorized', title: 'Please sign in again');
      }
      headers['Authorization'] = 'Bearer $token';
      headers['X-Device-Id'] = await _deviceId.get();
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    final request = http.Request(method, Uri.parse('$_baseUrl$path'))..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout));
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    } on TimeoutException {
      throw ApiException.network();
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    }
    if (decoded is Map<String, dynamic>) {
      throw ApiException.fromProblem(response.statusCode, decoded);
    }
    throw ApiException(
      status: response.statusCode,
      code: 'unknown',
      title: 'Something went wrong',
    );
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

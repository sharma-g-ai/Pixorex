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

  /// Null and empty [query] values are left out.
  Future<Map<String, dynamic>> get(String path, {Map<String, String?>? query}) =>
      _send('GET', path, query: query);

  /// [authenticated] is false only for invite preview and accept: they carry
  /// neither the bearer token nor X-Device-Id.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? idempotencyKey,
  }) =>
      _send('POST', path, body: body, authenticated: authenticated, idempotencyKey: idempotencyKey);

  /// Raw upload, e.g. a photo (contract 2.22): [headers] carry its Content-Type and Content-Digest.
  Future<Map<String, dynamic>> putBytes(
    String path,
    List<int> bytes, {
    required Map<String, String> headers,
  }) =>
      _send('PUT', path, bytes: bytes, extraHeaders: headers);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    Map<String, String>? extraHeaders,
    Map<String, String?>? query,
    bool authenticated = true,
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (extraHeaders != null) headers.addAll(extraHeaders);
    if (authenticated) {
      final token = await accessToken();
      if (token == null) {
        throw ApiException(status: 401, code: 'unauthorized', title: 'Please sign in again');
      }
      headers['Authorization'] = 'Bearer $token';
      headers['X-Device-Id'] = await _deviceId.get();
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    var uri = Uri.parse('$_baseUrl$path');
    final params = {
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    if (bytes != null) request.bodyBytes = bytes;

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

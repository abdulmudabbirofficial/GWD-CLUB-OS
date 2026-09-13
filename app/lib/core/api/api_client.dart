import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown for any non-2xx response. Carries the server's own message, which is
/// always written to be shown to a person as-is.
class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  bool get isAuthFailure => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isPendingApproval => statusCode == 403 && message.contains('awaiting approval');

  @override
  String toString() => message;
}

/// Where the backend lives, when the user has not set an address themselves.
///
/// Resolution order:
///   1. --dart-define=GWD_API_BASE=...        (release builds, CI, production)
///   2. the web origin the app was served from (so web "just works")
///   3. 10.0.2.2 on an Android emulator, which is the host's loopback
///   4. localhost for desktop and iOS simulator
///
/// A baked-in LAN address is fragile: the moment the router hands the laptop a
/// different IP, every installed APK stops reaching it and looks broken. So
/// this is only the *default* — [Session] lets the user override it and stores
/// the choice.
class ApiConfig {
  static const _define = String.fromEnvironment('GWD_API_BASE');

  static String resolve() {
    if (_define.isNotEmpty) return _define;
    if (kIsWeb) return ''; // same origin
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:4000';
    } catch (_) {
      // Platform is unavailable on some targets; fall through.
    }
    return 'http://localhost:4000';
  }

  /// Accepts what people actually type — "10.0.0.5", "10.0.0.5:4000",
  /// "http://10.0.0.5:4000" — and returns a usable origin, or null if it is
  /// not salvageable.
  static String? normalise(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    // Default to the port the server actually listens on.
    final port = uri.hasPort ? uri.port : 4000;
    return '${uri.scheme}://${uri.host}:$port';
  }
}

typedef TokenProvider = String? Function();
typedef UnauthorizedHandler = void Function();

class ApiClient {
  ApiClient({String Function()? baseUrlProvider, this.tokenProvider, this.onUnauthorized})
      : _baseUrlProvider = baseUrlProvider ?? ApiConfig.resolve;

  /// Read on every request rather than captured once, so changing the server
  /// address in Settings takes effect immediately — no restart, no rebuild.
  final String Function() _baseUrlProvider;
  String get baseUrl => _baseUrlProvider();

  final TokenProvider? tokenProvider;

  /// Called when the server rejects our token, so the app can drop to sign-in
  /// rather than silently showing empty screens.
  final UnauthorizedHandler? onUnauthorized;

  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?..removeWhere((_, v) => v == null);
    final qs = (cleaned == null || cleaned.isEmpty)
        ? ''
        : '?${cleaned.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}').join('&')}';
    return Uri.parse('$baseUrl$path$qs');
  }

  Map<String, String> get _headers {
    final token = tokenProvider?.call();
    return {
      'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
  }) async {
    late http.Response response;
    try {
      final uri = _uri(path, query);
      final encoded = body == null ? null : jsonEncode(body);
      response = await switch (method) {
        'GET' => _client.get(uri, headers: _headers),
        'POST' => _client.post(uri, headers: _headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: _headers, body: encoded),
        'PUT' => _client.put(uri, headers: _headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: _headers, body: encoded),
        _ => throw ArgumentError('Unsupported method $method'),
      }
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('The server took too long to respond.', 408);
    } catch (error) {
      // Name the address we actually tried. The most common cause by far is
      // that the backend isn't running, or the phone is on a different network
      // from the laptop — and a generic "check your connection" sends people
      // hunting for a phone problem that isn't there.
      final target = baseUrl.isEmpty ? 'the server' : baseUrl;
      throw ApiException(
        "Can't reach $target.\n\n"
        'Check that the backend is running on your computer and that this '
        'device is on the same Wi-Fi network.',
        0,
      );
    }

    Map<String, dynamic> json = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Non-JSON body (e.g. the SPA fallback) — leave json empty.
      }
    }

    if (response.statusCode == 401) onUnauthorized?.call();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        json['error']?.toString() ?? 'Something went wrong (${response.statusCode}).',
        response.statusCode,
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) =>
      _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? body]) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) =>
      _send('DELETE', path, body: body);

  /// Multipart upload, for event documents.
  ///
  /// Separate from [_send] because a file is not JSON: the body is a stream,
  /// the content-type carries a generated boundary, and a 15 MB permission
  /// letter on college Wi-Fi needs a far longer timeout than an API call.
  /// [bytes] is optional — a document can be a link to somewhere else instead.
  Future<Map<String, dynamic>> upload(
    String path, {
    Map<String, String> fields = const {},
    List<int>? bytes,
    String? filename,
    /// Which multipart part the file goes in. The routes differ deliberately —
    /// a document is `file`, a receipt is `receipt` — and the server rejects
    /// anything it was not told to expect.
    String fieldName = 'file',
    Duration timeout = const Duration(minutes: 3),
  }) async {
    late http.StreamedResponse streamed;
    try {
      final request = http.MultipartRequest('POST', _uri(path));
      final token = tokenProvider?.call();
      if (token != null && token.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);
      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename ?? 'upload',
        ));
      }
      streamed = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        'The upload timed out. A weak connection can stall a large file — '
        'try again, or paste a link to it instead.',
        408,
      );
    } catch (_) {
      final target = baseUrl.isEmpty ? 'the server' : baseUrl;
      throw ApiException("Can't reach $target to upload that file.", 0);
    }

    final body = await streamed.stream.bytesToString();
    Map<String, dynamic> json = const {};
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Non-JSON body — leave json empty and fall through to the status check.
      }
    }

    if (streamed.statusCode == 401) onUnauthorized?.call();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(
        json['error']?.toString() ?? 'That file could not be uploaded.',
        streamed.statusCode,
      );
    }
    return json;
  }

  /// Fetch raw bytes from an authenticated route.
  ///
  /// Documents are served behind the same token as everything else, which is
  /// the point — an unguessable filename is not access control. That also means
  /// the URL cannot just be handed to the system browser, so the app fetches
  /// the bytes itself.
  Future<({List<int> bytes, String contentType})> download(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    late http.Response response;
    try {
      response = await _client
          .get(_uri(path, query), headers: _headers)
          .timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw ApiException('That file took too long to download.', 408);
    } catch (_) {
      final target = baseUrl.isEmpty ? 'the server' : baseUrl;
      throw ApiException("Can't reach $target to fetch that file.", 0);
    }

    if (response.statusCode == 401) onUnauthorized?.call();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'That file could not be opened.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {
        // Not JSON — keep the generic message.
      }
      throw ApiException(message, response.statusCode);
    }

    return (
      bytes: response.bodyBytes,
      contentType: response.headers['content-type'] ?? 'application/octet-stream',
    );
  }

  void dispose() => _client.close();
}

/// Pulls a typed list out of a response envelope like `{ "tasks": [...] }`.
List<T> listFrom<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) {
  final raw = json[key];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => parse(e.cast<String, dynamic>()))
      .toList(growable: false);
}

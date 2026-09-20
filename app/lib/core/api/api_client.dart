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

/// Which deployment this build talks to.
///
/// Passed at build time. Everything about where the app points follows from
/// it, so a release cannot accidentally be a debug build aimed at somebody's
/// laptop — the one failure that looks completely normal until a phone leaves
/// the building.
enum AppEnvironment {
  /// The club's own laptop on college Wi-Fi, over plain HTTP. The default,
  /// because it is what somebody running `flutter run` means.
  dev,

  /// A hosted copy for testing. No address is committed for it; a build that
  /// asks for staging must supply one.
  staging,

  /// The real deployment.
  production;

  static AppEnvironment get current => switch (
        const String.fromEnvironment('GWD_ENV', defaultValue: 'dev')) {
        'production' || 'prod' => AppEnvironment.production,
        'staging' || 'stage' => AppEnvironment.staging,
        _ => AppEnvironment.dev,
      };

  bool get isProduction => this == AppEnvironment.production;

  /// Whether a plaintext address is acceptable here.
  ///
  /// It is on a LAN: the club's server is a laptop with no certificate, and
  /// refusing HTTP would mean refusing to work at all. It is not on anything
  /// hosted, where HTTP means a token travelling in the clear.
  bool get allowsInsecure => this == AppEnvironment.dev;
}

/// Where the backend lives, when the user has not set an address themselves.
///
/// Resolution order:
///   1. --dart-define=GWD_API_BASE=...   an explicit address, whatever the
///      environment — this is what `scripts/build-apk.ps1` bakes in
///   2. the environment's own address
///   3. for dev only: the web origin, the Android emulator's host alias, or
///      localhost, in that order
///
/// A baked-in LAN address is fragile: the moment the router hands the laptop a
/// different IP, every installed APK stops reaching it and looks broken. So
/// this is only the *default* — [Session] lets the user override it and stores
/// the choice.
class ApiConfig {
  static const _define = String.fromEnvironment('GWD_API_BASE');
  static const _staging = String.fromEnvironment('GWD_STAGING_BASE');

  /// The deployment this build was compiled for.
  static AppEnvironment get environment => AppEnvironment.current;

  /// The production service. The only address committed to the repository,
  /// because it is the only one that does not move.
  static const productionBase = 'https://gwd-club-os-abrw.onrender.com';

  static String resolve() {
    if (_define.isNotEmpty) return _define;

    switch (environment) {
      case AppEnvironment.production:
        return productionBase;
      case AppEnvironment.staging:
        // Deliberately not invented. A staging build with no address is a
        // mistake in the build command, and saying so beats silently talking
        // to a laptop that is not there.
        assert(
          _staging.isNotEmpty,
          'GWD_ENV=staging needs --dart-define=GWD_STAGING_BASE=https://...',
        );
        return _staging;
      case AppEnvironment.dev:
        if (kIsWeb) return ''; // same origin
        try {
          if (Platform.isAndroid) return 'http://10.0.2.2:4000';
        } catch (_) {
          // Platform is unavailable on some targets; fall through.
        }
        return 'http://localhost:4000';
    }
  }

  /// Whether [base] is safe to send a bearer token to in this environment.
  ///
  /// Only `dev` may speak plaintext, and only there because the club's server
  /// is a laptop without a certificate. Anywhere hosted, `http://` means every
  /// token and every document travels readable across whatever network the
  /// phone is on.
  static bool isAcceptable(String base) {
    if (base.isEmpty) return true; // same-origin web build
    if (environment.allowsInsecure) return true;
    return base.startsWith('https://');
  }

  /// Accepts what people actually type — "10.0.0.5", "10.0.0.5:4000",
  /// "http://10.0.0.5:4000" — and returns a usable origin, or null if it is
  /// not salvageable.
  ///
  /// Assumes `https` outside dev. Somebody typing a bare hostname into a
  /// production build means the hosted service, and quietly turning that into
  /// `http://` would be the app downgrading its own security on their behalf.
  static String? normalise(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    final secure = !environment.allowsInsecure;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = '${secure ? 'https' : 'http'}://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return null;
    if (!isAcceptable('${uri.scheme}://${uri.host}')) return null;
    // Default to the port the server actually listens on. A hosted address
    // serves on the scheme's own port and should not be given 4000.
    if (uri.hasPort) return '${uri.scheme}://${uri.host}:${uri.port}';
    return uri.scheme == 'https'
        ? '${uri.scheme}://${uri.host}'
        : '${uri.scheme}://${uri.host}:4000';
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

  Map<String, String> _headersFor(String? token) => {
        'content-type': 'application/json',
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      };

  /// Whether a 401 for a request sent under [sent] should end the session.
  ///
  /// Only if we are still holding that token. Changing your password revokes
  /// every token issued before it, and requests already in flight under the old
  /// one come back 401 a moment later - through no fault of the session that
  /// replaced it.
  ///
  /// Not hypothetical. Signing in fires fifteen calls to fill the store, a
  /// seeded account is pushed straight into the forced password sheet, and on a
  /// hosted database several of those calls are still open when the change
  /// lands. Every one came back 401 and the first to arrive signed the user
  /// out - so a first-time member, doing exactly what they were told, was
  /// thrown back to the sign-in screen by the act of succeeding.
  bool _shouldEndSession(String? sent) => sent == tokenProvider?.call();

  /// How long an ordinary call may take before the app gives up.
  ///
  /// Generous, because the backend is a laptop on college Wi-Fi and the phone
  /// is often two rooms away, not because any request should take this long.
  static const defaultTimeout = Duration(seconds: 20);

  /// Password work, which is slow *by design*.
  ///
  /// A cost-12 bcrypt comparison plus a fresh hash is a second of deliberate
  /// CPU before the database is even touched, and the write that follows goes
  /// to a hosted cluster. Twenty seconds is fine for reading a task list and is
  /// not a safe budget for this — and the failure is nastier than a spinner,
  /// because the server finishes the change after the client has stopped
  /// waiting. See [ClubStore.changePassword].
  static const passwordTimeout = Duration(seconds: 75);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? query,
    Duration? timeout,
  }) async {
    late http.Response response;
    final sent = tokenProvider?.call();
    final headers = _headersFor(sent);
    try {
      final uri = _uri(path, query);
      final encoded = body == null ? null : jsonEncode(body);
      response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encoded),
        'PATCH' => _client.patch(uri, headers: headers, body: encoded),
        'PUT' => _client.put(uri, headers: headers, body: encoded),
        'DELETE' => _client.delete(uri, headers: headers, body: encoded),
        _ => throw ArgumentError('Unsupported method $method'),
      }
          .timeout(timeout ?? defaultTimeout);
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

    if (response.statusCode == 401 && _shouldEndSession(sent)) onUnauthorized?.call();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        json['error']?.toString() ?? 'Something went wrong (${response.statusCode}).',
        response.statusCode,
      );
    }
    return json;
  }

  Future<Map<String, dynamic>> get(String path,
          {Map<String, dynamic>? query, Duration? timeout}) =>
      _send('GET', path, query: query, timeout: timeout);

  Future<Map<String, dynamic>> post(String path,
          [Map<String, dynamic>? body, Duration? timeout]) =>
      _send('POST', path, body: body, timeout: timeout);

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
    final sent = tokenProvider?.call();
    try {
      final request = http.MultipartRequest('POST', _uri(path));
      if (sent != null && sent.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $sent';
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

    if (streamed.statusCode == 401 && _shouldEndSession(sent)) onUnauthorized?.call();
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
    final sent = tokenProvider?.call();
    try {
      response = await _client
          .get(_uri(path, query), headers: _headersFor(sent))
          .timeout(const Duration(minutes: 2));
    } on TimeoutException {
      throw ApiException('That file took too long to download.', 408);
    } catch (_) {
      final target = baseUrl.isEmpty ? 'the server' : baseUrl;
      throw ApiException("Can't reach $target to fetch that file.", 0);
    }

    if (response.statusCode == 401 && _shouldEndSession(sent)) onUnauthorized?.call();
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
  return raw.whereType<Map>().map((e) => parse(e.cast<String, dynamic>())).toList(growable: false);
}

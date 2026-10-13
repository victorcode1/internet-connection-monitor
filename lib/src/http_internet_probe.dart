import 'dart:async';

import 'package:http/http.dart' as http;

/// A read-only endpoint and the exact HTTP status that proves reachability.
final class InternetCheckEndpoint {
  /// Creates a GET or HEAD check. Redirects are never accepted.
  InternetCheckEndpoint(
    this.uri, {
    this.expectedStatusCode = 204,
    this.method = 'GET',
  }) {
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme)) {
      throw ArgumentError.value(uri, 'uri', 'Use an absolute HTTP(S) URL.');
    }
    if (method != 'GET' && method != 'HEAD') {
      throw ArgumentError.value(method, 'method', 'Use GET or HEAD.');
    }
    if (expectedStatusCode < 200 || expectedStatusCode >= 300) {
      throw ArgumentError.value(
        expectedStatusCode,
        'expectedStatusCode',
        'Use a successful HTTP status (200–299).',
      );
    }
  }

  /// The URL to check. Browser clients require a CORS-enabled endpoint.
  final Uri uri;

  /// The exact response status accepted as reachable.
  final int expectedStatusCode;

  /// The read-only HTTP method used for this endpoint.
  final String method;
}

/// Tries independent HTTP endpoints until one returns its expected status.
///
/// Each [clientFactory] call must return a fresh client. This probe owns and
/// closes every client, including requests that time out. A captive portal's
/// redirect or login page does not satisfy the default 204 checks.
final class HttpInternetProbe {
  /// Creates a probe with Google and Cloudflare as the default endpoints.
  HttpInternetProbe({
    Iterable<InternetCheckEndpoint>? endpoints,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 4),
  })  : endpoints = List.unmodifiable(endpoints ?? defaultEndpoints),
        _clientFactory = clientFactory ?? http.Client.new {
    if (this.endpoints.isEmpty) {
      throw ArgumentError.value(endpoints, 'endpoints', 'Must not be empty.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
  }

  /// The default endpoints, each requiring an exact HTTP 204 response.
  static final List<InternetCheckEndpoint> defaultEndpoints =
      List.unmodifiable([
    InternetCheckEndpoint(Uri.parse('https://www.gstatic.com/generate_204')),
    InternetCheckEndpoint(Uri.parse('https://cp.cloudflare.com/generate_204')),
  ]);

  /// The endpoints in fallback order.
  final List<InternetCheckEndpoint> endpoints;

  /// Maximum time allowed per endpoint, excluding the next fallback check.
  final Duration timeout;
  final http.Client Function() _clientFactory;
  final Map<http.Client, Completer<http.StreamedResponse?>> _requests = {};
  bool _closed = false;

  /// Returns true if an endpoint is reachable; transport failures return false.
  Future<bool> call() async {
    for (final endpoint in endpoints) {
      if (_closed) return false;
      final client = _clientFactory();
      final result = Completer<http.StreamedResponse?>();
      _requests[client] = result;
      final timer = Timer(timeout, () {
        if (!result.isCompleted) result.complete(null);
      });
      try {
        final request = http.Request(endpoint.method, endpoint.uri)
          ..followRedirects = false;
        unawaited(
          client.send(request).then(
            (response) {
              if (!result.isCompleted) result.complete(response);
            },
            onError: (Object _, StackTrace __) {
              if (!result.isCompleted) result.complete(null);
            },
          ),
        );
        final response = await result.future;
        if (_closed) return false;
        if (response?.statusCode == endpoint.expectedStatusCode) return true;
      } on Exception {
        // DNS, TLS, CORS, transport and timeout failures try the next endpoint.
      } finally {
        timer.cancel();
        if (_requests.remove(client) != null) client.close();
      }
    }
    return false;
  }

  /// Cancels owned clients and releases pending checks. Safe to call twice.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final entry in _requests.entries) {
      if (!entry.value.isCompleted) entry.value.complete(null);
      entry.key.close();
    }
    _requests.clear();
  }
}

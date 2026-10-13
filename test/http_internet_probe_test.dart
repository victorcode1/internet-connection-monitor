import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internet_connection_monitor/internet_connection_monitor.dart';
import 'package:test/test.dart';

void main() {
  test('accepts exact 204 and stops after the first successful endpoint',
      () async {
    var calls = 0;
    final probe = HttpInternetProbe(
        clientFactory: () => MockClient((request) async {
              calls++;
              expect(request.method, 'GET');
              expect(request.followRedirects, isFalse);
              return http.Response('', 204);
            }));
    expect(await probe(), isTrue);
    expect(calls, 1);
    probe.close();
  });

  for (final failure in <Object>[http.ClientException('transport'), 403, 500]) {
    test('uses the fallback after $failure', () async {
      final hosts = <String>[];
      final probe = HttpInternetProbe(
          clientFactory: () => MockClient((request) async {
                hosts.add(request.url.host);
                if (hosts.length == 1) {
                  if (failure is int) return http.Response('', failure);
                  throw failure;
                }
                return http.Response('', 204);
              }));
      expect(await probe(), isTrue);
      expect(hosts, ['www.gstatic.com', 'cp.cloudflare.com']);
      probe.close();
    });
  }

  test('rejects captive portal redirects and login pages', () async {
    var calls = 0;
    final probe = HttpInternetProbe(
        clientFactory: () => MockClient((_) async {
              return http.Response('login', ++calls == 1 ? 302 : 200);
            }));
    expect(await probe(), isFalse);
    expect(calls, 2);
    probe.close();
  });

  test('supports application-owned HEAD health endpoints and immutable config',
      () async {
    final endpoints = [
      InternetCheckEndpoint(Uri.https('example.test', '/health'),
          method: 'HEAD', expectedStatusCode: 200)
    ];
    final probe = HttpInternetProbe(
        endpoints: endpoints,
        clientFactory: () => MockClient((request) async {
              expect(request.method, 'HEAD');
              return http.Response('', 200);
            }));
    endpoints.clear();
    expect(await probe(), isTrue);
    expect(() => probe.endpoints.clear(), throwsUnsupportedError);
    probe.close();
  });

  test('closes timed-out clients and bounds the entire fallback sequence', () {
    fakeAsync((clock) {
      final clients = <_HangingClient>[];
      bool? reachable;
      final probe = HttpInternetProbe(clientFactory: () {
        final client = _HangingClient();
        clients.add(client);
        return client;
      });
      unawaited(probe().then((value) => reachable = value));
      clock.elapse(const Duration(seconds: 8));
      expect(reachable, isFalse);
      expect(clients.length, 2);
      expect(clients.every((client) => client.closed), isTrue);
      expect(clock.pendingTimers, isEmpty);
      probe.close();
    });
  });

  test('close cancels a hanging request without waiting for the timeout', () {
    fakeAsync((clock) {
      final client = _HangingClient();
      final probe = HttpInternetProbe(clientFactory: () => client);
      bool? reachable;
      unawaited(probe().then((value) => reachable = value));
      probe.close();
      probe.close();
      clock.flushMicrotasks();
      expect(reachable, isFalse);
      expect(client.closed, isTrue);
      expect(clock.pendingTimers, isEmpty);
      unawaited(probe().then((value) => expect(value, isFalse)));
      clock.flushMicrotasks();
    });
  });

  test(
      'rejects empty endpoints, invalid URLs, writable methods and zero timeout',
      () {
    expect(() => HttpInternetProbe(endpoints: []), throwsArgumentError);
    expect(
        () => HttpInternetProbe(timeout: Duration.zero), throwsArgumentError);
    expect(
        () => InternetCheckEndpoint(Uri.parse('/health')), throwsArgumentError);
    expect(() => InternetCheckEndpoint(Uri.parse('file:///tmp/health')),
        throwsArgumentError);
    expect(
        () => InternetCheckEndpoint(Uri.https('example.test'), method: 'POST'),
        throwsArgumentError);
    expect(
        () => InternetCheckEndpoint(Uri.https('example.test'),
            expectedStatusCode: 302),
        throwsArgumentError);
  });
}

class _HangingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;

  @override
  void close() => closed = true;
}

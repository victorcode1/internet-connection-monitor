import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:internet_connection_monitor/internet_connection_monitor.dart';
import 'package:test/test.dart';

void main() {
  test('starts unknown and performs no work until requested', () async {
    var calls = 0;
    final monitor = InternetConnectionMonitor(probe: () async => ++calls > 0);
    expect(monitor.status, InternetStatus.unknown);
    expect(calls, 0);
    await monitor.dispose();
  });

  test('one-shot checks do not start polling', () {
    fakeAsync((clock) {
      final monitor = InternetConnectionMonitor(probe: () async => true);
      unawaited(monitor.check());
      clock.flushMicrotasks();
      expect(monitor.status, InternetStatus.online);
      expect(clock.pendingTimers, isEmpty);
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
    });
  });

  test('a transient failure does not produce an offline transition', () {
    fakeAsync((clock) {
      var calls = 0;
      final monitor = InternetConnectionMonitor(probe: () async => ++calls > 1);
      final states = <InternetStatus>[];
      final subscription = monitor.changes.listen(states.add);
      unawaited(monitor.start());
      clock.flushMicrotasks();
      expect(monitor.status, InternetStatus.unknown);
      clock.elapse(const Duration(seconds: 2));
      expect(states, [InternetStatus.online]);
      unawaited(subscription.cancel());
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('confirms offline and recovers without interface events or duplicates',
      () {
    fakeAsync((clock) {
      var online = false;
      final monitor = InternetConnectionMonitor(probe: () async => online);
      final states = <InternetStatus>[];
      final subscription = monitor.changes.listen(states.add);
      unawaited(monitor.start());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      expect(states, [InternetStatus.offline]);
      clock.elapse(const Duration(seconds: 10));
      expect(states, [InternetStatus.offline]);
      online = true;
      clock.elapse(const Duration(seconds: 10));
      expect(states, [InternetStatus.offline, InternetStatus.online]);
      unawaited(subscription.cancel());
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
    });
  });

  test('detects Internet loss with the same Wi-Fi and recovers on manual check',
      () {
    fakeAsync((clock) {
      var online = true;
      final monitor = InternetConnectionMonitor(probe: () async => online);
      unawaited(monitor.start());
      clock.flushMicrotasks();
      online = false;
      clock.elapse(const Duration(seconds: 32));
      expect(monitor.status, InternetStatus.offline);
      online = true;
      unawaited(monitor.check());
      clock.flushMicrotasks();
      expect(monitor.status, InternetStatus.online);
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
    });
  });

  test('serializes checks and discards superseded results', () async {
    final pending = <Completer<bool>>[];
    final monitor = InternetConnectionMonitor(
      failureThreshold: 1,
      probe: () {
        final result = Completer<bool>();
        pending.add(result);
        return result.future;
      },
    );
    final first = monitor.check();
    final second = monitor.check();
    final third = monitor.check();
    expect(identical(first, second), isTrue);
    expect(identical(second, third), isTrue);
    expect(pending.length, 1);
    pending.first.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.status, InternetStatus.unknown);
    expect(pending.length, 2);
    pending.last.complete(true);
    await first;
    expect(monitor.status, InternetStatus.online);
    await monitor.dispose();
  });

  test('network changes and stream errors request fresh checks', () {
    fakeAsync((clock) {
      var calls = 0;
      final events = StreamController<Object?>();
      final monitor = InternetConnectionMonitor(
        networkChanges: events.stream,
        probe: () async => ++calls > 0,
      );
      unawaited(monitor.start());
      clock.flushMicrotasks();
      events.add('wifi');
      clock.flushMicrotasks();
      events.addError(StateError('plugin failure'));
      clock.flushMicrotasks();
      expect(calls, 3);
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
      expect(events.hasListener, isFalse);
      unawaited(events.close());
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('repeated start does not duplicate checks or subscriptions', () {
    fakeAsync((clock) {
      var calls = 0;
      final monitor = InternetConnectionMonitor(probe: () async => ++calls > 0);
      unawaited(monitor.start());
      unawaited(monitor.start());
      clock.flushMicrotasks();
      unawaited(monitor.start());
      clock.flushMicrotasks();
      expect(calls, 1);
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
    });
  });

  for (final failure in [Exception('transport'), StateError('custom probe')]) {
    test('a throwing probe recovers after $failure', () {
      fakeAsync((clock) {
        var online = false;
        final monitor = InternetConnectionMonitor(
          probe: () async {
            if (!online) throw failure;
            return true;
          },
        );
        unawaited(monitor.start());
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 2));
        expect(monitor.status, InternetStatus.offline);
        online = true;
        clock.elapse(const Duration(seconds: 10));
        expect(monitor.status, InternetStatus.online);
        unawaited(monitor.dispose());
        clock.flushMicrotasks();
      });
    });
  }

  test('bounds a hanging custom probe and ignores its late result', () {
    fakeAsync((clock) {
      final pending = Completer<bool>();
      final monitor = InternetConnectionMonitor(
        probe: () => pending.future,
        checkTimeout: const Duration(seconds: 1),
        failureThreshold: 1,
      );
      unawaited(monitor.check());
      clock.elapse(const Duration(seconds: 1));
      expect(monitor.status, InternetStatus.offline);
      pending.complete(true);
      clock.flushMicrotasks();
      expect(monitor.status, InternetStatus.offline);
      unawaited(monitor.dispose());
      clock.flushMicrotasks();
    });
  });

  test(
      'dispose releases pending checks, cancels timers and ignores late errors',
      () {
    fakeAsync((clock) {
      final pending = Completer<bool>();
      final monitor = InternetConnectionMonitor(probe: () => pending.future);
      var completed = false;
      unawaited(monitor.start().then((_) => completed = true));
      final firstDispose = monitor.dispose();
      expect(identical(firstDispose, monitor.dispose()), isTrue);
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(monitor.status, InternetStatus.unknown);
      expect(clock.pendingTimers, isEmpty);
      pending.completeError(Exception('late error'));
      clock.flushMicrotasks();
    });
  });

  test('checks after disposal report StateError', () async {
    final monitor = InternetConnectionMonitor(probe: () async => true);
    await monitor.dispose();
    await expectLater(monitor.check(), throwsStateError);
    await expectLater(monitor.start(), throwsStateError);
  });

  test('rejects invalid configuration', () {
    expect(() => InternetConnectionMonitor(failureThreshold: 0),
        throwsArgumentError);
    expect(() => InternetConnectionMonitor(checkTimeout: Duration.zero),
        throwsArgumentError);
    expect(() => InternetConnectionMonitor(confirmationDelay: Duration.zero),
        throwsArgumentError);
    expect(() => InternetConnectionMonitor(retryInterval: Duration.zero),
        throwsArgumentError);
    expect(() => InternetConnectionMonitor(onlineInterval: Duration.zero),
        throwsArgumentError);
  });
}

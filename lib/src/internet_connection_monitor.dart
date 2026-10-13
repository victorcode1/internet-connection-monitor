import 'dart:async';

import 'http_internet_probe.dart';
import 'internet_status.dart';

/// A reachability check supplied by an application or test.
typedef InternetProbe = Future<bool> Function();

/// Confirms Internet status with serialized checks and periodic recovery.
///
/// Does not depend on Flutter, a network plugin, a state manager or widgets.
/// Feed interface events through [networkChanges] and call [check] when your
/// application resumes. Interface availability itself never proves Internet.
final class InternetConnectionMonitor {
  /// Creates an inactive monitor. Call [start] to enable periodic checks.
  ///
  /// A custom [probe] owns its resources and must finish within [checkTimeout].
  /// Its exceptions count as failed checks. The built-in HTTP probe owns its
  /// clients and cancels them when this monitor is disposed.
  InternetConnectionMonitor({
    InternetProbe? probe,
    Stream<Object?>? networkChanges,
    this.failureThreshold = 2,
    this.confirmationDelay = const Duration(seconds: 2),
    this.retryInterval = const Duration(seconds: 10),
    this.onlineInterval = const Duration(seconds: 30),
    this.checkTimeout = const Duration(seconds: 10),
  }) : _networkChanges = networkChanges {
    if (failureThreshold < 1) {
      throw ArgumentError.value(
          failureThreshold, 'failureThreshold', 'Use ≥1.');
    }
    for (final entry in {
      'confirmationDelay': confirmationDelay,
      'retryInterval': retryInterval,
      'onlineInterval': onlineInterval,
      'checkTimeout': checkTimeout,
    }.entries) {
      if (entry.value <= Duration.zero) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be positive.');
      }
    }
    if (probe == null) {
      final httpProbe = HttpInternetProbe();
      _ownedProbe = httpProbe;
      _probe = httpProbe.call;
    } else {
      _probe = probe;
    }
  }

  /// Consecutive failed checks needed to confirm [InternetStatus.offline].
  final int failureThreshold;

  /// Delay before confirming an unconfirmed failure.
  final Duration confirmationDelay;

  /// Delay between checks after an offline result.
  final Duration retryInterval;

  /// Delay between checks after an online result, even without network events.
  final Duration onlineInterval;

  /// Upper bound for the whole probe, including custom probes that never finish.
  final Duration checkTimeout;
  final Stream<Object?>? _networkChanges;
  late final InternetProbe _probe;
  HttpInternetProbe? _ownedProbe;
  final StreamController<InternetStatus> _controller =
      StreamController<InternetStatus>.broadcast();
  bool _disposed = false;
  Completer<bool>? _activeProbe;
  StreamSubscription<Object?>? _networkSubscription;
  Timer? _timer;
  Future<void>? _inFlight;
  Future<void>? _disposeFuture;
  InternetStatus _status = InternetStatus.unknown;
  int _failures = 0;
  bool _started = false;
  bool _pending = false;

  /// Last confirmed state. Starts as unknown and remains readable after dispose.
  InternetStatus get status => _status;

  /// Broadcast transitions without duplicates or replay of the current state.
  ///
  /// Subscribe before [start]; late subscribers can also read [status].
  Stream<InternetStatus> get changes => _controller.stream;

  /// Whether resources were permanently released.
  bool get isDisposed => _disposed;

  /// Starts monitoring and performs the initial check. Repeated calls are safe.
  Future<void> start() {
    if (isDisposed) return Future.error(StateError('Monitor is disposed.'));
    if (_started) return _inFlight ?? Future<void>.value();
    _started = true;
    _networkSubscription = _networkChanges?.listen(
      (_) => unawaited(check()),
      onError: (Object _, StackTrace __) => unawaited(check()),
    );
    return check();
  }

  /// Checks now, discarding results superseded by another check request.
  ///
  /// Concurrent callers share completion and request one fresh check after the
  /// current probe. Without [start], this is a one-shot check with no polling.
  Future<void> check() {
    if (isDisposed) return Future.error(StateError('Monitor is disposed.'));
    _timer?.cancel();
    final running = _inFlight;
    if (running != null) {
      _pending = true;
      return running;
    }
    final completion = Completer<void>();
    _inFlight = completion.future;
    unawaited(_runChecks(completion));
    return completion.future;
  }

  Future<void> _runChecks(Completer<void> completion) async {
    try {
      do {
        _pending = false;
        final online = await _probeSafely();
        if (isDisposed) return;
        if (_pending) continue;
        _failures = online ? 0 : _failures + 1;
        if (online || _failures >= failureThreshold) {
          final next = online ? InternetStatus.online : InternetStatus.offline;
          if (_status != next) {
            _status = next;
            _controller.add(next);
          }
        }
      } while (_pending);
    } finally {
      _inFlight = null;
      if (_started && !isDisposed) {
        final delay = _failures == 0
            ? onlineInterval
            : _failures < failureThreshold
                ? confirmationDelay
                : retryInterval;
        _timer = Timer(delay, () => unawaited(check()));
      }
      completion.complete();
    }
  }

  Future<bool> _probeSafely() async {
    final result = Completer<bool>();
    _activeProbe = result;
    final timer = Timer(checkTimeout, () {
      if (!result.isCompleted) result.complete(false);
    });
    try {
      unawaited(
        Future<bool>.sync(_probe).then(
          (online) {
            if (!result.isCompleted) result.complete(online);
          },
          onError: (Object _, StackTrace __) {
            // A custom probe failure must not stop polling.
            if (!result.isCompleted) result.complete(false);
          },
        ),
      );
      return await result.future;
    } finally {
      timer.cancel();
      _activeProbe = null;
    }
  }

  /// Stops timers, cancels network events and closes the transition stream.
  ///
  /// Pending custom probes are ignored; their owners must release resources.
  /// Cancel or resume paused listeners before awaiting this method.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _started = false;
    _timer?.cancel();
    _ownedProbe?.close();
    final active = _activeProbe;
    if (active != null && !active.isCompleted) active.complete(false);
    await _networkSubscription?.cancel();
    await _inFlight;
    await _controller.close();
  }
}

# internet_connection_monitor

A Dart package for confirmed Internet reachability, with HTTP fallback checks,
periodic recovery and no Flutter or state-management dependency.

The source is available on [GitHub](https://github.com/victorcode1/internet-connection-monitor).

## Why use it?

A Wi-Fi connection or a DNS result does not prove that HTTP requests can reach
the Internet. This monitor checks reachable endpoints, tolerates a transient
failure, and detects a loss of Internet even when the network interface stays
connected.

- Starts with `InternetStatus.unknown`, rather than assuming online.
- Tries Google and then Cloudflare; an exact HTTP 204 confirms reachability.
- Requires two consecutive failed checks before reporting offline.
- Confirms an unconfirmed failure after 2 seconds, retries offline after
  10 seconds and rechecks online after 30 seconds.
- Serializes probes and discards a result superseded by a fresh check request.
- Supports custom endpoints, probes, timing and interface event streams.
- Cancels owned HTTP clients and timers on disposal.

Intervals are measured **after** each check completes. Each default endpoint
can take up to 4 seconds; the whole monitor check is bounded to 10 seconds.
Detection time includes request duration and the confirmation delay.

## Installation

```sh
dart pub add internet_connection_monitor
```

Or add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  internet_connection_monitor: ^0.1.0
```

For local development, a `path: ../internet-connection-monitor` dependency also works.

## Usage

```dart
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

final monitor = InternetConnectionMonitor();
final subscription = monitor.changes.listen((status) {
  print(status.name);
});

await monitor.start();
print(monitor.status);

// On app resume, or when the user asks to retry:
await monitor.check();

// When the owning service is disposed:
await subscription.cancel();
await monitor.dispose();
```

`changes` is a broadcast stream of transitions; it does not replay state. Read
`status` for a late subscriber, or use `initialData: monitor.status` with a
Flutter `StreamBuilder`. `start()` is idempotent. `check()` without `start()`
performs a one-shot check without polling. Checks after disposal throw
`StateError`; create a new monitor to start again.

## Flutter integration

Keep widgets, Riverpod, translations and `connectivity_plus` in your app:

```dart
final monitor = InternetConnectionMonitor(
  networkChanges: Connectivity().onConnectivityChanged,
);
await monitor.start();
```

This example requires the app's own `connectivity_plus` import and dependency.
The stream is only a trigger for a real probe. Call `check()` from your existing
app lifecycle handler when the app resumes. The package does not register a
Flutter lifecycle observer or provide a global singleton.

## Custom HTTP checks

```dart
final probe = HttpInternetProbe(
  endpoints: [
    InternetCheckEndpoint(
      Uri.https('your-domain.example', '/health'),
      method: 'HEAD',
      expectedStatusCode: 200,
    ),
  ],
);
final monitor = InternetConnectionMonitor(probe: probe.call);
try {
  await monitor.start();
} finally {
  await monitor.dispose();
  probe.close();
}
```

`clientFactory` is injectable for tests or a different HTTP transport. It must
return a **fresh client** on every call: the probe owns and closes each client.
An injected probe is owned by its caller. Dispose its resources yourself.
Custom probes should honor their own transport timeout; a monitor timeout
ignores late results but cannot cancel an arbitrary caller-owned operation.

## Interpretation and platforms

`online` means that at least one configured endpoint was reachable. `offline`
means all configured endpoints failed for the required consecutive checks.
Neither status proves the health of your business API or every Internet host.
Firewalls, provider blocks and browser CORS rules can make all probes fail even
when other services are reachable. Configure endpoints appropriate to your app.

The source uses `package:http`, without `dart:io`, and can be compiled for Dart
VM and browser targets. Browser checks require endpoints that permit CORS;
redirects and opaque responses cannot confirm the expected status. Use HTTPS
from HTTPS pages. Mobile and desktop apps must grant Internet access in their
platform configuration. Polling is subject to OS/background suspension; resume
checks are the app's responsibility.

## Development and release

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example
dart analyze
dart test
dart pub publish --dry-run
```

Review the dry-run file list, choose the publishing Google account, and publish
with `dart pub publish` when the release is approved. See the official
[Dart publishing guide](https://dart.dev/tools/pub/publishing).

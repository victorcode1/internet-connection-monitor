# internet_connection_monitor

A library that lets your app know when it has Internet access, when it loses it,
and when it comes back. Works in both Dart and Flutter projects.

[See how it works](https://victorf.dev/projects/internet-connection-monitor) ·
[Install from pub.dev](https://pub.dev/packages/internet_connection_monitor) ·
[View the code on GitHub](https://github.com/victorcode1/internet-connection-monitor)

## What is it for?

Having Wi-Fi does not always mean having Internet. This library checks the
connection and notifies your app when it changes.

Your app can use that result to show a **"No Internet"** message, offer a
**"Retry"** button, or wait before resending data. You decide what message to
show and what to do next.

## How it works

1. Your app asks to check the connection.
2. The library tries to get a response from the Internet. If the first address
   fails, it tries another.
3. Your app receives the result and can notify the user.

By default, it waits for two consecutive failed checks before confirming there
is no Internet. This avoids warning about a momentary failure. It also keeps
checking to detect when the connection returns.

## Installation

In a Dart project, run:

```sh
dart pub add internet_connection_monitor
```

With Flutter, use:

```sh
flutter pub add internet_connection_monitor
```

You can also add it to your `pubspec.yaml`:

```yaml
dependencies:
  internet_connection_monitor: ^0.1.3
```

## A quick example to get started

This code prints the notifications in English. Save it as `bin/main.dart` in a
Dart console project and run it with `dart run bin/main.dart`.

```dart
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

String connectionMessage(InternetStatus status) {
  switch (status) {
    case InternetStatus.unknown:
      return 'Checking';
    case InternetStatus.online:
      return 'Online';
    case InternetStatus.offline:
      return 'Offline';
  }
}

Future<void> main() async {
  final monitor = InternetConnectionMonitor();
  final notifications = monitor.changes.listen((status) {
    print(connectionMessage(status));
  });

  try {
    print(connectionMessage(monitor.status));
    await monitor.start();

    // This demo stays active for 10 seconds.
    await Future<void>.delayed(const Duration(seconds: 10));

    // You can use this call in a "Retry" button.
    await monitor.check();
  } finally {
    // When done, stop listening and stop the checks.
    await notifications.cancel();
    await monitor.dispose();
  }
}
```

At the start you will see **"Checking"**. Then **"Online"** or **"Offline"**
appears once the result is confirmed. If the result does not change, the library
does not repeat the same notification.

The example ends after waiting 10 seconds and doing one last check. In a real
app, keep the monitor active as long as you need it and stop it when you no
longer use it.

## The calls you will use

| Call                          | What it does                                                        |
| ----------------------------- | ------------------------------------------------------------------- |
| `monitor.start()`             | Starts checking the connection and keeps doing so periodically.     |
| `monitor.changes.listen(...)` | Receives a notification when the result changes.                    |
| `monitor.status`              | Tells you the last known result.                                    |
| `monitor.check()`             | Asks to check again, for example when tapping "Retry".              |
| `monitor.dispose()`           | Stops the monitor when you finish using it.                         |

The names in the code mean the following:

| Name in code | In plain words                                                           |
| ------------ | ------------------------------------------------------------------------ |
| `unknown`    | We do not know yet whether there is a connection.                        |
| `online`     | At least one Internet address responded as expected.                     |
| `offline`    | The checks failed enough times to confirm there is no connection.        |

## Flutter example: showing "No Internet"

This example shows a notice at the top of your screen when Internet is lost.
When the connection returns, the notice disappears. The **"Retry"** button asks
for a new check.

### 1. Add the library

Inside your Flutter project, run:

```sh
flutter pub add internet_connection_monitor
```

### 2. Create the notice widget

Create the file `lib/internet_notice.dart` and paste this code:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

class InternetNotice extends StatefulWidget {
  const InternetNotice({super.key, required this.child});

  final Widget child;

  @override
  State<InternetNotice> createState() => _InternetNoticeState();
}

class _InternetNoticeState extends State<InternetNotice>
    with WidgetsBindingObserver {
  final _monitor = InternetConnectionMonitor();
  late final StreamSubscription<InternetStatus> _subscription;
  InternetStatus _status = InternetStatus.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Listen before starting the checks.
    _subscription = _monitor.changes.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });

    unawaited(_monitor.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_monitor.check());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_status == InternetStatus.offline)
          MaterialBanner(
            content: const Text(
              'No Internet. Waiting for the connection to return.',
            ),
            leading: const Icon(Icons.wifi_off),
            actions: [
              TextButton(
                onPressed: () => unawaited(_monitor.check()),
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(child: widget.child),
      ],
    );
  }

  Future<void> _closeMonitor() async {
    await _subscription.cancel();
    await _monitor.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeMonitor());
    super.dispose();
  }
}
```

The `changes.listen(...)` part listens for changes. `setState` updates what is
shown on screen. `mounted` avoids updating a widget that has already closed. It
also checks the connection when returning to the app and cancels the
subscription when the widget closes.

### 3. Use it on your screen

This `lib/main.dart` is a small, complete app. Replace the centered text with
your own screen content:

```dart
import 'package:flutter/material.dart';

import 'internet_notice.dart';

void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('My app')),
        body: const InternetNotice(
          child: Center(child: Text('Your screen content goes here')),
        ),
      ),
    ),
  );
}
```

Run `flutter run` to open it.

### What you will see and how to test it

- When the app opens, the connection is still being checked. No offline notice
  appears until the result is confirmed.
- If there is no Internet, the **"No Internet"** message appears with
  **"Retry"**.
- If the connection returns, the notice disappears automatically.
- To test both cases, turn off Wi-Fi and mobile data and then turn them back on.
  Detection can take a few seconds: the library confirms failures and checks
  again every so often.

This widget creates its own monitor and stops it when the screen closes. If you
want to share the connection across the whole app, create **a single monitor** in
the part that stays active while the app is used and share its result between
screens. Do not create the monitor inside `build()` and do not close from one
screen a monitor that other screens also use.

On Android, enable Internet in `android/app/src/main/AndroidManifest.xml`, inside
`<manifest>` and outside `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

On macOS, enable the app's outgoing network connections. For Flutter web, see
"Using it on web pages and other apps" below: the check addresses must allow
requests from your page.

## What "having Internet" means in this library

The result indicates whether any of the checked addresses responded as expected.
A specific site may still fail even when the result is **"Online"**.

If a network blocks the check addresses, the result may be **"Offline"** even
though other sites work. You can choose which addresses are checked to adapt
them to your app.

<details>
<summary><strong>More options, if you need them</strong></summary>

### How often it checks again

These are the starting values. You can change them when creating the monitor.

| Situation                                  | Checks again after   | Option in code        |
| ------------------------------------------ | -------------------- | --------------------- |
| The first check failed and needs confirming | After 2 seconds      | `confirmationDelay`   |
| Confirmed there is no Internet             | After 10 seconds     | `retryInterval`       |
| There is Internet                          | After 30 seconds     | `onlineInterval`      |

The times start counting **when the previous check finishes**. Each address can
take up to 4 seconds to respond. A complete check is limited to 10 seconds with
`checkTimeout`. For that reason, detecting a change can take longer than the
wait time in the table.

`failureThreshold` lets you choose how many consecutive failed checks are
required before reporting no connection. The starting value is `2`.

### Choosing another address to check

By default, Google and Cloudflare addresses are tried. A response with code
`204` is expected, which indicates a correct response with no content. A Wi-Fi
login page does not count as that response.

You can use your own address and choose which response it must return. This
block is a complete example; change `your-domain.example` to your address before
running it.

```dart
import 'package:internet_connection_monitor/internet_connection_monitor.dart';

Future<void> main() async {
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
    print(monitor.status.name);
  } finally {
    await monitor.dispose();
    probe.close();
  }
}
```

In this example, `HEAD` asks for a response without downloading the content and
`200` is the code we expect to receive. You can also use `GET` if your address
needs it. The library accepts exactly the response you chose; a redirect to
another page does not count as a valid response.

If you pass your own probe via `probe`, you are responsible for closing it, as
`probe.close()` does in the example. If you use `clientFactory`, it returns a new
client on each call: the library closes each one when it finishes.

A custom probe must limit how long it waits. The monitor can stop waiting for
its result, but it cannot by itself stop an operation you created outside the
library.

### Receiving the notifications in Flutter

Start listening to the notifications before calling `start()`, as in the
example. If you start listening afterwards, also read `monitor.status`: earlier
notifications are not sent again. If you use `StreamBuilder`, you can pass it
`initialData: monitor.status` so it has an initial result.

When the app returns to the foreground, call `monitor.check()` from the part of
your code that detects that return. The library does not do it by itself. If you
already detect Wi-Fi changes in your app, you can send those notifications via
`networkChanges` to ask for another check. Detecting Wi-Fi still does not prove
there is Internet.

### A few things to keep in mind

- You can call `start()` several times: it does not create repeated checks.
- If you call `check()` without first calling `start()`, you perform a single
  check; periodic checking is not started.
- Checks run one after another. If a new one is requested while another is in
  progress, the previous result is discarded and a new one runs.
- After `dispose()`, create a new monitor if you want to start again.
- Cancel the notifications you listen to before waiting for `dispose()` to
  finish. If you have paused a listener, resume or cancel it so that closing can
  finish.

### Using it on web pages and other apps

On a web page, the checked address must allow requests from your page. This
permission is called **CORS**. If it is missing, the browser may block the
check. Use `https` addresses when your page also uses `https`. A response the
browser is not allowed to read also does not confirm the connection.

In mobile and desktop apps, make sure your app has permission to use the
Internet. The system may pause checks while the app is not in use; ask for
another check when it returns to the foreground.

</details>

## Contributing

You can [report a problem or propose an improvement](https://github.com/victorcode1/internet-connection-monitor/issues).
The library can be used and shared under the [MIT license](LICENSE).

To review the changes on your computer:

```sh
dart pub get
dart format --output=none --set-exit-if-changed lib test example
dart analyze
dart test
dart pub publish --dry-run
```

The last command reviews what would be published without uploading it to
pub.dev. The actual publish is done with `dart pub publish`.
See the [official publishing guide](https://dart.dev/tools/pub/publishing).

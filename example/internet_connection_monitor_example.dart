import 'dart:async';

import 'package:internet_connection_monitor/internet_connection_monitor.dart';

Future<void> main() async {
  final monitor = InternetConnectionMonitor();
  final subscription = monitor.changes.listen((status) {
    print('Internet: ${status.name}');
  });

  try {
    await monitor.start();
    print('Confirmed state: ${monitor.status.name}');
    // A real app keeps monitoring until its owning service is disposed.
    await Future<void>.delayed(const Duration(seconds: 3));
  } finally {
    await subscription.cancel();
    await monitor.dispose();
  }
}

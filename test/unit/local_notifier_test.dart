import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/local_notifier.dart';

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  test('clearAll delegates to the platform notification plugin', () async {
    final plugin = _MockNotificationsPlugin();
    when(plugin.cancelAll).thenAnswer((_) async {});

    await FlutterLocalNotifier(plugin).clearAll();

    verify(plugin.cancelAll).called(1);
  });
}

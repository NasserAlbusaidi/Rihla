import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #484 — guard: push notifications must use the branded small-icon, never the
/// stock Flutter launcher.
///
/// A small notification icon is rendered by the OS using ONLY its alpha mask
/// (tinted white/accent), so a full-colour launcher mipmap collapses to a blank
/// white square on the status bar. The brand mark lives as a white-on-
/// transparent alpha silhouette at every density in `res/drawable-*/
/// ic_launcher_monochrome.png`, so both code paths must point there:
///
/// 1. Foreground (app open): `FlutterLocalNotifier` renders the notification
///    itself — its init default icon + per-notification `icon` must be the
///    branded drawable, not `@mipmap/ic_launcher` (which doesn't even exist;
///    the launcher is `@mipmap/launcher_icon`, so the lookup fails → stock).
/// 2. Backgrounded/terminated (OS-displayed FCM): the OS reads
///    `com.google.firebase.messaging.default_notification_icon` from the
///    manifest. Absent → it falls back to the app icon → white square.
void main() {
  test('local_notifier uses the branded small-icon, not stock launcher (#484)',
      () {
    final source =
        File('lib/core/services/local_notifier.dart').readAsStringSync();

    expect(
      source,
      isNot(contains('@mipmap/ic_launcher')),
      reason:
          'local_notifier must not reference the stock launcher mipmap — a '
          'full-colour icon renders as a white square in the status bar. Use '
          'the branded ic_launcher_monochrome alpha silhouette.',
    );
    expect(
      source,
      contains('ic_launcher_monochrome'),
      reason:
          'Foreground notifications (init defaultIcon + AndroidNotificationDetails '
          'icon) must reference the branded ic_launcher_monochrome drawable.',
    );
  });

  test('AndroidManifest declares the branded FCM notification icon (#484)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_icon'),
      reason:
          'Backgrounded/terminated FCM notifications are rendered by the OS, '
          'which needs default_notification_icon meta-data; absent → it uses '
          'the app icon → white square.',
    );
    expect(
      manifest,
      contains('@drawable/ic_launcher_monochrome'),
      reason:
          'The FCM default_notification_icon must point at the branded '
          'white-on-transparent ic_launcher_monochrome drawable.',
    );
  });
}

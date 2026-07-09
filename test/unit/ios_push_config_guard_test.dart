import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #941 — guard: the iOS remote-push plumbing must stay wired.
///
/// FCM delivery on iOS depends on two static config keys that never surface in
/// a unit or widget test (they only matter on a signed device build), so a
/// silent regression — someone pruning the plist or entitlements — would go
/// unnoticed until a real-device push fails to arrive. These string guards fail
/// fast in CI instead:
///
/// 1. `UIBackgroundModes: remote-notification` in `Info.plist` — lets iOS wake
///    the app for background/content-available pushes.
/// 2. `aps-environment` in `Runner.entitlements` — the Push Notifications
///    capability. Its value is `development`; automatic signing rewrites it to
///    `production` at app-store archive time, so the checked-in value is fine.
void main() {
  test('iOS Info.plist enables the remote-notification background mode (#941)',
      () {
    final plist = File('ios/Runner/Info.plist');
    expect(plist.existsSync(), isTrue);

    final source = plist.readAsStringSync();
    expect(
      source,
      contains('UIBackgroundModes'),
      reason:
          'Info.plist must declare UIBackgroundModes so iOS can wake the app '
          'for FCM/APNs remote notifications.',
    );
    expect(
      source,
      contains('<string>remote-notification</string>'),
      reason:
          'UIBackgroundModes must include remote-notification — without it '
          'background/content-available pushes are not delivered on iOS.',
    );
  });

  test('iOS entitlements declare the Push Notifications capability (#941)', () {
    final entitlements = File('ios/Runner/Runner.entitlements');
    expect(entitlements.existsSync(), isTrue);

    expect(
      entitlements.readAsStringSync(),
      contains('aps-environment'),
      reason:
          'Runner.entitlements must carry aps-environment (the Push '
          'Notifications capability) or APNs registration fails on device. '
          'Automatic signing rewrites development→production at archive time.',
    );
  });
}

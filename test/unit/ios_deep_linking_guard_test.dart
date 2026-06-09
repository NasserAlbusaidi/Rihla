import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #369 — guard: Flutter/go_router native deep-linking must stay OFF on iOS.
///
/// Inbound deep links are owned solely by `app_links` (`deep_link_service.dart`).
/// Android hard-disables Flutter's native handler via the
/// `flutter_deeplinking_enabled=false` meta-data in `AndroidManifest.xml`.
/// iOS has no equivalent flag in the manifest — it relies on
/// `FlutterDeepLinkingEnabled` being **absent** from `Info.plist` (off by
/// default). Setting it to `YES` turns on go_router's native handler while
/// app_links is still live, so the same Universal Link opens the app **and**
/// Safari (the documented double-handler bug).
///
/// This test FAILS if anyone adds `<key>FlutterDeepLinkingEnabled</key>` to
/// `ios/Runner/Info.plist`.
void main() {
  test('iOS Info.plist does not enable Flutter native deep linking (#369)', () {
    final plist = File('ios/Runner/Info.plist');

    expect(plist.existsSync(), isTrue);
    expect(
      plist.readAsStringSync(),
      isNot(contains('FlutterDeepLinkingEnabled')),
      reason:
          'Never set FlutterDeepLinkingEnabled in ios/Runner/Info.plist — '
          'app_links owns inbound deep links; enabling go_router/Flutter native '
          'deep-linking double-handles Universal Links on iOS (opens the app AND '
          'Safari). Android disables the equivalent via '
          'flutter_deeplinking_enabled=false in AndroidManifest.xml.',
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Runner.entitlements carries the Sign in with Apple entitlement (#1256)',
      () {
    final content = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(content, contains('com.apple.developer.applesignin'));
  });
}

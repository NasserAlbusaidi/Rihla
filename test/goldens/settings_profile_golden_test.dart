import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Settings profile screen — light and dark theme-smoke goldens',
      (tester) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/settings_profile',
      harness: const GoldenHarness(
        title: 'Profile',
        subtitle: 'Manage your account',
        rows: [
          (label: 'Name', value: 'Sample User'),
          (label: 'Theme', value: 'System'),
          (label: 'Currency', value: 'OMR'),
          (label: 'Notifications', value: 'On'),
          (label: 'Version', value: 'v1.0.0'),
        ],
      ),
    );
  });
}

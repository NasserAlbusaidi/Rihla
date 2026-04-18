import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Onboarding screen — light and dark theme-smoke goldens',
      (tester) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/onboarding',
      harness: const GoldenHarness(
        title: 'Welcome to Rihla',
        subtitle: 'Plan trips with friends',
        rows: [
          (label: 'Create groups', value: ''),
          (label: 'Track expenses', value: ''),
          (label: 'Split fairly', value: ''),
        ],
      ),
    );
  });
}

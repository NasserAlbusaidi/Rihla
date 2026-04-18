import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Memories screen — light and dark theme-smoke goldens',
      (tester) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/memories',
      harness: const GoldenHarness(
        title: 'Memories',
        subtitle: '3 photos shared',
        rows: [
          (label: 'Sunrise at camp', value: 'Alice'),
          (label: 'Wadi pool jump', value: 'Bob'),
          (label: 'Group photo', value: 'Carol'),
        ],
      ),
    );
  });
}

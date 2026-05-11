import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets(
    'Group detail screen — light and dark theme-smoke goldens',
    (tester) async {
      await pumpThemeVariants(
        tester,
        baselineStem: 'goldens/group_detail',
        harness: const GoldenHarness(
          title: 'Wadi Shab Weekend',
          subtitle: '5 members • 2 events',
          rows: [
            (label: 'Camping trip', value: 'OMR 28.250'),
            (label: 'Dinner', value: 'OMR 14.000'),
            (label: 'Fuel', value: 'OMR 6.500'),
          ],
        ),
      );
    },
    tags: const ['golden'],
  );
}

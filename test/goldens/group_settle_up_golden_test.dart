import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets(
    'Group settle up screen — light and dark theme-smoke goldens',
    (tester) async {
      await pumpThemeVariants(
        tester,
        baselineStem: 'goldens/group_settle_up',
        harness: const GoldenHarness(
          title: 'Settle Up',
          subtitle: '3 suggested transfers',
          rows: [
            (label: 'Alice owes Bob', value: 'OMR 12.500'),
            (label: 'Carol owes Alice', value: 'OMR 8.000'),
            (label: 'Bob owes Carol', value: 'OMR 4.250'),
          ],
        ),
      );
    },
    tags: const ['golden'],
  );
}

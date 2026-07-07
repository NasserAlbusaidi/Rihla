import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets(
    'Add expense screen — light and dark theme-smoke goldens',
    (tester) async {
      await pumpThemeVariants(
        tester,
        baselineStem: 'goldens/add_expense',
        harness: const GoldenHarness(
          title: 'Add expense',
          subtitle: 'Split evenly among members',
          rows: [
            (label: 'Amount', value: 'OMR 0.000'),
            (label: 'Payer', value: 'You'),
            (label: 'Category', value: 'Food'),
            (label: 'Split', value: 'Even'),
          ],
        ),
      );
    },
    tags: const ['golden'],
  );
}

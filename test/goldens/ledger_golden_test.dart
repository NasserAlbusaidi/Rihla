import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Ledger screen — light and dark theme-smoke goldens', (
    tester,
  ) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/ledger',
      harness: const GoldenHarness(
        title: 'Ledger',
        subtitle: 'Event total OMR 124.500',
        rows: [
          (label: 'Hotel — Alice paid', value: 'OMR 75.000'),
          (label: 'Fuel — Bob paid', value: 'OMR 18.500'),
          (label: 'Groceries — Carol paid', value: 'OMR 22.750'),
          (label: 'Coffee — Alice paid', value: 'OMR 8.250'),
        ],
      ),
    );
  }, tags: const ['golden']);
}

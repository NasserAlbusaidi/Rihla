import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Gear screen — light and dark theme-smoke goldens', (
    tester,
  ) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/gear',
      harness: const GoldenHarness(
        title: 'Gear',
        subtitle: '4 items • 2 claimed',
        rows: [
          (label: 'Tent (3-person)', value: 'Alice'),
          (label: 'Cooler', value: 'Bob'),
          (label: 'First aid kit', value: 'Unclaimed'),
          (label: 'Speakers', value: 'Unclaimed'),
        ],
      ),
    );
  }, tags: const ['golden']);
}

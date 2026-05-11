import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets('Home screen — light and dark theme-smoke goldens', (
    tester,
  ) async {
    await pumpThemeVariants(
      tester,
      baselineStem: 'goldens/home',
      harness: const GoldenHarness(
        title: 'Home',
        subtitle: '2 active groups',
        rows: [
          (label: 'Weekend in Wadi Shab', value: 'OMR 42.000'),
          (label: 'Muscat dinner crew', value: 'OMR 18.500'),
        ],
      ),
    );
  }, tags: const ['golden']);
}

import 'package:flutter_test/flutter_test.dart';

import 'golden_harness.dart';

void main() {
  testWidgets(
    'Logistics screen — light and dark theme-smoke goldens',
    (tester) async {
      await pumpThemeVariants(
        tester,
        baselineStem: 'goldens/logistics',
        harness: const GoldenHarness(
          title: 'Logistics',
          subtitle: 'Day 1 itinerary',
          rows: [
            (label: '08:00 Meet at campus', value: ''),
            (label: '10:30 Arrive at Wadi', value: ''),
            (label: '12:00 Lunch + hike', value: ''),
            (label: '17:00 Pack up', value: ''),
          ],
        ),
      );
    },
    tags: const ['golden'],
  );
}

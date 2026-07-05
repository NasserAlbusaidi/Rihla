import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/shared/widgets/falaj_fork.dart';

import 'painter_golden_harness.dart';

/// GATE ARTIFACT (spec §PR-3): the settle-up connector swap (component 8)
/// is conditional on these baselines being legible at 16px and 24px, in
/// both writing directions. Review by eye after regenerating — this
/// directory is macOS-only + CI-excluded, a local visual gate, not a CI gate.
void main() {
  testWidgets(
    'FalajFork — 16px wordmark box, LTR + RTL',
    (tester) async {
      await pumpPainterGolden(
        tester,
        baselineStem: 'goldens/falaj_fork_16',
        // 16px type * 1.6 / 0.32, per WordmarkLogo's box formula. No color
        // override — resolves to context.colors.primary (brass), matching
        // production.
        child: const FalajFork(size: Size(25.6, 5.12)),
        brightness: Brightness.light,
      );
    },
    tags: const ['golden'],
  );

  testWidgets(
    'FalajFork — 24px wordmark box, LTR + RTL',
    (tester) async {
      await pumpPainterGolden(
        tester,
        baselineStem: 'goldens/falaj_fork_24',
        // 24px type * 1.6 / 0.32.
        child: const FalajFork(size: Size(38.4, 7.68)),
        brightness: Brightness.light,
      );
    },
    tags: const ['golden'],
  );
}

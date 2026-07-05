import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';

/// Pumps a fixed-size painter [child] under both [TextDirection]s and
/// matches each against `'${baselineStem}_ltr.png'` /
/// `'${baselineStem}_rtl.png'`.
///
/// **Net-new to the repo:** [pumpThemeVariants] (`golden_harness.dart`) is
/// LTR-only — it has no [Directionality] wrapper. Painter devices that
/// mirror by reading direction (e.g. `FalajForkPainter`) need an RTL axis
/// the existing harness can't produce, hence this sibling helper.
Future<void> pumpPainterGolden(
  WidgetTester tester, {
  required String baselineStem,
  required Widget child,
  required Brightness brightness,
}) async {
  const boundaryKey = ValueKey('painter_golden_boundary');
  for (final (dir, suffix) in const [
    (TextDirection.ltr, 'ltr'),
    (TextDirection.rtl, 'rtl'),
  ]) {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme,
        home: Directionality(
          textDirection: dir,
          child: Center(
            child: RepaintBoundary(key: boundaryKey, child: child),
          ),
        ),
      ),
    );
    // NOTE: `find.byType(RepaintBoundary).first` is NOT safe here — Flutter
    // inserts its own ancestor RepaintBoundary(s) in the MaterialApp tree, so
    // `.first`/`.last` can silently match a full-viewport boundary instead of
    // the one explicitly wrapping [child] (this shipped once as an 800x600
    // baseline instead of the painter's actual box). Find by key instead.
    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('${baselineStem}_$suffix.png'),
    );
  }
}

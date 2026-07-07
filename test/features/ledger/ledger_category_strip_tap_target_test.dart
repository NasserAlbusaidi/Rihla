import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_category_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1041 §4: category filter chips must expose a >=44dp effective hit
/// region — the visual pill itself stays compact (see the widget's Center
/// wrapper); only the invisible GestureDetector hit box grows.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('All chip hit region is >=44dp tall', (tester) async {
    await tester.pumpWidget(
      wrap(
        LedgerCategoryStrip(
          expenses: const [],
          totalCount: 2,
          active: null,
          onChange: (_) {},
        ),
      ),
    );

    final hitRegion = find
        .ancestor(
          of: find.text('(2)'),
          matching: find.byType(GestureDetector),
        )
        .first;
    final size = tester.getSize(hitRegion);
    expect(size.height, greaterThanOrEqualTo(44));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_category_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #155 — the "All" filter pill rendered one string `الكل · 2`, whose `·`
/// separator collapses against the count in RTL so it reads as `الكل ٢٠`
/// ("All 20"). Label and count must be structurally distinct, separator-free,
/// and the count LTR-isolated (Western digit, per #145).
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    locale: const Locale('ar'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('All filter pill: label and count are distinct, no collapsing separator (ar)', (
    tester,
  ) async {
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

    expect(find.text('الكل'), findsOneWidget); // label is its own node
    expect(find.text('(2)'), findsOneWidget); // count is its own delimited node
    expect(find.textContaining('·'), findsNothing); // collapsing separator gone

    final dir = tester.widget<Directionality>(
      find.ancestor(
        of: find.text('(2)'),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(dir.textDirection, TextDirection.ltr); // count is LTR-isolated
  });

  testWidgets('empty-state All pill is also split and separator-free (ar)', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LedgerCategoryStripEmpty()));

    expect(find.text('الكل'), findsOneWidget);
    expect(find.text('(0)'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });
}

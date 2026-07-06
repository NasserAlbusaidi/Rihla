import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/activity_glyph.dart';
import 'package:safar/shared/widgets/activity_row.dart';

/// #967 — an interactive [ActivityRow] must announce as a single merged button
/// (not a stream of unlabeled text fragments); an inert (onTap-less) row must
/// stay inert (the #866 event feed passes no onTap).
Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

ActivityRow _row({VoidCallback? onTap}) => ActivityRow(
  glyph: ActivityGlyph.expenseAdded,
  actorName: 'Layla',
  description: 'added an expense',
  timestamp: DateTime(2026, 5, 1),
  onTap: onTap,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('an interactive row merges into one button node with a '
      'composed label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_row(onTap: () {})));

    final node = tester.getSemantics(find.byType(InkWell));
    final data = node.getSemanticsData();
    expect(node.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.label, contains('Layla'));
    expect(data.label, contains('added an expense'));
    handle.dispose();
  });

  testWidgets('an inert (onTap-less) row exposes no button node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(_row()));

    expect(find.byType(InkWell), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.button ?? false),
      ),
      findsNothing,
    );
    handle.dispose();
  });
}

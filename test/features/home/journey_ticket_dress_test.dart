import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';
import 'package:safar/features/home/widgets/journey_ticket_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Falaj rebrand PR-3, component 3 — proves the journey ticket's tear-line
/// re-dresses to brass and the corner seal renders.
void main() {
  final entry = ActiveJourneyEntry(
    eventId: 'e1',
    groupId: 'g1',
    title: 'Tokyo',
    type: EventType.trip,
    memberNames: const ['Aisha', 'Bilal'],
    startDate: null,
    endDate: null,
    createdAt: DateTime(2026),
    nets: [(currency: 'OMR', net: Decimal.parse('1.4'))],
    fallbackCurrency: 'OMR',
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('perforation tear-line is brass, not the old rule2 color', (
    tester,
  ) async {
    await tester.pumpWidget(host(JourneyTicketCard(entry: entry)));

    final colors = AppTheme.lightTheme.extension<AppColorTokens>()!;
    final painterFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_DashedRulePainter',
    );
    expect(painterFinder, findsOneWidget);

    final customPaint = tester.widget<CustomPaint>(painterFinder);
    final dynamic painter = customPaint.painter;
    expect(painter.color, colors.primary.withValues(alpha: 0.35));
    expect(painter.color, isNot(colors.rule2));
  });

  testWidgets('brass corner seal renders on the content stub', (tester) async {
    await tester.pumpWidget(host(JourneyTicketCard(entry: entry)));

    expect(find.byKey(HomeKeys.journeyTicketSeal), findsOneWidget);
  });
}

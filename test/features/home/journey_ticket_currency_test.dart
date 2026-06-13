import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/home/providers/active_journeys_provider.dart';
import 'package:safar/features/home/widgets/journey_ticket_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #261 PR-B — proves the journey ticket renders the entry's own currency, not
/// hardcoded OMR (non-OMR no-op proof for the home journey strip).
void main() {
  ActiveJourneyEntry entry(String currency, String balance) => ActiveJourneyEntry(
    eventId: 'e1',
    groupId: 'g1',
    title: 'Tokyo',
    type: EventType.trip,
    memberNames: const ['Aisha', 'Bilal'],
    startDate: null,
    endDate: null,
    createdAt: DateTime(2026),
    nets: [(currency: currency, net: Decimal.parse(balance))],
    fallbackCurrency: currency,
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('journey ticket shows JPY (0dp), not OMR', (tester) async {
    await tester.pumpWidget(host(JourneyTicketCard(entry: entry('JPY', '1200'))));
    expect(find.textContaining('JPY'), findsOneWidget);
    expect(find.textContaining('OMR'), findsNothing);
    expect(find.textContaining('1200.000'), findsNothing); // no OMR 3dp drift
  });

  testWidgets('journey ticket shows USD (2dp)', (tester) async {
    await tester.pumpWidget(host(JourneyTicketCard(entry: entry('USD', '12.50'))));
    expect(find.textContaining('USD'), findsOneWidget);
    expect(find.textContaining('OMR'), findsNothing);
  });

  testWidgets('journey ticket renders every currency bucket (#382 PR-5)', (
    tester,
  ) async {
    final multi = ActiveJourneyEntry(
      eventId: 'e1',
      groupId: 'g1',
      title: 'Tokyo',
      type: EventType.trip,
      memberNames: const ['Aisha', 'Bilal'],
      startDate: null,
      endDate: null,
      createdAt: DateTime(2026),
      nets: [
        (currency: 'OMR', net: Decimal.parse('1.4')),
        (currency: 'AED', net: Decimal.parse('41')),
      ],
      fallbackCurrency: 'OMR',
    );
    await tester.pumpWidget(host(JourneyTicketCard(entry: multi)));
    expect(find.textContaining('OMR'), findsOneWidget);
    expect(find.textContaining('AED'), findsOneWidget);
  });

  testWidgets('settled journey ticket renders zero in fallback currency', (
    tester,
  ) async {
    final settled = ActiveJourneyEntry(
      eventId: 'e1',
      groupId: 'g1',
      title: 'Tokyo',
      type: EventType.trip,
      memberNames: const ['Aisha', 'Bilal'],
      startDate: null,
      endDate: null,
      createdAt: DateTime(2026),
      nets: const [],
      fallbackCurrency: 'OMR',
    );
    await tester.pumpWidget(host(JourneyTicketCard(entry: settled)));
    expect(settled.isSettled, isTrue);
    expect(find.textContaining('OMR'), findsOneWidget);
  });
}

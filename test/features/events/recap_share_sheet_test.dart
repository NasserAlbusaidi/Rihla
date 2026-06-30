import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/widgets/recap_share_card.dart';
import 'package:safar/features/events/widgets/recap_share_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// The sheet composes two already-unit-tested primitives — captureBoundaryPng
// (widget_to_image_test: boundary → PNG bytes) and shareImage (share_helper_test:
// → 'shareFiles' with image/png mime + non-zero origin). This file covers the
// composition: the sheet renders the exact card inside the capture boundary with
// a wired Share-image CTA. The full tap→capture→share path is deliberately NOT
// driven here — _share interleaves setState (needs frame pumps) with toImage /
// temp-file I/O (needs tester.runAsync), which cannot both run in one test zone.

EventRecap _recap() => EventRecap(
      eventId: 'e1',
      eventName: 'Wadi Shab Weekend',
      startDate: DateTime(2026, 3, 12),
      endDate: DateTime(2026, 3, 14),
      participantCount: 3,
      expenseCount: 4,
      totalSpentByCurrency: {'OMR': Decimal.parse('142.350')},
      userPaidByCurrency: const {},
      userShareByCurrency: const {},
      userSettledByCurrency: const {},
      userNetByCurrency: const {},
      biggestExpenseByCurrency: const {},
      payerTotalsByCurrency: {
        'OMR': [(participantId: 'a', amount: Decimal.parse('88.000'))],
      },
      categoryTotalsByCurrency: {
        'OMR': [(categoryId: 'food', total: Decimal.parse('142.350'))],
      },
      participantNetsByCurrency: {
        'OMR': [(participantId: 'a', net: Decimal.zero)],
      },
      isSettledByCurrency: const {'OMR': true},
      isEmpty: false,
    );

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showRecapShareSheet(
                context,
                recap: _recap(),
                roster: const {'a': 'Ahmed'},
                eventType: EventType.trip,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  testWidgets('sheet renders the recap card inside a capture boundary + CTA',
      (tester) async {
    await _openSheet(tester);

    expect(find.byKey(EventKeys.recapShareSheet), findsOneWidget);
    expect(find.byType(RecapShareCard), findsOneWidget);
    // The card sits inside a RepaintBoundary so it can be rasterized.
    expect(
      find.ancestor(
        of: find.byType(RecapShareCard),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(find.byKey(EventKeys.recapShareConfirmButton), findsOneWidget);
    expect(find.text('Share image'), findsOneWidget);
  });
}

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/models/trip_receipt.dart';
import 'package:safar/features/events/providers/trip_receipt_provider.dart';
import 'package:safar/features/events/widgets/recap_share_card.dart';
import 'package:safar/features/events/widgets/recap_share_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// The sheet composes two already-unit-tested primitives — captureBoundaryPng
// (widget_to_image_test: boundary → PNG bytes) and shareImage/shareCsv
// (share_helper_test). This file covers the composition: the sheet renders the
// card inside the capture boundary, a Share-image CTA, and a Trip-Receipt CSV
// CTA that is gated on the receipt resolving (AsyncData). The tap→share path is
// NOT driven here — it interleaves setState with temp-file I/O across zones.

const _eventRef = (groupId: 'g1', eventId: 'e1');

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

TripReceipt _receipt() => TripReceipt(
      eventId: 'e1',
      eventName: 'Wadi Shab Weekend',
      eventType: EventType.trip,
      startDate: null,
      endDate: null,
      isClosed: false,
      closedAt: null,
      closedByName: null,
      generatedAt: DateTime(2026, 3, 14),
      participantNames: const ['Ahmed'],
      expenses: [
        (
          id: 'x1',
          date: DateTime(2026, 3, 12),
          description: 'Lunch',
          categoryId: 'food',
          payerName: 'Ahmed',
          amount: Decimal.parse('10.000'),
          currency: 'OMR',
          splitMode: 'equally',
        ),
      ],
      allocations: const [],
      corrections: const [],
      correctionsCoverage: AuditCoverage.complete,
      settlements: const [],
      netsByCurrency: const {},
      currencies: const ['OMR'],
    );

Future<void> _openSheet(
  WidgetTester tester,
  AsyncValue<TripReceipt> receipt,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripReceiptProvider.overrideWith((ref, arg) => receipt),
      ],
      child: MaterialApp(
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
                  eventRef: _eventRef,
                ),
                child: const Text('Open'),
              ),
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
  testWidgets('renders the card in a capture boundary + both CTAs (CSV enabled)',
      (tester) async {
    await _openSheet(tester, AsyncValue.data(_receipt()));

    expect(find.byKey(EventKeys.recapShareSheet), findsOneWidget);
    expect(find.byType(RecapShareCard), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(RecapShareCard),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(find.byKey(EventKeys.recapShareConfirmButton), findsOneWidget);
    expect(find.text('Share image'), findsOneWidget);

    // #704 CSV CTA present and enabled on the data path.
    final csv = find.byKey(EventKeys.recapExportCsvButton);
    expect(csv, findsOneWidget);
    expect(find.text('Export ledger (CSV)'), findsOneWidget);
    expect(tester.widget<TextButton>(csv).onPressed, isNotNull);
  });

  testWidgets('CSV CTA is disabled while the receipt is still loading',
      (tester) async {
    await _openSheet(tester, const AsyncValue.loading());

    final csv = find.byKey(EventKeys.recapExportCsvButton);
    expect(csv, findsOneWidget);
    expect(tester.widget<TextButton>(csv).onPressed, isNull);
  });
}

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/widgets/recap_share_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Net-new (#900 PR-3 comp 7): the recap share card is a fixed 360-wide,
/// LIGHT-only brand poster (see the widget's own doc-comment) — an ideal
/// deterministic golden target. This baseline captures the falaj fork
/// underscore (comp 1) replacing the leading brass dot, and the
/// "recorded in Rihla" document-close caption underneath the footer row.
/// It deliberately does NOT exercise the polarity caret (comp 6) — the
/// card's hero is a total-spent readout, never a signed net.
void main() {
  Decimal d(String s) => Decimal.parse(s);

  testWidgets('RecapShareCard — light, document-close ritual footer',
      (tester) async {
    final recap = EventRecap(
      eventId: 'e1',
      eventName: 'Wadi Shab Weekend',
      startDate: DateTime(2026, 3, 12),
      endDate: DateTime(2026, 3, 14),
      participantCount: 5,
      expenseCount: 6,
      totalSpentByCurrency: {'OMR': d('142.350')},
      userPaidByCurrency: const {},
      userShareByCurrency: const {},
      userSettledByCurrency: const {},
      userNetByCurrency: const {},
      biggestExpenseByCurrency: {
        'OMR': (
          expenseId: 'x1',
          amount: d('45.000'),
          description: 'Boat & guide',
          categoryId: 'activities',
          payerId: 'u1',
        ),
      },
      payerTotalsByCurrency: {
        'OMR': [
          (participantId: 'u1', amount: d('88.000')),
          (participantId: 'u2', amount: d('54.350')),
        ],
      },
      categoryTotalsByCurrency: {
        'OMR': [
          (categoryId: 'activities', total: d('60.000')),
          (categoryId: 'food', total: d('50.350')),
          (categoryId: 'stay', total: d('32.000')),
        ],
      },
      participantNetsByCurrency: {
        'OMR': [
          (participantId: 'u1', net: Decimal.zero),
          (participantId: 'u2', net: Decimal.zero),
        ],
      },
      isSettledByCurrency: {'OMR': true},
      isEmpty: false,
    );

    const boundaryKey = ValueKey('recap_share_card_golden_boundary');
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: RecapShareCard(
                recap: recap,
                roster: const {'u1': 'Ahmed', 'u2': 'Sara'},
                eventType: EventType.trip,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byKey(boundaryKey),
      matchesGoldenFile('goldens/recap_share_card_light.png'),
    );
  }, tags: const ['golden']);
}

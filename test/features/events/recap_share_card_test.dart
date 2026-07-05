import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/widgets/recap_share_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/falaj_fork.dart';
import 'package:safar/shared/widgets/r_amount.dart';

Decimal _d(String s) => Decimal.parse(s);

EventRecap _recap({
  String name = 'Wadi Shab Weekend',
  DateTime? start,
  DateTime? end,
  int people = 5,
  int expenses = 6,
  Map<String, Decimal> total = const {},
  Map<String, List<RecapPersonAmount>> payers = const {},
  Map<String, RecapExpenseRef> biggest = const {},
  Map<String, List<RecapCategoryTotal>> categories = const {},
  Map<String, List<RecapNet>> nets = const {},
  Map<String, bool> settled = const {},
}) {
  return EventRecap(
    eventId: 'e1',
    eventName: name,
    startDate: start,
    endDate: end,
    participantCount: people,
    expenseCount: expenses,
    totalSpentByCurrency: total,
    userPaidByCurrency: const {},
    userShareByCurrency: const {},
    userSettledByCurrency: const {},
    userNetByCurrency: const {},
    biggestExpenseByCurrency: biggest,
    payerTotalsByCurrency: payers,
    categoryTotalsByCurrency: categories,
    participantNetsByCurrency: nets,
    isSettledByCurrency: settled,
    isEmpty: expenses == 0,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required EventRecap recap,
  Map<String, String> roster = const {},
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: RecapShareCard(
            recap: recap,
            roster: roster,
            eventType: EventType.trip,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('settled single-currency card renders title, total, status, brand',
      (tester) async {
    final recap = _recap(
      start: DateTime(2026, 3, 12),
      end: DateTime(2026, 3, 14),
      total: {'OMR': _d('142.350')},
      payers: {
        'OMR': [
          (participantId: 'u1', amount: _d('88.000')),
          (participantId: 'u2', amount: _d('54.350')),
        ],
      },
      biggest: {
        'OMR': (
          expenseId: 'x1',
          amount: _d('45.000'),
          description: 'Boat & guide',
          categoryId: 'activities',
          payerId: 'u1',
        ),
      },
      categories: {
        'OMR': [
          (categoryId: 'activities', total: _d('60.000')),
          (categoryId: 'food', total: _d('50.350')),
          (categoryId: 'stay', total: _d('32.000')),
        ],
      },
      nets: {
        'OMR': [
          (participantId: 'u1', net: Decimal.zero),
          (participantId: 'u2', net: Decimal.zero),
        ],
      },
      settled: {'OMR': true},
    );

    await _pumpCard(tester, recap: recap, roster: {'u1': 'Ahmed', 'u2': 'Sara'});

    expect(find.text('Wadi Shab Weekend'), findsOneWidget);
    expect(find.text('All settled'), findsOneWidget);
    expect(find.text('Rihla'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    // The hero total + several breakdowns render via RAmount.
    expect(find.byType(RAmount), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'footer carries the document-close ritual: fork underscore + caption, '
      'no polarity caret', (tester) async {
    final recap = _recap(
      total: {'OMR': _d('142.350')},
      settled: {'OMR': true},
    );

    await _pumpCard(tester, recap: recap);

    expect(find.byType(FalajFork), findsOneWidget);
    expect(find.text('recorded in Rihla'), findsOneWidget);
    // The recap hero is a total-spent readout (never a net) — no owed/owe
    // polarity, so the ▲/▼ caret must never appear on this card (comp 6).
    expect(find.textContaining('▲', findRichText: true), findsNothing);
    expect(find.textContaining('▼', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outstanding card shows the still-to-settle pill', (tester) async {
    final recap = _recap(
      total: {'OMR': _d('318.500')},
      nets: {
        'OMR': [
          (participantId: 'u1', net: _d('176.000')),
          (participantId: 'u2', net: _d('-100.000')),
          (participantId: 'u3', net: _d('-76.000')),
        ],
      },
      settled: {'OMR': false},
    );

    await _pumpCard(tester, recap: recap);

    expect(find.textContaining('still to settle'), findsOneWidget);
    expect(find.text('All settled'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-currency card uses a GCC-first hero + lists the rest',
      (tester) async {
    final recap = _recap(
      name: 'Euro Trip',
      total: {'EUR': _d('1240.00'), 'GBP': _d('320.00')},
      settled: {'EUR': true, 'GBP': true},
    );

    await _pumpCard(tester, recap: recap);

    // EUR sorts before GBP (GCC-first list) → hero EUR, GBP rides in the note.
    expect(find.textContaining('EUR', findRichText: true), findsWidgets);
    expect(find.textContaining('GBP', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undated card falls back to the per-person stat', (tester) async {
    final recap = _recap(
      start: null,
      end: null,
      total: {'OMR': _d('100.000')},
      settled: {'OMR': true},
    );

    await _pumpCard(tester, recap: recap);

    expect(find.text('Per person'), findsOneWidget);
    expect(find.text('Avg / day'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category bar segments render with visible (non-collapsed) height',
      (tester) async {
    // Regression: childless ColoredBox segments under a default (center) Row
    // collapse to height 0 and the bar renders invisible. They must be ~11px.
    final recap = _recap(
      total: {'OMR': _d('100.000')},
      categories: {
        'OMR': [
          (categoryId: 'food', total: _d('60.000')),
          (categoryId: 'transport', total: _d('40.000')),
        ],
      },
      settled: {'OMR': true},
    );

    await _pumpCard(tester, recap: recap);

    final segHeights = tester
        .renderObjectList<RenderBox>(find.byType(ColoredBox))
        .map((r) => r.size.height)
        .toList();
    expect(segHeights.any((h) => h >= 10 && h <= 12), isTrue,
        reason: 'a category bar segment should be ~11px tall, not collapsed');
  });

  testWidgets('category bar folds a single Other even when other is top-ranked',
      (tester) async {
    // 'other' ranks in the top 3 AND there are >3 categories: the remainder
    // (incl. 'other') must fold into exactly ONE "Other" chip, not two.
    final recap = _recap(
      total: {'OMR': _d('150.000')},
      categories: {
        'OMR': [
          (categoryId: 'food', total: _d('50.000')),
          (categoryId: 'other', total: _d('40.000')),
          (categoryId: 'activities', total: _d('30.000')),
          (categoryId: 'transport', total: _d('20.000')),
          (categoryId: 'stay', total: _d('10.000')),
        ],
      },
      settled: {'OMR': true},
    );

    await _pumpCard(tester, recap: recap);

    expect(find.text('Other'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without throwing when a payer is absent from the roster',
      (tester) async {
    // A departed-but-residual member (#249): in the nets/payers, not in roster.
    final recap = _recap(
      total: {'OMR': _d('50.000')},
      payers: {
        'OMR': [(participantId: 'ghost', amount: _d('50.000'))],
      },
      nets: {
        'OMR': [(participantId: 'ghost', net: _d('25.000'))],
      },
      settled: {'OMR': false},
    );

    await _pumpCard(tester, recap: recap, roster: const {});
    expect(tester.takeException(), isNull);
  });
}

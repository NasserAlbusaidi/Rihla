import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/widgets/custom_split_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Hosts the sheet, drives [interactions], and returns the captured result.
Future<SplitResult?> _runSheet(
  WidgetTester tester, {
  required Decimal total,
  required List<SplitParticipant> participants,
  String currency = 'OMR',
  List<SplitItem>? initialItems,
  bool initialItemized = false,
  required Future<void> Function(WidgetTester tester) interactions,
}) async {
  SplitResult? captured;
  bool done = false;
  // A tall window so the itemized sheet (item rows + per-person preview)
  // renders without scrolling — keeps field/tap finders reliable.
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showCustomSplitSheet(
                  context,
                  title: 'Coffee run',
                  total: total,
                  currency: currency,
                  participants: participants,
                  initialItems: initialItems,
                  initialItemized: initialItemized,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interactions(tester);
  await tester.pumpAndSettle();
  expect(done, isTrue, reason: 'sheet was never dismissed');
  return captured;
}

bool _applyEnabled(WidgetTester tester) {
  final apply = tester.widget<ElevatedButton>(
    find.byKey(const Key('split_sheet_apply')),
  );
  return apply.onPressed != null;
}

/// Opens the assign sheet for item [index], taps "Everyone", and closes it.
Future<void> _assignEveryone(WidgetTester tester, int index) async {
  final trigger = find.byKey(Key('itemized_assignees_$index'));
  await tester.ensureVisible(trigger);
  await tester.pumpAndSettle();
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('itemized_everyone')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('itemized_assign_done')));
  await tester.pumpAndSettle();
}

/// Opens the assign sheet for item [index], ticks the participant with [id]
/// (matched by stable tile key, not display name — names also appear in the
/// preview list behind the sheet), and closes it.
Future<void> _assignOne(
  WidgetTester tester,
  int index,
  String id,
) async {
  final trigger = find.byKey(Key('itemized_assignees_$index'));
  await tester.ensureVisible(trigger);
  await tester.pumpAndSettle();
  await tester.tap(trigger);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('itemized_assign_tile_$id')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('itemized_assign_done')));
  await tester.pumpAndSettle();
}

Future<void> _addItem(WidgetTester tester) async {
  final add = find.byKey(const Key('itemized_add_item'));
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
}

void main() {
  // 4 people, alphabetical ids matching the coffee-run scenario.
  const four = [
    SplitParticipant(id: 'h', name: 'Hessa'),
    SplitParticipant(id: 'k', name: 'Khalid'),
    SplitParticipant(id: 'n', name: 'Nasser'),
    SplitParticipant(id: 's', name: 'Sara'),
  ];

  group('CustomSplitSheet — itemized tab', () {
    testWidgets('Itemized chip selectable; empty body shows one draft + add',
        (tester) async {
      await _runSheet(
        tester,
        total: Decimal.parse('6.100'),
        participants: four,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          // One empty draft row + the add-item affordance.
          expect(find.byKey(const Key('itemized_label_0')), findsOneWidget);
          expect(find.byKey(const Key('itemized_amount_0')), findsOneWidget);
          expect(find.byKey(const Key('itemized_add_item')), findsOneWidget);
          // Cancel out — we only assert structure here.
          await t.tap(find.text('Cancel'));
        },
      );
    });
  });

  group('CustomSplitSheet — itemized reconcile gate', () {
    testWidgets('Apply disabled until items sum to total, enabled when equal',
        (tester) async {
      await _runSheet(
        tester,
        total: Decimal.parse('6.100'),
        participants: four,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();

          // One item, under total → Apply disabled.
          await t.enterText(
            find.byKey(const Key('itemized_label_0')),
            'Pastries',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_0')),
            '1.200',
          );
          await _assignEveryone(t, 0);
          expect(_applyEnabled(t), isFalse);

          // Add a second item bringing the sum to exactly 6.100.
          await _addItem(t);
          await t.enterText(
            find.byKey(const Key('itemized_label_1')),
            'Drinks',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_1')),
            '4.900',
          );
          await _assignEveryone(t, 1);
          expect(_applyEnabled(t), isTrue);

          await t.tap(find.text('Cancel'));
        },
      );
    });
  });

  group('CustomSplitSheet — itemized apply (coffee run, OMR)', () {
    testWidgets('Everyone + per-drink items return the allocator distribution',
        (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('6.100'),
        participants: four,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();

          // Pastries 1.200 → Everyone (0.300 each).
          await t.enterText(
            find.byKey(const Key('itemized_label_0')),
            'Pastries',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_0')),
            '1.200',
          );
          await _assignEveryone(t, 0);

          // Americano 1.600 → Nasser.
          await _addItem(t);
          await t.enterText(
            find.byKey(const Key('itemized_label_1')),
            'Americano',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_1')),
            '1.600',
          );
          await _assignOne(t, 1, 'n');

          // Espresso 1.200 → Sara.
          await _addItem(t);
          await t.enterText(
            find.byKey(const Key('itemized_label_2')),
            'Espresso',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_2')),
            '1.200',
          );
          await _assignOne(t, 2, 's');

          // Latte 2.100 → Khalid.
          await _addItem(t);
          await t.enterText(
            find.byKey(const Key('itemized_label_3')),
            'Latte',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_3')),
            '2.100',
          );
          await _assignOne(t, 3, 'k');

          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.items, isNotNull);
      expect(result.items!.length, 4);

      final expected = BalanceCalculator.allocateItemizedDistribution(
        items: result.items!,
        currency: 'OMR',
      );
      expect(result.distribution, expected);
      // Pin the exact figures from the scenario.
      expect(result.distribution!['n'], Decimal.parse('1.900'));
      expect(result.distribution!['s'], Decimal.parse('1.500'));
      expect(result.distribution!['k'], Decimal.parse('2.400'));
      expect(result.distribution!['h'], Decimal.parse('0.300'));
    });
  });

  group('CustomSplitSheet — itemized reopen', () {
    testWidgets('initialItems + initialItemized seed the draft rows',
        (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('6.100'),
        participants: four,
        initialItemized: true,
        initialItems: const [
          SplitItem(
            label: 'Pastries',
            amountFils: 1200,
            participantIds: ['h', 'k', 'n', 's'],
          ),
          SplitItem(label: 'Americano', amountFils: 1600, participantIds: ['n']),
          SplitItem(label: 'Espresso', amountFils: 1200, participantIds: ['s']),
          SplitItem(label: 'Latte', amountFils: 2100, participantIds: ['k']),
        ],
        interactions: (t) async {
          // The four seeded labels render in their fields.
          expect(
            find.widgetWithText(TextField, 'Pastries'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(TextField, 'Latte'),
            findsOneWidget,
          );
          expect(find.byKey(const Key('itemized_label_3')), findsOneWidget);
          // Reconciled out of the box → Apply enabled; apply round-trips.
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.items!.length, 4);
      expect(result.distribution!['h'], Decimal.parse('0.300'));
    });
  });

  group('CustomSplitSheet — itemized JPY (×1) + zero-assignee guard', () {
    testWidgets('yen items have no ×100 drift; reconcile at unit scale',
        (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.fromInt(900),
        currency: 'JPY',
        participants: const [
          SplitParticipant(id: 'a', name: 'Aki'),
          SplitParticipant(id: 'b', name: 'Bo'),
        ],
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('itemized_label_0')),
            'Ramen',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_0')),
            '900',
          );
          await _assignEveryone(t, 0);
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.items!.single.amountFils, 900); // ×1, not ×100
      expect(result.distribution!['a'], Decimal.fromInt(450));
      expect(result.distribution!['b'], Decimal.fromInt(450));
    });

    testWidgets('a zero-assignee draft blocks Apply (and never throws)',
        (tester) async {
      await _runSheet(
        tester,
        total: Decimal.parse('1.200'),
        participants: four,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          // A fully-priced row that reconciles to total, but NO assignee.
          await t.enterText(
            find.byKey(const Key('itemized_label_0')),
            'Pastries',
          );
          await t.enterText(
            find.byKey(const Key('itemized_amount_0')),
            '1.200',
          );
          await t.pump();
          // Sum matches total, but the missing assignee must block Apply.
          expect(_applyEnabled(t), isFalse);
          await t.tap(find.text('Cancel'));
        },
      );
    });
  });
}

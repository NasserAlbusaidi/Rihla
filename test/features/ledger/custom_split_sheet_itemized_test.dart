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
  List<SplitAdjustment>? initialAdjustments,
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
                  initialAdjustments: initialAdjustments,
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

/// Opens the add-adjustment sheet, picks [type], enters [amount], optionally
/// picks [alloc] ('equal'/'proportional'; ignored for a discount), and closes.
Future<void> _addAdjustment(
  WidgetTester tester, {
  required String type,
  required String amount,
  String? alloc,
}) async {
  final add = find.byKey(const Key('itemized_add_adjustment'));
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('adjustment_type_$type')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('adjustment_amount')), amount);
  await tester.pump();
  if (alloc != null && type != 'discount') {
    await tester.tap(find.byKey(Key('adjustment_alloc_$alloc')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('adjustment_done')));
  await tester.pumpAndSettle();
}

/// Opens the add-adjustment sheet, picks discount, enters [amount], selects the
/// 'assigned' mode, ticks each id in [memberIds], and closes (#605).
Future<void> _addAssignedDiscount(
  WidgetTester tester, {
  required String amount,
  required List<String> memberIds,
}) async {
  final add = find.byKey(const Key('itemized_add_adjustment'));
  await tester.ensureVisible(add);
  await tester.pumpAndSettle();
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('adjustment_type_discount')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('adjustment_amount')), amount);
  await tester.pump();
  await tester.tap(find.byKey(const Key('adjustment_alloc_assigned')));
  await tester.pumpAndSettle();
  for (final id in memberIds) {
    await tester.tap(find.byKey(Key('adjustment_assign_tile_$id')));
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('adjustment_done')));
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

  group('CustomSplitSheet — bill-level adjustments (#605)', () {
    const two = [
      SplitParticipant(id: 'a', name: 'Aki'),
      SplitParticipant(id: 'b', name: 'Bo'),
    ];

    testWidgets('adding a service adjustment reconciles + folds into the result',
        (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('2.000'),
        participants: two,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('itemized_label_0')), 'Food');
          await t.enterText(find.byKey(const Key('itemized_amount_0')), '1.000');
          await _assignEveryone(t, 0);
          // Items alone (1.000) under the 2.000 bill → Apply disabled.
          expect(_applyEnabled(t), isFalse);

          await _addAdjustment(t, type: 'service', amount: '1.000', alloc: 'equal');
          // Items 1.000 + service 1.000 == 2.000 → reconciled.
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.adjustments, isNotNull);
      expect(result.adjustments!.length, 1);
      expect(result.adjustments!.single.type, 'service');
      expect(result.adjustments!.single.amountFils, 1000);
      expect(result.adjustments!.single.allocation, 'equal');
      // Each: 0.500 item share + 0.500 service share = 1.000.
      expect(result.distribution!['a'], Decimal.parse('1.000'));
      expect(result.distribution!['b'], Decimal.parse('1.000'));
    });

    testWidgets('a discount larger than items does not crash the preview',
        (tester) async {
      await _runSheet(
        tester,
        total: Decimal.parse('2.000'),
        participants: two,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('itemized_label_0')), 'Food');
          await t.enterText(find.byKey(const Key('itemized_amount_0')), '1.000');
          await _assignEveryone(t, 0);
          // Discount 5.000 ≫ items 1.000 → would-be remaining < 0; must not throw.
          await _addAdjustment(t, type: 'discount', amount: '5.000');
          expect(tester.takeException(), isNull);
          expect(_applyEnabled(t), isFalse); // nowhere near reconciled
          await t.tap(find.text('Cancel'));
        },
      );
    });

    testWidgets('an adjustment with no items still renders the whole-table spread',
        (tester) async {
      await _runSheet(
        tester,
        total: Decimal.parse('1.000'),
        participants: two,
        interactions: (t) async {
          await t.tap(find.text('Itemized'));
          await t.pumpAndSettle();
          // No item entered (default empty draft). Add 1.000 service equally.
          await _addAdjustment(t, type: 'service', amount: '1.000', alloc: 'equal');
          // Each of the 2 owes 0.500 in the live preview despite zero items.
          expect(
            find.textContaining('0.500', findRichText: true),
            findsWidgets,
          );
          await t.tap(find.text('Cancel'));
        },
      );
    });

    testWidgets('initialAdjustments seed an editable adjustment row on reopen',
        (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('2.000'),
        participants: two,
        initialItemized: true,
        initialItems: const [
          SplitItem(label: 'Food', amountFils: 1000, participantIds: ['a', 'b']),
        ],
        initialAdjustments: const [
          SplitAdjustment(type: 'service', amountFils: 1000, allocation: 'equal'),
        ],
        interactions: (t) async {
          // The seeded adjustment row is present and the bill reconciles.
          expect(find.byKey(const Key('itemized_adjustment_0')), findsOneWidget);
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result!.adjustments!.single.type, 'service');
      expect(result.distribution!['a'], Decimal.parse('1.000'));
      expect(result.distribution!['b'], Decimal.parse('1.000'));
    });

    testWidgets(
      '#1041 §4: adjustment-type chip hit region is >=44dp tall',
      (tester) async {
        await _runSheet(
          tester,
          total: Decimal.parse('2.000'),
          participants: two,
          interactions: (t) async {
            await t.tap(find.text('Itemized'));
            await t.pumpAndSettle();
            final add = find.byKey(const Key('itemized_add_adjustment'));
            await t.ensureVisible(add);
            await t.pumpAndSettle();
            await t.tap(add);
            await t.pumpAndSettle();

            final size = t.getSize(
              find.byKey(const Key('adjustment_type_service')),
            );
            expect(size.height, greaterThanOrEqualTo(44));

            // Select a type + valid amount before closing (mirrors
            // _addAdjustment) — closing with a blank amount disposes the
            // controller mid-animation, a pre-existing app quirk unrelated
            // to tap targets and out of scope here.
            await t.tap(find.byKey(const Key('adjustment_type_service')));
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('adjustment_amount')),
              '1.000',
            );
            await t.pump();
            await t.tap(find.byKey(const Key('adjustment_done')));
            await t.pumpAndSettle();
            await t.tap(find.text('Cancel'));
          },
        );
      },
    );

    testWidgets(
      'assigned discount folds onto its subset only + result carries the subset',
      (tester) async {
        final result = await _runSheet(
          tester,
          total: Decimal.parse('1.600'),
          participants: two,
          interactions: (t) async {
            await t.tap(find.text('Itemized'));
            await t.pumpAndSettle();
            // a's item 1.000 → a; b's item 1.000 → b.
            await t.enterText(find.byKey(const Key('itemized_label_0')), 'A food');
            await t.enterText(find.byKey(const Key('itemized_amount_0')), '1.000');
            await _assignOne(t, 0, 'a');
            await _addItem(t);
            await t.enterText(find.byKey(const Key('itemized_label_1')), 'B food');
            await t.enterText(find.byKey(const Key('itemized_amount_1')), '1.000');
            await _assignOne(t, 1, 'b');
            // 0.400 discount borne by {a} only → bill 2.000 − 0.400 = 1.600.
            await _addAssignedDiscount(t, amount: '0.400', memberIds: ['a']);
            expect(t.takeException(), isNull);
            expect(_applyEnabled(t), isTrue);
            await t.tap(find.byKey(const Key('split_sheet_apply')));
          },
        );
        expect(result, isNotNull);
        expect(result!.adjustments!.single.type, 'discount');
        expect(result.adjustments!.single.allocation, 'assigned');
        expect(result.adjustments!.single.participantIds, ['a']);
        // a bore the whole 0.400; b untouched.
        expect(result.distribution!['a'], Decimal.parse('0.600'));
        expect(result.distribution!['b'], Decimal.parse('1.000'));
        // The folded distribution matches the allocator exactly.
        final expected = BalanceCalculator.allocateItemizedDistribution(
          items: result.items!,
          currency: 'OMR',
          adjustments: result.adjustments!,
          participantIds: const ['a', 'b'],
        );
        expect(result.distribution, expected);
      },
    );

    testWidgets(
      'assigned discount over its subset: no crash, Apply disabled, inline error, '
      'preview not zeroed',
      (tester) async {
        await _runSheet(
          tester,
          total: Decimal.parse('2.000'),
          participants: two,
          interactions: (t) async {
            await t.tap(find.text('Itemized'));
            await t.pumpAndSettle();
            await t.enterText(find.byKey(const Key('itemized_label_0')), 'A food');
            await t.enterText(find.byKey(const Key('itemized_amount_0')), '1.000');
            await _assignOne(t, 0, 'a');
            await _addItem(t);
            await t.enterText(find.byKey(const Key('itemized_label_1')), 'B food');
            await t.enterText(find.byKey(const Key('itemized_amount_1')), '1.000');
            await _assignOne(t, 1, 'b');
            // 1.500 discount on {a}, whose subset owes only 1.000 → overshoot.
            await _addAssignedDiscount(t, amount: '1.500', memberIds: ['a']);
            expect(t.takeException(), isNull);
            // Inline error shown, Apply disabled.
            expect(
              find.byKey(const Key('assigned_discount_error')),
              findsOneWidget,
            );
            expect(_applyEnabled(t), isFalse);
            // Preview is NOT zeroed — the pre-assigned fold (1.000 each) renders.
            expect(
              find.textContaining('1.000', findRichText: true),
              findsWidgets,
            );
            await t.tap(find.text('Cancel'));
          },
        );
      },
    );

    testWidgets(
      'reopen seeds an assigned discount subset + caption; apply retains it',
      (tester) async {
        final result = await _runSheet(
          tester,
          total: Decimal.parse('1.600'),
          participants: two,
          initialItemized: true,
          initialItems: const [
            SplitItem(label: 'A food', amountFils: 1000, participantIds: ['a']),
            SplitItem(label: 'B food', amountFils: 1000, participantIds: ['b']),
          ],
          initialAdjustments: const [
            SplitAdjustment(
              type: 'discount',
              amountFils: 400,
              allocation: 'assigned',
              participantIds: ['a'],
            ),
          ],
          interactions: (t) async {
            expect(find.byKey(const Key('itemized_adjustment_0')), findsOneWidget);
            // The collapsed row shows the "borne by" caption naming Aki.
            expect(find.textContaining('Aki'), findsWidgets);
            expect(_applyEnabled(t), isTrue);
            await t.tap(find.byKey(const Key('split_sheet_apply')));
          },
        );
        expect(result!.adjustments!.single.allocation, 'assigned');
        expect(result.adjustments!.single.participantIds, ['a']);
        expect(result.distribution!['a'], Decimal.parse('0.600'));
        expect(result.distribution!['b'], Decimal.parse('1.000'));
      },
    );

    testWidgets(
      'assigned with no members selected degrades to proportional (no throw)',
      (tester) async {
        final result = await _runSheet(
          tester,
          total: Decimal.parse('1.600'),
          participants: two,
          interactions: (t) async {
            await t.tap(find.text('Itemized'));
            await t.pumpAndSettle();
            await t.enterText(find.byKey(const Key('itemized_label_0')), 'A food');
            await t.enterText(find.byKey(const Key('itemized_amount_0')), '1.000');
            await _assignOne(t, 0, 'a');
            await _addItem(t);
            await t.enterText(find.byKey(const Key('itemized_label_1')), 'B food');
            await t.enterText(find.byKey(const Key('itemized_amount_1')), '1.000');
            await _assignOne(t, 1, 'b');
            // Pick 'assigned' but select NO members → toAdjustment degrades it.
            final add = find.byKey(const Key('itemized_add_adjustment'));
            await t.ensureVisible(add);
            await t.pumpAndSettle();
            await t.tap(add);
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('adjustment_type_discount')));
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('adjustment_amount')),
              '0.400',
            );
            await t.pump();
            await t.tap(find.byKey(const Key('adjustment_alloc_assigned')));
            await t.pumpAndSettle();
            await t.tap(find.byKey(const Key('adjustment_done')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            expect(_applyEnabled(t), isTrue);
            await t.tap(find.byKey(const Key('split_sheet_apply')));
          },
        );
        // Empty subset ⇒ normalized to pooled proportional; no participantIds.
        expect(result!.adjustments!.single.allocation, 'proportional');
        expect(result.adjustments!.single.participantIds, isNull);
      },
    );

    testWidgets(
      '#1049: closing the add-adjustment sheet with a blank amount does not '
      'dispose the controller mid-animation',
      (tester) async {
        await _runSheet(
          tester,
          total: Decimal.parse('2.000'),
          participants: two,
          interactions: (t) async {
            await t.tap(find.text('Itemized'));
            await t.pumpAndSettle();
            final add = find.byKey(const Key('itemized_add_adjustment'));
            await t.ensureVisible(add);
            await t.pumpAndSettle();
            await t.tap(add);
            await t.pumpAndSettle();
            // Close the editor with a BLANK amount — the #1049 path. Pre-fix this
            // threw "A TextEditingController was used after being disposed" as the
            // sheet rebuilt during its exit transition.
            await t.tap(find.byKey(const Key('adjustment_done')));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            // The blank adjustment was pruned — no row left behind.
            expect(find.byKey(const Key('itemized_adjustment_0')), findsNothing);
            // Close the parent sheet so _runSheet completes.
            await t.tap(find.text('Cancel'));
          },
        );
      },
    );
  });
}

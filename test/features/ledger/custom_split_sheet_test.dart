import 'dart:ui' show Tristate;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/custom_split_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _SheetHarness {
  const _SheetHarness({required this.result, required this.done});

  final SplitResult? Function() result;
  final bool Function() done;
}

Future<_SheetHarness> _openSheet(
  WidgetTester tester, {
  required Decimal total,
  required List<SplitParticipant> participants,
  String currency = 'OMR',
  SplitMode initialMode = SplitMode.equally,
  Map<String, Decimal>? initialDistribution,
}) async {
  SplitResult? captured;
  var done = false;
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
                  title: 'Dinner',
                  total: total,
                  currency: currency,
                  participants: participants,
                  initialMode: initialMode,
                  initialDistribution: initialDistribution,
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
  return _SheetHarness(result: () => captured, done: () => done);
}

/// Hosts the sheet, drives the supplied [interactions], and returns the
/// captured [SplitResult].
Future<SplitResult?> _runSheet(
  WidgetTester tester, {
  required Decimal total,
  required List<SplitParticipant> participants,
  String currency = 'OMR',
  SplitMode initialMode = SplitMode.equally,
  Map<String, Decimal>? initialDistribution,
  required Future<void> Function(WidgetTester tester) interactions,
}) async {
  final harness = await _openSheet(
    tester,
    total: total,
    participants: participants,
    currency: currency,
    initialMode: initialMode,
    initialDistribution: initialDistribution,
  );
  await interactions(tester);
  // Allow the future returned by showModalBottomSheet to resolve.
  await tester.pumpAndSettle();
  expect(harness.done(), isTrue, reason: 'sheet was never dismissed');
  return harness.result();
}

bool _applyEnabled(WidgetTester tester) {
  final apply = tester.widget<ElevatedButton>(
    find.byKey(const Key('split_sheet_apply')),
  );
  return apply.onPressed != null;
}

String _fieldText(WidgetTester tester, Key key) {
  final field = tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
  );
  return field.controller!.text;
}

String _exactText(WidgetTester tester, String id) =>
    _fieldText(tester, Key('split_exact_$id'));

String _percentText(WidgetTester tester, String id) =>
    _fieldText(tester, Key('split_percent_$id'));

Decimal _sumTexts(Iterable<String> texts) => texts.fold(
  Decimal.zero,
  (sum, text) => sum + (Decimal.tryParse(text) ?? Decimal.zero),
);

Decimal _distributionSum(Map<String, Decimal> distribution) =>
    distribution.values.fold(Decimal.zero, (sum, value) => sum + value);

void _expectExactTexts(WidgetTester tester, Map<String, String> expected) {
  for (final entry in expected.entries) {
    expect(_exactText(tester, entry.key), entry.value);
  }
}

void _expectPercentTexts(WidgetTester tester, Map<String, String> expected) {
  for (final entry in expected.entries) {
    expect(_percentText(tester, entry.key), entry.value);
  }
}

void main() {
  const participants = [
    SplitParticipant(id: 'a', name: 'Alex'),
    SplitParticipant(id: 'b', name: 'Bo'),
    SplitParticipant(id: 'c', name: 'Cam'),
  ];

  group('CustomSplitSheet — equally', () {
    testWidgets('#1067 mode tabs expose button role and selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CustomSplitSheet)),
      );
      final equally = tester.getSemantics(
        find.bySemanticsLabel(l10n.splitModeEqually),
      );
      final shares = tester.getSemantics(
        find.bySemanticsLabel(l10n.splitModeShares),
      );
      expect(equally.flagsCollection.isButton, isTrue);
      expect(equally.flagsCollection.isSelected, Tristate.isTrue);
      expect(shares.flagsCollection.isButton, isTrue);
      expect(shares.flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('#1067 mode tab hit region is >=44dp around a compact pill', (
      tester,
    ) async {
      await _openSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(CustomSplitSheet)),
      );
      final label = find.text(l10n.splitModeEqually);
      final hitRegion = find
          .ancestor(of: label, matching: find.byType(GestureDetector))
          .first;
      final paintedPill = find
          .ancestor(of: label, matching: find.byType(AnimatedContainer))
          .first;
      final compactStrip = find.byKey(const Key('split_mode_segment'));
      final paintedTrack = find.byKey(const Key('split_mode_segment_track'));

      expect(tester.getSize(hitRegion).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(paintedPill).height, lessThan(44));
      expect(tester.getSize(compactStrip).height, 44);
      expect(tester.getSize(paintedTrack).height, lessThan(44));
    });

    testWidgets('Apply returns (equally, null) by default', (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.equally);
      expect(result.distribution, isNull);
    });

    testWidgets('Cancel returns null', (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.text('Cancel'));
        },
      );
      expect(result, isNull);
    });
  });

  group('CustomSplitSheet — shares', () {
    testWidgets('stepper edits return weighted distribution', (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          // Switch to shares mode.
          await t.tap(find.text('Shares'));
          await t.pumpAndSettle();
          // Default is 1 share each. Bump Alex to 3 (two +).
          final plusButtons = find.byIcon(Icons.add);
          await t.tap(plusButtons.at(0));
          await t.pump();
          await t.tap(plusButtons.at(0));
          await t.pump();
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.shares);
      expect(result.distribution, isNotNull);
      expect(result.distribution!['a'], Decimal.fromInt(3));
      expect(result.distribution!['b'], Decimal.fromInt(1));
      expect(result.distribution!['c'], Decimal.fromInt(1));
    });

    testWidgets('Apply disabled when every share is zero', (tester) async {
      bool tapped = false;
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
                    await showCustomSplitSheet(
                      context,
                      title: 'Dinner',
                      total: Decimal.parse('30.000'),
                      currency: 'OMR',
                      participants: participants,
                    );
                    tapped = true;
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
      await tester.tap(find.text('Shares'));
      await tester.pumpAndSettle();
      // Drive each share down to 0.
      final minusButtons = find.byIcon(Icons.remove);
      for (int i = 0; i < participants.length; i++) {
        await tester.tap(minusButtons.at(i));
        await tester.pump();
      }
      final apply = tester.widget<ElevatedButton>(
        find.byKey(const Key('split_sheet_apply')),
      );
      expect(apply.onPressed, isNull);
      expect(tapped, isFalse);
    });
  });

  group('CustomSplitSheet — exact', () {
    testWidgets('Apply disables when seeded exact sum is edited off total', (
      tester,
    ) async {
      await _openSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
      );
      await tester.tap(find.text('Exact amounts'));
      await tester.pumpAndSettle();

      _expectExactTexts(tester, const {'a': '10', 'b': '10', 'c': '10'});
      expect(_applyEnabled(tester), isTrue);

      await tester.enterText(find.byKey(const Key('split_exact_a')), '11');
      await tester.pump();
      expect(_applyEnabled(tester), isFalse);
    });

    testWidgets('valid totals return per-participant amounts', (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.text('Exact amounts'));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('split_exact_a')), '15');
          await t.pump();
          await t.enterText(find.byKey(const Key('split_exact_b')), '10');
          await t.pump();
          await t.enterText(find.byKey(const Key('split_exact_c')), '5');
          await t.pump();
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.distribution!['a'], Decimal.fromInt(15));
      expect(result.distribution!['b'], Decimal.fromInt(10));
      expect(result.distribution!['c'], Decimal.fromInt(5));
    });

    testWidgets('in-sheet switch seeds exact and Apply works immediately', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.text('Exact amounts'));
          await t.pumpAndSettle();

          _expectExactTexts(t, const {'a': '10', 'b': '10', 'c': '10'});
          expect(
            _sumTexts(participants.map((p) => _exactText(t, p.id))),
            Decimal.parse('30'),
          );
          expect(_applyEnabled(t), isTrue);

          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.distribution!['a'], Decimal.fromInt(10));
      expect(result.distribution!['b'], Decimal.fromInt(10));
      expect(result.distribution!['c'], Decimal.fromInt(10));
    });

    testWidgets('card-entry exact seeds rows and Apply works immediately', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.exact,
        interactions: (t) async {
          _expectExactTexts(t, const {'a': '10', 'b': '10', 'c': '10'});
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.distribution!['a'], Decimal.fromInt(10));
      expect(result.distribution!['b'], Decimal.fromInt(10));
      expect(result.distribution!['c'], Decimal.fromInt(10));
    });
  });

  group('CustomSplitSheet — percent', () {
    testWidgets('Apply disables when seeded percent sum is edited off 100', (
      tester,
    ) async {
      await _openSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
      );
      await tester.tap(find.text('Percent'));
      await tester.pumpAndSettle();

      _expectPercentTexts(tester, const {
        'a': '33.333',
        'b': '33.333',
        'c': '33.334',
      });
      expect(_applyEnabled(tester), isTrue);

      await tester.enterText(find.byKey(const Key('split_percent_a')), '30');
      await tester.pump();
      expect(_applyEnabled(tester), isFalse);
    });

    testWidgets('returns percent distribution', (tester) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.text('Percent'));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('split_percent_a')), '50');
          await t.pump();
          await t.enterText(find.byKey(const Key('split_percent_b')), '30');
          await t.pump();
          await t.enterText(find.byKey(const Key('split_percent_c')), '20');
          await t.pump();
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.percent);
      expect(result.distribution!['a'], Decimal.fromInt(50));
      expect(result.distribution!['b'], Decimal.fromInt(30));
      expect(result.distribution!['c'], Decimal.fromInt(20));
    });

    testWidgets('in-sheet switch seeds percent and Apply works immediately', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        interactions: (t) async {
          await t.tap(find.text('Percent'));
          await t.pumpAndSettle();

          _expectPercentTexts(t, const {
            'a': '33.333',
            'b': '33.333',
            'c': '33.334',
          });
          expect(
            _sumTexts(participants.map((p) => _percentText(t, p.id))),
            Decimal.fromInt(100),
          );
          expect(_applyEnabled(t), isTrue);

          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.percent);
      expect(result.distribution!['a'], Decimal.parse('33.333'));
      expect(result.distribution!['b'], Decimal.parse('33.333'));
      expect(result.distribution!['c'], Decimal.parse('33.334'));
    });

    testWidgets('card-entry percent seeds rows and Apply works immediately', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.percent,
        interactions: (t) async {
          _expectPercentTexts(t, const {
            'a': '33.333',
            'b': '33.333',
            'c': '33.334',
          });
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.percent);
      expect(result.distribution!['a'], Decimal.parse('33.333'));
      expect(result.distribution!['b'], Decimal.parse('33.333'));
      expect(result.distribution!['c'], Decimal.parse('33.334'));
    });
  });

  group('CustomSplitSheet — shadow members (#278)', () {
    testWidgets('a shadow participant shows the not-joined-yet marker', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCustomSplitSheet(
                    context,
                    title: 'Dinner',
                    total: Decimal.parse('30.000'),
                    currency: 'OMR',
                    participants: const [
                      SplitParticipant(id: 'a', name: 'Alex'),
                      SplitParticipant(id: 'b', name: 'Bo', isShadow: true),
                    ],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The shadow member is marked; the real member is not.
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Bo'), findsOneWidget);
      expect(find.text("Hasn't joined yet"), findsOneWidget);
    });
  });

  group('CustomSplitSheet — initial values', () {
    testWidgets('opens in the requested mode with prefilled shares', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.shares,
        initialDistribution: {
          'a': Decimal.fromInt(2),
          'b': Decimal.fromInt(1),
          'c': Decimal.fromInt(1),
        },
        interactions: (t) async {
          // Apply without touching anything; values should round-trip.
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );
      expect(result, isNotNull);
      expect(result!.mode, SplitMode.shares);
      expect(result.distribution!['a'], Decimal.fromInt(2));
      expect(result.distribution!['b'], Decimal.fromInt(1));
      expect(result.distribution!['c'], Decimal.fromInt(1));
    });

    testWidgets('existing exact distribution hydrates without re-seeding', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.exact,
        initialDistribution: {
          'a': Decimal.fromInt(5),
          'b': Decimal.fromInt(10),
          'c': Decimal.fromInt(15),
        },
        interactions: (t) async {
          _expectExactTexts(t, const {'a': '5', 'b': '10', 'c': '15'});
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.exact);
      expect(result.distribution!['a'], Decimal.fromInt(5));
      expect(result.distribution!['b'], Decimal.fromInt(10));
      expect(result.distribution!['c'], Decimal.fromInt(15));
    });

    testWidgets('existing percent distribution hydrates without re-seeding', (
      tester,
    ) async {
      final result = await _runSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.percent,
        initialDistribution: {
          'a': Decimal.fromInt(50),
          'b': Decimal.fromInt(30),
          'c': Decimal.fromInt(20),
        },
        interactions: (t) async {
          _expectPercentTexts(t, const {'a': '50', 'b': '30', 'c': '20'});
          expect(_applyEnabled(t), isTrue);
          await t.tap(find.byKey(const Key('split_sheet_apply')));
        },
      );

      expect(result, isNotNull);
      expect(result!.mode, SplitMode.percent);
      expect(result.distribution!['a'], Decimal.fromInt(50));
      expect(result.distribution!['b'], Decimal.fromInt(30));
      expect(result.distribution!['c'], Decimal.fromInt(20));
    });

    testWidgets('switching exact to percent and back preserves exact edits', (
      tester,
    ) async {
      await _openSheet(
        tester,
        total: Decimal.parse('30.000'),
        participants: participants,
        initialMode: SplitMode.exact,
      );

      _expectExactTexts(tester, const {'a': '10', 'b': '10', 'c': '10'});
      await tester.enterText(find.byKey(const Key('split_exact_a')), '12');
      await tester.pump();

      await tester.tap(find.text('Percent'));
      await tester.pumpAndSettle();
      _expectPercentTexts(tester, const {
        'a': '33.333',
        'b': '33.333',
        'c': '33.334',
      });

      await tester.tap(find.text('Exact amounts'));
      await tester.pumpAndSettle();
      _expectExactTexts(tester, const {'a': '12', 'b': '10', 'c': '10'});
    });
  });

  group('CustomSplitSheet — exact currency seeding', () {
    final cases =
        <({String currency, Decimal total, Map<String, String> expected})>[
          (
            currency: 'OMR',
            total: Decimal.parse('10.000'),
            expected: const {'a': '3.333', 'b': '3.333', 'c': '3.334'},
          ),
          (
            currency: 'USD',
            total: Decimal.parse('10.00'),
            expected: const {'a': '3.33', 'b': '3.33', 'c': '3.34'},
          ),
          (
            currency: 'JPY',
            total: Decimal.parse('10'),
            expected: const {'a': '3', 'b': '3', 'c': '4'},
          ),
        ];

    for (final testCase in cases) {
      testWidgets(
        '${testCase.currency} exact seed sums to total with remainder last',
        (tester) async {
          final result = await _runSheet(
            tester,
            total: testCase.total,
            currency: testCase.currency,
            participants: participants,
            initialMode: SplitMode.exact,
            interactions: (t) async {
              _expectExactTexts(t, testCase.expected);
              expect(_applyEnabled(t), isTrue);
              await t.tap(find.byKey(const Key('split_sheet_apply')));
            },
          );

          expect(result, isNotNull);
          expect(result!.mode, SplitMode.exact);
          expect(_distributionSum(result.distribution!), testCase.total);
          for (final entry in testCase.expected.entries) {
            expect(result.distribution![entry.key], Decimal.parse(entry.value));
          }
        },
      );
    }
  });
}

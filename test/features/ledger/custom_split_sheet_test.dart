import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/custom_split_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Hosts the sheet, drives the supplied [interactions], and returns the
/// captured [SplitResult].
Future<SplitResult?> _runSheet(
  WidgetTester tester, {
  required Decimal total,
  required List<SplitParticipant> participants,
  SplitMode initialMode = SplitMode.equally,
  Map<String, Decimal>? initialDistribution,
  required Future<void> Function(WidgetTester tester) interactions,
}) async {
  SplitResult? captured;
  bool done = false;
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
                  currency: 'OMR',
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
  await interactions(tester);
  // Allow the future returned by showModalBottomSheet to resolve.
  await tester.pumpAndSettle();
  expect(done, isTrue, reason: 'sheet was never dismissed');
  return captured;
}

void main() {
  const participants = [
    SplitParticipant(id: 'a', name: 'Alex'),
    SplitParticipant(id: 'b', name: 'Bo'),
    SplitParticipant(id: 'c', name: 'Cam'),
  ];

  group('CustomSplitSheet — equally', () {
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
    testWidgets('Apply disabled until sum equals total', (tester) async {
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
                    participants: participants,
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
      await tester.tap(find.text('Exact amounts'));
      await tester.pumpAndSettle();

      // Fill only one row — sum != total — Apply should be disabled.
      await tester.enterText(find.byKey(const Key('split_exact_a')), '10');
      await tester.pump();
      var apply = tester.widget<ElevatedButton>(
        find.byKey(const Key('split_sheet_apply')),
      );
      expect(apply.onPressed, isNull);

      // Fill the rest so sum == 30 — Apply should enable.
      await tester.enterText(find.byKey(const Key('split_exact_b')), '12');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('split_exact_c')), '8');
      await tester.pump();
      apply = tester.widget<ElevatedButton>(
        find.byKey(const Key('split_sheet_apply')),
      );
      expect(apply.onPressed, isNotNull);
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
  });

  group('CustomSplitSheet — percent', () {
    testWidgets('Apply disabled until sum is 100', (tester) async {
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
                    participants: participants,
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
      await tester.tap(find.text('Percent'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('split_percent_a')), '30');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('split_percent_b')), '30');
      await tester.pump();
      // Sum = 60 — Apply disabled.
      var apply = tester.widget<ElevatedButton>(
        find.byKey(const Key('split_sheet_apply')),
      );
      expect(apply.onPressed, isNull);

      await tester.enterText(find.byKey(const Key('split_percent_c')), '40');
      await tester.pump();
      apply = tester.widget<ElevatedButton>(
        find.byKey(const Key('split_sheet_apply')),
      );
      expect(apply.onPressed, isNotNull);
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
  });
}

import 'dart:ui' show Tristate;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/widgets/split_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #485 — the unified Split card: one payer control (no second dropdown),
/// plain-language scope segment, inline mode segment, real per-person figures,
/// and an "adds up to total" footer.
///
/// split-clarity (2026-07-02) — Itemized is now a first-class option ON the card
/// (variation A), not a hidden 5th chip inside the custom-split sheet.
final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

/// Three participants so an equal split leaves an indivisible remainder
/// (#853): 10.000/3 does not divide evenly in any currency.
final _threePersonEvent = Event(
  id: 'event-3',
  name: 'Nizwa weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'a-ali',
  participantIds: const ['a-ali', 'b-basma', 'c-zayn'],
  participantNames: const {
    'a-ali': 'Ali Said',
    'b-basma': 'Basma Noor',
    'c-zayn': 'Zayn Malik',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 6, 1),
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    SplitMode splitMode = SplitMode.equally,
    Map<String, Decimal>? splitDistribution,
    SplitExplanation? splitExplanation,
    void Function(SplitMode)? onPickMode,
    VoidCallback? onPickItemized,
    Event? event,
    String amount = '48.000',
    String currency = 'OMR',
  }) async {
    final effectiveEvent = event ?? _event;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SplitCard(
                event: effectiveEvent,
                displayNames: effectiveEvent.participantNames,
                amount: Decimal.parse(amount),
                currency: currency,
                scope: ExpenseScope.global,
                payerId: effectiveEvent.participantIds.first,
                selfId: effectiveEvent.participantIds.first,
                customSplitParticipants: const {},
                splitMode: splitMode,
                splitDistribution: splitDistribution,
                splitExplanation: splitExplanation,
                onChangePayer: () {},
                onScopeChanged: (_) {},
                onCustomSplitChanged: (_) {},
                onPickMode: onPickMode ?? (_) {},
                onPickItemized: onPickItemized ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders one payer control and no stock dropdown (#485)', (
    tester,
  ) async {
    await pumpCard(tester);

    // The single payer control — one "Change" affordance, never a second picker.
    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('PAID BY'), findsNothing); // the retired dropdown's label
  });

  testWidgets('renders the plain-language scope + mode segments (#485)', (
    tester,
  ) async {
    await pumpCard(tester);

    // Scope segment — plain language.
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Some people'), findsOneWidget);
    expect(find.text('Just me'), findsOneWidget);
    // Mode segment.
    expect(find.text('Equal'), findsOneWidget);
    expect(find.text('Shares'), findsOneWidget);
    expect(find.text('Exact'), findsOneWidget);
  });

  testWidgets('#1067 mode chips expose button role and selected state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(SplitCard)));
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

  testWidgets('#1067 mode chip hit region is >=44dp around a compact pill', (
    tester,
  ) async {
    await pumpCard(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(SplitCard)));
    final label = find.text(l10n.splitModeEqually);
    final hitRegion = find
        .ancestor(of: label, matching: find.byType(GestureDetector))
        .first;
    final paintedPill = find
        .ancestor(of: label, matching: find.byType(AnimatedContainer))
        .first;

    expect(tester.getSize(hitRegion).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(paintedPill).height, lessThan(44));
  });

  testWidgets('Itemized is a first-class option on the card (split-clarity)', (
    tester,
  ) async {
    await pumpCard(tester);

    // The whole point: itemized is visible on the card at rest, alongside the
    // four arithmetic modes — no hunting inside the custom-split sheet.
    expect(find.text('Percent'), findsOneWidget);
    expect(find.text('Itemized'), findsOneWidget);
  });

  testWidgets('tapping Itemized fires onPickItemized, not onPickMode', (
    tester,
  ) async {
    var itemizedTaps = 0;
    final modes = <SplitMode>[];
    await pumpCard(
      tester,
      onPickMode: modes.add,
      onPickItemized: () => itemizedTaps++,
    );

    await tester.tap(find.text('Itemized'));
    await tester.pump();

    expect(itemizedTaps, 1);
    // Itemized is NOT a SplitMode — it must not leak through the mode callback.
    expect(modes, isEmpty);
  });

  testWidgets(
    'an itemized expense highlights Itemized, not Exact (helper shown)',
    (tester) async {
      await pumpCard(
        tester,
        // Itemized persists as SplitMode.exact + a splitExplanation (#203).
        splitMode: SplitMode.exact,
        splitDistribution: {
          'uid-yasmin': Decimal.parse('24.000'),
          'uid-layla': Decimal.parse('24.000'),
        },
        splitExplanation: const SplitExplanation(
          items: [
            SplitItem(
              label: 'Dinner',
              amountFils: 48000,
              participantIds: ['uid-yasmin', 'uid-layla'],
            ),
          ],
        ),
      );

      // The selected-mode helper reflects Itemized (proves it's the active
      // selection, not Exact — the pre-fix bug showed "Exact" highlighted).
      expect(
        find.text('Add each receipt line and tick who ordered it.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the selected-mode helper explains Equal by default', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('Everyone pays the same.'), findsOneWidget);
  });

  testWidgets(
    'shows real per-person figures and an adds-up footer (#485/#242)',
    (tester) async {
      await pumpCard(tester);

      // 48 / 2 = 24.000 each, both rows render it.
      expect(find.text('OMR 24.000'), findsWidgets);
      // Reconciliation footer.
      expect(find.textContaining('Adds up to'), findsOneWidget);
    },
  );

  testWidgets('callbacks: payer, scope, and mode taps each fire once (#485)', (
    tester,
  ) async {
    var payerTaps = 0;
    final scopes = <ExpenseScope>[];
    final modes = <SplitMode>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SplitCard(
                event: _event,
                displayNames: const {
                  'uid-yasmin': 'Yasmin Khan',
                  'uid-layla': 'Layla Hassan',
                },
                amount: Decimal.parse('48.000'),
                currency: 'OMR',
                scope: ExpenseScope.global,
                payerId: 'uid-yasmin',
                selfId: 'uid-yasmin',
                customSplitParticipants: const {},
                splitMode: SplitMode.equally,
                splitDistribution: null,
                splitExplanation: null,
                onChangePayer: () => payerTaps++,
                onScopeChanged: scopes.add,
                onCustomSplitChanged: (_) {},
                onPickMode: modes.add,
                onPickItemized: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.tap(find.text('Just me'));
    await tester.tap(find.text('Shares'));
    await tester.pump();

    expect(payerTaps, 1);
    expect(scopes, [ExpenseScope.personal]);
    expect(modes, [SplitMode.shares]);
  });

  // #853: equal-split preview rows must show the allocator's REAL per-person
  // owed (currency-quantized, remainder on the alphabetically-last recipient),
  // so they reconcile to the total — not a naive per-head that sums short.
  // Pre-fix every row showed the naive base (e.g. OMR 3.333), so the remainder
  // value (OMR 3.334) appeared nowhere → this is the RED/GREEN discriminator.
  final nonDivisibleCases =
      <({String currency, String amount, String base, String remainder})>[
        (currency: 'OMR', amount: '10.000', base: '3.333', remainder: '3.334'),
        (currency: 'USD', amount: '10.00', base: '3.33', remainder: '3.34'),
        (currency: 'JPY', amount: '10', base: '3', remainder: '4'),
      ];
  for (final c in nonDivisibleCases) {
    testWidgets('equal split reconciles a ${c.currency} non-divisible total '
        '(#853)', (tester) async {
      await pumpCard(
        tester,
        event: _threePersonEvent,
        amount: c.amount,
        currency: c.currency,
      );
      // Alphabetically-last recipient (Zayn) absorbs the 1-subunit remainder.
      expect(find.text('${c.currency} ${c.remainder}'), findsOneWidget);
      // The other two carry the base share.
      expect(find.text('${c.currency} ${c.base}'), findsWidgets);
    });
  }
}

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/widgets/split_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #485 — the unified Split card: one payer control (no second dropdown),
/// plain-language scope segment, inline mode segment, real per-person figures,
/// and an "adds up to total" footer.
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

void main() {
  Future<void> pumpCard(WidgetTester tester) async {
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
                onChangePayer: () {},
                onScopeChanged: (_) {},
                onCustomSplitChanged: (_) {},
                onPickMode: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders one payer control and no stock dropdown (#485)',
      (tester) async {
    await pumpCard(tester);

    // The single payer control — one "Change" affordance, never a second picker.
    expect(find.text('Change'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('PAID BY'), findsNothing); // the retired dropdown's label
  });

  testWidgets('renders the plain-language scope + mode segments (#485)',
      (tester) async {
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

  testWidgets('shows real per-person figures and an adds-up footer (#485/#242)',
      (tester) async {
    await pumpCard(tester);

    // 48 / 2 = 24.000 each, both rows render it.
    expect(find.text('OMR 24.000'), findsWidgets);
    // Reconciliation footer.
    expect(find.textContaining('Adds up to'), findsOneWidget);
  });

  testWidgets('callbacks: payer, scope, and mode taps each fire once (#485)',
      (tester) async {
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
}

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/widgets/split_scope_selector.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'renders the three scope tabs and shows the payer selector for non-leaders',
    (tester) async {
      ExpenseScope? selectedScope;

      await _pumpSelector(
        tester,
        currentUid: 'uid-layla',
        scope: ExpenseScope.global,
        onScopeChanged: (scope) => selectedScope = scope,
      );

      expect(find.text('Everyone'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      // #247: payer attribution is no longer leader-gated. A non-leader can
      // record who actually paid, so the payer selector is visible to everyone.
      expect(find.byKey(LedgerKeys.payerSectionLabel), findsOneWidget);

      await tester.tap(find.text('Personal'));
      await tester.pump();

      expect(selectedScope, ExpenseScope.personal);
    },
  );

  testWidgets(
    'custom picker includes the current user and toggles self into the set',
    (tester) async {
      Set<String>? selectedParticipants;

      await _pumpSelector(
        tester,
        currentUid: 'uid-layla',
        scope: ExpenseScope.custom,
        customSplitParticipants: const {'uid-yasmin'},
        onCustomSplitChanged: (ids) => selectedParticipants = ids,
      );

      expect(find.text('SELECT PARTICIPANTS'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Yasmin Khan'), findsOneWidget);
      expect(find.text('Omar Said'), findsOneWidget);
      // #247: the current user is no longer filtered out of the custom picker,
      // so you can include yourself in a custom split ("I paid, split me+him").
      expect(find.text('Layla Hassan'), findsOneWidget);

      // Toggling self adds the current user to the custom set.
      await tester.tap(find.text('Layla Hassan'));
      await tester.pump();

      expect(selectedParticipants, {'uid-yasmin', 'uid-layla'});
    },
  );

  testWidgets(
    'leader payer selector defaults to the current user and emits changes',
    (tester) async {
      String? selectedPayer;

      await _pumpSelector(
        tester,
        currentUid: 'uid-yasmin',
        scope: ExpenseScope.global,
        onPayerChanged: (id) => selectedPayer = id,
      );

      expect(find.byKey(LedgerKeys.payerSectionLabel), findsOneWidget);
      expect(find.text('Yasmin Khan (Me)'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Layla Hassan').last);
      await tester.pumpAndSettle();

      expect(selectedPayer, 'uid-layla');
    },
  );
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  required String currentUid,
  required ExpenseScope scope,
  ValueChanged<ExpenseScope>? onScopeChanged,
  Set<String> customSplitParticipants = const {},
  ValueChanged<Set<String>>? onCustomSplitChanged,
  String? selectedPayerId,
  ValueChanged<String?>? onPayerChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          MockUser(uid: currentUid, isAnonymous: true),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SplitScopeSelector(
              event: _event,
              scope: scope,
              onScopeChanged: onScopeChanged ?? (_) {},
              customSplitParticipants: customSplitParticipants,
              onCustomSplitChanged: onCustomSplitChanged ?? (_) {},
              selectedPayerId: selectedPayerId,
              onPayerChanged: onPayerChanged ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla', 'uid-omar'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
    'uid-omar': 'Omar Said',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

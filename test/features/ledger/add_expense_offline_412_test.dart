import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockExpenseService extends Mock implements ExpenseService {}

// #412 RED: on a real device offline, the Firestore write future resolves only
// on SERVER ack, so awaiting it raw hangs the Add button spinner indefinitely
// and the #357 "Saved — will sync" feedback never fires. FakeFirebaseFirestore
// acks instantly and can't model this — the never-completing Completer below
// is the real offline behavior.
void main() {
  testWidgets(
    '#412: offline add shows the queued success dialog within bounded time '
    '— no indefinite spinner',
    (tester) async {
      final service = _MockExpenseService();
      // Current (buggy) path: addExpense resolves only on server ack.
      when(
        () => service.addExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          payerParticipantId: 'uid-yasmin',
          amount: Decimal.parse('12.5'),
          description: null,
          scope: ExpenseScope.global,
          customSplitParticipants: null,
          splitMode: SplitMode.equally,
          splitDistribution: null,
          categoryId: 'food',
          createdBy: 'uid-yasmin',
        ),
      ).thenAnswer((_) => Completer<Expense>().future);
      // Fixed path: stageExpense hands back the locally-built expense plus a
      // never-acking write future.
      when(
        () => service.stageExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          payerParticipantId: 'uid-yasmin',
          amount: Decimal.parse('12.5'),
          description: null,
          scope: ExpenseScope.global,
          customSplitParticipants: null,
          splitMode: SplitMode.equally,
          splitDistribution: null,
          categoryId: 'food',
          createdBy: 'uid-yasmin',
        ),
      ).thenReturn((expense: _expense, ack: Completer<void>().future));

      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentUserIdProvider.overrideWithValue('uid-yasmin'),
            connectivityProvider.overrideWith((ref) => connectivity),
            expenseServiceProvider.overrideWithValue(service),
            groupDetailProvider(
              'group-1',
            ).overrideWith((ref) => Stream.value(_group)),
            eventDetailProvider((
              groupId: 'group-1',
              eventId: 'event-1',
            )).overrideWith((ref) => Stream.value(_event)),
            // #204: category is mandatory at creation → offer one to pick.
            tripCategoriesProvider('event-1').overrideWith(
              (ref) => Stream.value([
                ExpenseCategory(
                  id: 'food',
                  tripId: 'event-1',
                  name: 'Food',
                  icon: 'food',
                  color: '#C2693B',
                  createdAt: DateTime(2026, 1, 1),
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AddExpenseScreen(groupId: 'group-1', eventId: 'event-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AddExpenseScreen)),
      );

      await tester.enterText(find.byType(TextField).first, '12.5');
      await tester.tap(find.text('Food')); // #204: category is mandatory
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      // Past kWriteAckTimeout (5s) + dialog entrance animation. Never
      // pumpAndSettle here (ConnectivityNotifier trap) — fixed pumps only.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      // The queued success dialog appeared with the honest badge…
      expect(find.text('Expense saved'), findsOneWidget);
      expect(find.text('SAVED — WILL SYNC'), findsOneWidget);
      // …the one-shot home balance was told to refresh (#104)…
      expect(container.read(ledgerRevisionProvider), 1);
      // …and the banner state reads "Saved — will sync" (#357/#412).
      expect(connectivity.state, ConnectivityStatus.syncing);
      expect(find.byType(OfflineBanner), findsOneWidget);
    },
  );
}

final _group = Group(
  id: 'group-1',
  name: 'Trip',
  inviteCode: 'ABC123',
  createdBy: 'uid-yasmin',
  memberIds: const ['uid-yasmin'],
  currency: 'OMR',
  createdAt: DateTime(2026),
);

final _event = Event(
  id: 'event-1',
  name: 'Marrakech, four ways',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
  },
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

final _expense = Expense(
  id: 'expense-1',
  tripId: 'event-1',
  payerParticipantId: 'uid-yasmin',
  amount: Decimal.parse('12.5'),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 5, 31),
  createdBy: 'uid-yasmin',
);

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/widgets/pre_settlement_review_sheet.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #898: event pre-settlement review flags are display-only warnings. The
/// event entry point must suppress flags whose currency bucket is already
/// fully settled, using the same balance basis the screen displays.

const _groupId = 'group-1';
const _eventId = 'event-1';
const _eventRef = (groupId: _groupId, eventId: _eventId);

final _event = Event(
  id: _eventId,
  groupId: _groupId,
  name: 'Beach Trip',
  type: EventType.trip,
  createdBy: 'alice',
  participantIds: const ['alice', 'bob'],
  participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 16),
);

final _group = Group(
  id: _groupId,
  name: 'Trip',
  inviteCode: 'ABC123',
  createdBy: 'alice',
  memberIds: const ['alice', 'bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 5, 16),
);

final _members = [
  GroupMember(
    id: 'alice',
    groupId: _groupId,
    userId: 'alice',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 5, 16),
  ),
  GroupMember(
    id: 'bob',
    groupId: _groupId,
    userId: 'bob',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 5, 16),
  ),
];

Expense _expense({
  required String id,
  required String description,
  String amount = '10.000',
  String currency = 'OMR',
  SplitMode? splitMode = SplitMode.equally,
}) {
  return Expense(
    id: id,
    tripId: _eventId,
    payerParticipantId: 'alice',
    amount: Decimal.parse(amount),
    description: description,
    scope: ExpenseScope.global,
    splitMode: splitMode,
    currency: currency,
    createdAt: DateTime(2026, 5, 16),
    createdBy: 'alice',
  );
}

Settlement _settlement({
  required String id,
  required String amount,
  String currency = 'OMR',
}) {
  return Settlement(
    id: id,
    tripId: _eventId,
    payerParticipantId: 'bob',
    recipientParticipantId: 'alice',
    amount: Decimal.parse(amount),
    currency: currency,
    settledAt: DateTime(2026, 5, 17),
    createdBy: 'bob',
  );
}

Widget _wrap({
  required SharedPreferences prefs,
  required Stream<List<Expense>> expenses,
  required Stream<List<Settlement>> settlements,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('bob'),
      eventDetailProvider(_eventRef).overrideWith((_) => Stream.value(_event)),
      eventExpensesProvider(_eventRef).overrideWith((_) => expenses),
      eventSettlementsProvider(_eventRef).overrideWith((_) => settlements),
      groupMembersProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_members)),
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group)),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettleUpScreen(groupId: _groupId, eventId: _eventId),
      ),
    ),
  );
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('no sheet when every flagged event currency is already settled', (
    tester,
  ) async {
    final prefs = await _prefs();
    final settledExact = _expense(
      id: 'omr-exact',
      description: 'Settled OMR dinner',
      splitMode: SplitMode.exact,
    );

    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        expenses: Stream.value([settledExact]),
        settlements: Stream.value([
          _settlement(id: 'settle-omr', amount: '5.000'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
    expect(find.text('Settled OMR dinner'), findsNothing);
  });

  testWidgets(
    'sheet appears when flagged event currency is still outstanding',
    (tester) async {
      final prefs = await _prefs();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          expenses: Stream.value([
            _expense(
              id: 'omr-exact',
              description: 'Outstanding OMR dinner',
              splitMode: SplitMode.exact,
            ),
          ]),
          settlements: Stream.value(const <Settlement>[]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Outstanding OMR dinner'), findsOneWidget);
    },
  );

  testWidgets('mixed buckets hide settled OMR rows and keep outstanding USD', (
    tester,
  ) async {
    final prefs = await _prefs();
    final omrSettled = _expense(
      id: 'omr-exact',
      description: 'Settled OMR dinner',
      splitMode: SplitMode.exact,
    );
    final usdLarge = _expense(
      id: 'usd-large',
      description: 'Outstanding USD villa',
      amount: '120.00',
      currency: 'USD',
    );
    final usdSmall = _expense(
      id: 'usd-small',
      description: 'USD coffee',
      amount: '1.00',
      currency: 'USD',
    );

    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        expenses: Stream.value([omrSettled, usdLarge, usdSmall]),
        settlements: Stream.value([
          _settlement(id: 'settle-omr', amount: '5.000'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Settled OMR dinner'), findsNothing);
    expect(find.text('Outstanding USD villa'), findsOneWidget);
  });

  testWidgets('does not latch while event settlements are still loading', (
    tester,
  ) async {
    final prefs = await _prefs();
    final settlements = StreamController<List<Settlement>>();
    addTearDown(settlements.close);

    await tester.pumpWidget(
      _wrap(
        prefs: prefs,
        expenses: Stream.value([
          _expense(
            id: 'omr-exact',
            description: 'Eventually settled OMR dinner',
            splitMode: SplitMode.exact,
          ),
        ]),
        settlements: settlements.stream,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);

    settlements.add([_settlement(id: 'settle-omr', amount: '5.000')]);
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
    expect(find.text('Eventually settled OMR dinner'), findsNothing);
  });

  testWidgets(
    'settlement stream hard error → loud error view, basis never computed '
    '(#1028)',
    (tester) async {
      final prefs = await _prefs();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          expenses: Stream.value([
            _expense(
              id: 'omr-exact',
              description: 'Error-path OMR dinner',
              splitMode: SplitMode.exact,
            ),
          ]),
          settlements: Stream.error(StateError('settlements failed')),
        ),
      );
      await tester.pumpAndSettle();

      // #1028: the basis is OUTBOUND — folding an errored settlements stream
      // to [] resurrected settled debts as over-pay suggestions. The fail-open
      // contract survives only for the MEMBERS-error leg.
      expect(find.text("Couldn't load balances."), findsOneWidget);
      expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
      expect(find.text('Error-path OMR dinner'), findsNothing);
    },
  );
}

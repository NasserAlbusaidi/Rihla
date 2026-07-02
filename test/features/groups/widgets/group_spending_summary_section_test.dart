import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_spending_summary_section.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

const _groupId = 'group-1';

Event _makeEvent(String id, String name) {
  return Event(
    id: id,
    name: name,
    type: EventType.trip,
    groupId: _groupId,
    createdBy: 'creator',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Abdullah', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    createdAt: DateTime(2025, 1, 1),
  );
}

GroupMember _makeMember(String uid, String name) {
  return GroupMember(
    id: 'member-$uid',
    groupId: _groupId,
    userId: uid,
    displayName: name,
    role: 'MEMBER',
    joinedAt: DateTime(2025, 1, 1),
  );
}

Expense _makeExpense({
  required String id,
  required String tripId,
  required String amount,
  String payer = 'uid-1',
  String currency = 'OMR',
  String? categoryId,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    createdAt: DateTime(2025, 1, 1),
    categoryId: categoryId,
    currency: currency,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Event> events,
  required Map<String, List<Expense>> expensesByEvent,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        groupEventsProvider(_groupId).overrideWith((_) => Stream.value(events)),
        groupMembersProvider(_groupId).overrideWith(
          (_) => Stream.value([
            _makeMember('uid-1', 'Abdullah'),
            _makeMember('uid-2', 'Nasser'),
          ]),
        ),
        groupSettlementsProvider(_groupId)
            .overrideWith((_) => Stream.value(const <Settlement>[])),
        for (final event in events) ...[
          eventExpensesProvider((groupId: _groupId, eventId: event.id))
              .overrideWith(
            (_) => Stream.value(expensesByEvent[event.id] ?? const []),
          ),
          eventSettlementsProvider((groupId: _groupId, eventId: event.id))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: GroupSpendingSummarySection(groupId: _groupId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no expenses -> section absent, header included', (tester) async {
    await _pump(
      tester,
      events: [_makeEvent('event-a', 'Wahiba Sands')],
      expensesByEvent: const {'event-a': []},
    );

    expect(find.byKey(GroupKeys.insightsSection), findsNothing);
    expect(find.text('INSIGHTS'), findsNothing);
  });

  testWidgets('populated -> header, total, top event and top payer name',
      (tester) async {
    await _pump(
      tester,
      events: [
        _makeEvent('event-a', 'Wahiba Sands'),
        _makeEvent('event-b', 'Jabal Shams'),
      ],
      expensesByEvent: {
        'event-a': [
          _makeExpense(
            id: 'x1',
            tripId: 'event-a',
            amount: '60',
            categoryId: 'fuel',
          ),
        ],
        'event-b': [
          _makeExpense(
            id: 'x2',
            tripId: 'event-b',
            amount: '40',
            payer: 'uid-2',
            categoryId: 'food',
          ),
        ],
      },
    );

    expect(find.byKey(GroupKeys.insightsSection), findsOneWidget);
    expect(find.text('INSIGHTS'), findsOneWidget);
    // Top event = Wahiba (60 > 40); rendered by name, not id.
    expect(find.text('Wahiba Sands'), findsOneWidget);
    // Top payer uid-1 resolved through memberNames.
    expect(find.text('Abdullah'), findsWidgets);
    // Money renders through RAmount only.
    expect(find.byType(RAmount), findsWidgets);
    // Category labels come from the catalog.
    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
  });

  testWidgets('multi-currency -> one card per currency, nothing combined',
      (tester) async {
    await _pump(
      tester,
      events: [_makeEvent('event-a', 'Wahiba Sands')],
      expensesByEvent: {
        'event-a': [
          _makeExpense(id: 'x1', tripId: 'event-a', amount: '10'),
          _makeExpense(
            id: 'x2',
            tripId: 'event-a',
            amount: '7',
            currency: 'USD',
            payer: 'uid-2',
          ),
        ],
      },
    );

    final currencies = tester
        .widgetList<RAmount>(find.byType(RAmount))
        .map((w) => w.currency)
        .toSet();
    expect(currencies, containsAll(['OMR', 'USD']));
    // 10 OMR + 7 USD must never merge into a 17 anywhere.
    final values = tester
        .widgetList<RAmount>(find.byType(RAmount))
        .map((w) => w.value)
        .toList();
    expect(values, isNot(contains(Decimal.parse('17'))));
  });
}

// #1283 — accessibility guideline matchers for SettleUpScreen (event scope).
//
// Arrange section copied from test/features/ledger/settle_up_screen_test.dart
// (`buildScreen` defaults: alice paid, currentUid 'bob' owes) — reuse, don't
// invent new fixtures.

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/recording_functions_service.dart';

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

final _expenses = [
  Expense(
    id: 'expense-1',
    tripId: _eventId,
    payerParticipantId: 'alice',
    amount: Decimal.parse('20.000'),
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 16),
    createdBy: 'alice',
  ),
];

Widget _buildScreen(
  FakeFirebaseFirestore fakeDb, {
  Locale? locale,
  required RecordingFunctionsService recordingFunctions,
  required SharedPreferences prefs,
}) {
  final overrides = [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserIdProvider.overrideWithValue('bob'),
    eventDetailProvider(_eventRef).overrideWith((ref) => Stream.value(_event)),
    eventExpensesProvider(
      _eventRef,
    ).overrideWith((ref) => Stream.value(_expenses)),
    eventSettlementsProvider(
      _eventRef,
    ).overrideWith((ref) => Stream.value(const <Settlement>[])),
    groupMembersProvider(
      _groupId,
    ).overrideWith((ref) => Stream.value(const [])),
    groupDetailProvider(_groupId).overrideWith(
      (ref) => Stream.value(
        Group(
          id: _groupId,
          name: 'Trip',
          inviteCode: 'ABC123',
          createdBy: 'bob',
          memberIds: const [],
          currency: 'OMR',
          createdAt: DateTime(2026),
        ),
      ),
    ),
    settlementServiceProvider.overrideWithValue(
      SettlementService.withFirestore(
        fakeDb,
        functionsService: recordingFunctions,
      ),
    ),
    groupActivityServiceProvider.overrideWithValue(
      GroupActivityService.withFirestore(fakeDb),
    ),
  ];

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SettleUpScreen(groupId: _groupId, eventId: _eventId),
    ),
  );
}

void main() {
  late SharedPreferences prefs;
  late RecordingFunctionsService recordingFunctions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recordingFunctions = RecordingFunctionsService();
  });

  Future<void> pumpScreen(WidgetTester tester, {required Locale locale}) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(
      _buildScreen(
        fakeDb,
        locale: locale,
        recordingFunctions: recordingFunctions,
        prefs: prefs,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SettleUpScreen (event scope) accessibility (#1283)', () {
    testWidgets('EN meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // androidTapTargetGuideline and textContrastGuideline both pass for real
    // on this screen today (verified stable across repeated runs).
    testWidgets('EN meets androidTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets androidTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('EN meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('AR meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}

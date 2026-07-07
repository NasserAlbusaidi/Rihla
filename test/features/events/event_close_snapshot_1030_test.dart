import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/events/widgets/event_danger_section.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1030 — the spending snapshot captured at event close is an OUTBOUND write
/// (frozen spending served by every future recap open). Its owed map comes
/// from `ledgerViewProvider.balances`, which folds `groupMembersProvider` —
/// a valueless members stream means a wrong #249 universe, so the close must
/// capture NO snapshot (recap stays live; recoverable by reopen+close) rather
/// than freeze wrong money.
class _MockEventService extends Mock implements EventService {}

class _SilentActivityService extends GroupActivityService {
  _SilentActivityService() : super.withFirestore(FakeFirebaseFirestore());

  @override
  Future<void> logActivity({
    required String groupId,
    required String type,
    required String actorId,
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {}
}

final _event = Event(
  id: 'evt-1',
  name: 'Summer Trip',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-a',
  participantIds: const ['uid-a', 'uid-b'],
  participantNames: const {'uid-a': 'Alice', 'uid-b': 'Bob'},
  modules: EventModules.forType(EventType.trip),
  createdAt: DateTime(2026, 3, 1),
);

final _expenses = [
  Expense(
    id: 'x1',
    tripId: 'evt-1',
    payerParticipantId: 'uid-a',
    amount: Decimal.parse('10.000'),
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 3, 2),
    createdBy: 'uid-a',
  ),
];

GroupMember _member(String uid, String name) => GroupMember(
  id: 'doc-$uid',
  groupId: 'group-1',
  userId: uid,
  displayName: name,
  role: 'member',
  joinedAt: DateTime(2026, 1, 1),
);

Widget _wrap({
  required SharedPreferences prefs,
  required EventService eventService,
  required Stream<List<GroupMember>> membersStream,
}) {
  final eventRef = (groupId: _event.groupId, eventId: _event.id);
  final router = GoRouter(
    initialLocation: '/danger',
    routes: [
      GoRoute(
        path: '/danger',
        // Consumer keeps eventDetailProvider WARM like prod navigation does
        // (hub → settings) — a cold provider read at close time would empty
        // the recap for the wrong reason and mask the members leg.
        builder: (_, _) => Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(eventDetailProvider(eventRef));
              return EventDangerSection(
                groupId: _event.groupId,
                eventId: _event.id,
                event: _event,
                isAdmin: true,
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('Group:${state.pathParameters['gid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      connectivityProvider.overrideWith(
        (ref) => ConnectivityNotifier(startPeriodicChecks: false),
      ),
      eventServiceProvider.overrideWithValue(eventService),
      groupActivityServiceProvider.overrideWithValue(_SilentActivityService()),
      // eventDetailProvider valued so eventRecapProvider builds a REAL
      // (non-empty) recap — otherwise the snapshot is null for the wrong
      // reason and the error case can't go RED.
      eventDetailProvider(
        eventRef,
      ).overrideWith((ref) => Stream<Event?>.value(_event)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(_expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      groupMembersProvider(_event.groupId).overrideWith((ref) => membersStream),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    prefs = await SharedPreferences.getInstance();
  });

  Future<Map<String, dynamic>?> closeAndCaptureSnapshot(
    WidgetTester tester,
    Stream<List<GroupMember>> membersStream,
  ) async {
    final service = _MockEventService();
    when(
      () => service.closeEvent(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        closedBy: any(named: 'closedBy'),
        spendingSnapshot: any(named: 'spendingSnapshot'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      _wrap(prefs: prefs, eventService: service, membersStream: membersStream),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(EventKeys.closeEventTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EventKeys.closeEventConfirmButton));
    await tester.pumpAndSettle();

    final captured = verify(
      () => service.closeEvent(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        closedBy: any(named: 'closedBy'),
        spendingSnapshot: captureAny(named: 'spendingSnapshot'),
      ),
    ).captured;
    return captured.single as Map<String, dynamic>?;
  }

  testWidgets(
    '#1030: close under a members hard error captures NO spending snapshot',
    (tester) async {
      final snapshot = await closeAndCaptureSnapshot(
        tester,
        Stream<List<GroupMember>>.error(StateError('members failed')),
      );
      expect(snapshot, isNull);
    },
  );

  testWidgets(
    '#1030 pin: healthy close still captures the spending snapshot',
    (tester) async {
      final snapshot = await closeAndCaptureSnapshot(
        tester,
        Stream.value([_member('uid-a', 'Alice'), _member('uid-b', 'Bob')]),
      );
      expect(snapshot, isNotNull);
      expect(snapshot!['expenseCount'], 1);
    },
  );
}

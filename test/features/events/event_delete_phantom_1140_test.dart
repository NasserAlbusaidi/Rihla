// test/features/events/event_delete_phantom_1140_test.dart
//
// #1140: a denied/queued-then-denied event soft-delete must persist NO
// `event_deleted` activity row (phantom history). The `event_deleted` row is
// folded into deleteEvent's OWN atomic WriteBatch, so it shares the mutation's
// fate. event_danger_section reads the actor from FirebaseConfig.currentUser
// directly, so these tests register a fake signed-in FirebaseAuthPlatform (the
// #1124 seam) — without it, actorId == '' takes the D7 domain-only fallback and
// the activity path is never exercised.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// --- Fake signed-in FirebaseAuthPlatform (#1124 seam) --------------------
const _uid = 'uid-alice';

class _FakeMultiFactorPlatform extends MultiFactorPlatform {
  _FakeMultiFactorPlatform(super.auth);
}

class _FakeUserPlatform extends UserPlatform {
  _FakeUserPlatform(FirebaseAuthPlatform auth, String uid)
      : super(
          auth,
          _FakeMultiFactorPlatform(auth),
          PigeonUserDetails(
            userInfo: PigeonUserInfo(
              uid: uid,
              isAnonymous: true,
              isEmailVerified: false,
            ),
            providerData: const [],
          ),
        );
}

class _FakeFirebaseAuthPlatform extends FirebaseAuthPlatform {
  _FakeFirebaseAuthPlatform(FirebaseApp app) : super(appInstance: app);
  UserPlatform? _user;
  // Mutable so a single instance (bound once in setUpAll) can flip between a
  // signed-in uid and null WITHOUT re-binding FirebaseAuth.instance.
  void setUser(String? uid) => _user = uid == null ? null : _FakeUserPlatform(this, uid);
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;
  @override
  UserPlatform? get currentUser => _user;
}

class _MockEventService extends Mock implements EventService {}

Event _event() => Event(
      id: 'evt-1',
      name: 'Camping Weekend',
      type: EventType.camping,
      groupId: 'g1',
      createdBy: _uid,
      participantIds: const [_uid],
      participantNames: const {_uid: 'Alice'},
      modules: const EventModules(),
      startDate: DateTime(2026, 3, 15),
      createdAt: DateTime(2026, 3, 10),
    );

Widget _wrap({
  required SharedPreferences prefs,
  required EventService eventService,
  required GroupActivityService activityService,
}) {
  final event = _event();
  final eventRef = (groupId: event.groupId, eventId: event.id);
  final router = GoRouter(
    initialLocation: '/danger',
    routes: [
      GoRoute(
        path: '/danger',
        builder: (_, _) => Scaffold(
          body: EventDangerSection(
            groupId: event.groupId,
            eventId: event.id,
            event: event,
            isAdmin: true,
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
      groupActivityServiceProvider.overrideWithValue(activityService),
      eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
      eventExpensesProvider(eventRef).overrideWith((ref) => Stream.value(const [])),
      eventSettlementsProvider(eventRef).overrideWith((ref) => Stream.value(const [])),
      groupMembersProvider(event.groupId)
          .overrideWith((ref) => Stream.value(const <GroupMember>[])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _confirmDelete(WidgetTester tester) async {
  await tester.tap(find.byKey(EventKeys.deleteEventTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
  await tester.pumpAndSettle();
}

Future<int> _activityCount(FakeFirebaseFirestore fake) async {
  final snap =
      await fake.collection('groups').doc('g1').collection('activity').get();
  return snap.docs.length;
}

/// Seeds the live event doc so a soft-delete `.update()`/batch has a target.
Future<void> _seedEvent(FakeFirebaseFirestore fake) {
  return fake
      .collection('groups')
      .doc('g1')
      .collection('events')
      .doc('evt-1')
      .set({...(_event().toFirestoreMap()), 'id': 'evt-1'});
}

void main() {
  late SharedPreferences prefs;
  late FirebaseApp app;
  late _FakeFirebaseAuthPlatform auth;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    app = await Firebase.initializeApp();
    auth = _FakeFirebaseAuthPlatform(app);
    FirebaseAuthPlatform.instance = auth;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
    prefs = await SharedPreferences.getInstance();
    auth.setUser(_uid); // signed in by default
  });

  testWidgets(
    'a denied event soft-delete persists NO event_deleted activity row (#1140)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      final activityService = GroupActivityService.withFirestore(fake);
      // deleteEvent is denied on the (offline-queued) replay: model it as a
      // future that rejects. Pre-fix, the screen wrote a SEPARATE activity row
      // before/independent of this — so the assertion below would fail (RED).
      final eventService = _MockEventService();
      when(() => eventService.deleteEvent(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
            activityId: any(named: 'activityId'),
            activityActorId: any(named: 'activityActorId'),
            activityActorName: any(named: 'activityActorName'),
            activityDescription: any(named: 'activityDescription'),
            activityMetadata: any(named: 'activityMetadata'),
          )).thenAnswer(
        (_) => Future<void>.error(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Simulated denied delete on replay.',
          ),
        ),
      );

      await tester.pumpWidget(_wrap(
        prefs: prefs,
        eventService: eventService,
        activityService: activityService,
      ));
      await tester.pumpAndSettle();
      await _confirmDelete(tester);

      // The activity is now folded into deleteEvent's batch (mocked away here),
      // NOT written separately — so a denied delete leaves zero phantom rows.
      expect(await _activityCount(fake), 0);
    },
  );

  testWidgets(
    'a successful event soft-delete writes exactly one event_deleted row keyed '
    'evt_deleted_<id> (#1140)',
    (tester) async {
      final fake = FakeFirebaseFirestore();
      await _seedEvent(fake); // the soft-delete batch updates an existing doc
      // Real EventService on the SAME fake → deleteEvent's batch writes both the
      // soft-delete and the activity row atomically into this fake.
      final eventService = EventService.withFirestore(fake);
      final activityService = GroupActivityService.withFirestore(fake);

      await tester.pumpWidget(_wrap(
        prefs: prefs,
        eventService: eventService,
        activityService: activityService,
      ));
      await tester.pumpAndSettle();
      await _confirmDelete(tester);

      final snap = await fake
          .collection('groups')
          .doc('g1')
          .collection('activity')
          .get();
      expect(snap.docs, hasLength(1));
      final data = snap.docs.single.data();
      expect(snap.docs.single.id, equals('evt_deleted_evt-1'));
      expect(data['type'], equals('event_deleted'));
      expect(data['actorId'], equals(_uid));
      expect(data['actorName'], equals('Alice'));
      expect(data['metadata'],
          containsPair('eventName', 'Camping Weekend'));
    },
  );

  testWidgets(
    'D7: with NO signed-in user, delete falls back to domain-only (no activity '
    'params) and still routes back',
    (tester) async {
      // No auth user → actorId == '' → domain-only deleteEvent, never blocked.
      auth.setUser(null);
      final fake = FakeFirebaseFirestore();
      final activityService = GroupActivityService.withFirestore(fake);
      final eventService = _MockEventService();
      when(() => eventService.deleteEvent(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        prefs: prefs,
        eventService: eventService,
        activityService: activityService,
      ));
      await tester.pumpAndSettle();
      await _confirmDelete(tester);

      // Called WITHOUT activity params (the 2-arg overload), and routed back.
      verify(() => eventService.deleteEvent(groupId: 'g1', eventId: 'evt-1'))
          .called(1);
      expect(find.text('Group:g1'), findsOneWidget);
      expect(await _activityCount(fake), 0);
    },
  );
}

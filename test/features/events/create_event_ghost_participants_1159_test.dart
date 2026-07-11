import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/app_messenger.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/create_event_screen.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockEventService extends Mock implements EventService {}

class _MockGroupActivityService extends Mock implements GroupActivityService {}

// ---------------------------------------------------------------------------
// Fixtures (own — never mutate create_event_test.dart's shared ones)
// ---------------------------------------------------------------------------

const _tombId = 'tombstone-deleted-abc123';

final _live = GroupMember(
  id: 'uid-a',
  groupId: 'g1',
  userId: 'uid-a',
  displayName: 'Alice',
  role: 'CREATOR',
  joinedAt: DateTime(2026),
);
final _liveB = GroupMember(
  id: 'uid-b',
  groupId: 'g1',
  userId: 'uid-b',
  displayName: 'Bob',
  role: 'MEMBER',
  joinedAt: DateTime(2026),
);
final _shadow = GroupMember(
  id: 'shadow-uuid-1',
  groupId: 'g1',
  userId: 'shadow-uuid-1',
  displayName: 'Chad',
  role: 'MEMBER',
  isShadow: true,
  joinedAt: DateTime(2026),
);
final _ghost = GroupMember(
  id: _tombId,
  groupId: 'g1',
  userId: _tombId,
  displayName: 'Dana',
  role: 'MEMBER',
  isTombstone: true,
  joinedAt: DateTime(2026),
);

/// post-#1154 group: `activeMemberIds` present, tombstone excluded from it.
final _groupR5 = Group(
  id: 'g1',
  name: 'G',
  inviteCode: 'ABC123',
  createdBy: 'uid-a',
  memberIds: const ['uid-a', 'uid-b', 'shadow-uuid-1', _tombId],
  activeMemberIds: const ['uid-a', 'uid-b', 'shadow-uuid-1'],
  createdAt: DateTime(2026),
);

/// legacy group: `activeMemberIds` ABSENT — copyWith can't null it (`?? this.`),
/// so this is a second literal built WITHOUT the field (rules would fall back
/// to full memberIds, ghost included — belt-and-braces still hides it).
final _groupLegacy = Group(
  id: 'g1',
  name: 'G',
  inviteCode: 'ABC123',
  createdBy: 'uid-a',
  memberIds: const ['uid-a', 'uid-b', 'shadow-uuid-1', _tombId],
  createdAt: DateTime(2026),
);

/// Returned by the stubbed stageEvent; its id drives the post-submit nav.
final _createdEvent = Event(
  id: 'event-created',
  name: 'Beach Day',
  type: EventType.trip,
  groupId: 'g1',
  createdBy: 'uid-a',
  participantIds: const ['uid-a', 'uid-b', 'shadow-uuid-1'],
  participantNames: const {
    'uid-a': 'Alice',
    'uid-b': 'Bob',
    'shadow-uuid-1': 'Chad',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 6, 1),
);

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Widget _wrapCreate({
  required SharedPreferences prefs,
  required List<GroupMember> members,
  Stream<Group>? groupStream,
  EventType initialType = EventType.trip,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
      groupDetailProvider(
        'g1',
      ).overrideWith((ref) => groupStream ?? Stream.value(_groupR5)),
      eventLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CreateEventScreen(groupId: 'g1', initialEventType: initialType),
    ),
  );
}

Widget _wrapCreateRouted({
  required SharedPreferences prefs,
  required EventService eventService,
  required GroupActivityService activityService,
  required List<GroupMember> members,
  Stream<Group>? groupStream,
  String? currentUserId = 'uid-a',
  ConnectivityStatus connectivity = ConnectivityStatus.online,
  EventType initialType = EventType.trip,
}) {
  final router = GoRouter(
    initialLocation: '/create',
    routes: [
      GoRoute(
        path: '/create',
        builder: (_, _) => CreateEventScreen(
          groupId: 'g1',
          initialEventType: initialType,
        ),
      ),
      GoRoute(
        path: '/group/:gid/event/:eid',
        builder: (_, state) =>
            Scaffold(body: Text('EventHub:${state.pathParameters['eid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUserId),
      eventServiceProvider.overrideWithValue(eventService),
      groupActivityServiceProvider.overrideWithValue(activityService),
      groupMembersProvider('g1').overrideWith((ref) => Stream.value(members)),
      groupDetailProvider(
        'g1',
      ).overrideWith((ref) => groupStream ?? Stream.value(_groupR5)),
      eventLoadingProvider.overrideWith((ref) => false),
      // Timer-free notifier — pumpAndSettle hangs on the 60s periodic timer.
      connectivityProvider.overrideWith((ref) {
        final notifier = ConnectivityNotifier(startPeriodicChecks: false);
        if (connectivity == ConnectivityStatus.offline) notifier.setOffline();
        if (connectivity == ConnectivityStatus.syncing) notifier.setSyncing();
        return notifier;
      }),
    ],
    child: MaterialApp.router(
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Stub stageEvent so it accepts any participant set and returns [_createdEvent].
void _stubStageEvent(EventService eventService) {
  when(
    () => eventService.stageEvent(
      groupId: 'g1',
      name: 'Beach Day',
      type: EventType.trip,
      participantIds: any(named: 'participantIds'),
      participantNames: any(named: 'participantNames'),
      createdBy: 'uid-a',
      startDate: null,
      endDate: null,
      modules: null,
      activityActorId: any(named: 'activityActorId'),
      activityActorName: any(named: 'activityActorName'),
    ),
  ).thenReturn((event: _createdEvent, ack: Future<void>.value()));
}

/// Capture the participantIds/participantNames of the single stageEvent call.
({Set<String> ids, Map<String, String> names}) _capturedStage(
  EventService eventService,
) {
  final captured = verify(
    () => eventService.stageEvent(
      groupId: 'g1',
      name: 'Beach Day',
      type: EventType.trip,
      participantIds: captureAny(named: 'participantIds'),
      participantNames: captureAny(named: 'participantNames'),
      createdBy: 'uid-a',
      startDate: null,
      endDate: null,
      modules: null,
      activityActorId: any(named: 'activityActorId'),
      activityActorName: any(named: 'activityActorName'),
    ),
  ).captured;
  final ids = (captured[0] as List).cast<String>().toSet();
  final names = (captured[1] as Map).cast<String, String>();
  return (ids: ids, names: names);
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField), 'Beach Day');
  await tester.ensureVisible(find.byKey(EventKeys.createEventButton));
  await tester.tap(find.byKey(EventKeys.createEventButton));
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Test User',
    });
    prefs = await SharedPreferences.getInstance();
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
  });

  group('#1159 create-event ghost default-selection', () {
    testWidgets('ghost row hidden, live+shadow rows shown', (tester) async {
      await tester.pumpWidget(
        _wrapCreate(prefs: prefs, members: [_live, _liveB, _shadow, _ghost]),
      );
      await tester.pumpAndSettle();

      // A tombstone renders as "Dana (former member)" (MemberNameResolver
      // suffix), so match by substring — exact 'Dana' finds nothing pre-fix too.
      expect(find.textContaining('Dana'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Chad'), findsOneWidget);
    });

    testWidgets(
      'default selection excludes ghost — submitted participantIds are '
      'active-only',
      (tester) async {
        final eventService = _MockEventService();
        final activityService = _MockGroupActivityService();
        _stubStageEvent(eventService);

        await tester.pumpWidget(
          _wrapCreateRouted(
            prefs: prefs,
            eventService: eventService,
            activityService: activityService,
            members: [_live, _liveB, _shadow, _ghost],
          ),
        );
        await tester.pumpAndSettle();
        await _fillAndSubmit(tester);

        final stage = _capturedStage(eventService);
        expect(stage.ids, {'uid-a', 'uid-b', 'shadow-uuid-1'});
        expect(stage.names.containsKey(_tombId), isFalse);
      },
    );

    testWidgets(
      'Select All checked at default AND only eligible rows render',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreate(prefs: prefs, members: [_live, _liveB, _shadow, _ghost]),
        );
        await tester.pumpAndSettle();

        // Discriminator (Gate R1-rubric P2): a bare Select-All-checked assertion
        // is non-discriminating (pre-fix 4==4 → also checked). The row count is
        // what goes RED: 3 eligible rows → 4 checkboxes (3 rows + Select-All);
        // pre-fix renders Dana's row too → 5 checkboxes.
        expect(find.byType(Checkbox), findsNWidgets(4));
        // A tombstone renders as "Dana (former member)" (MemberNameResolver
      // suffix), so match by substring — exact 'Dana' finds nothing pre-fix too.
      expect(find.textContaining('Dana'), findsNothing);

        final selectAll = tester.widget<Checkbox>(
          find.byKey(EventKeys.selectAllButton),
        );
        expect(selectAll.value, isTrue);
      },
    );

    testWidgets('Select All selects only eligible members', (tester) async {
      final eventService = _MockEventService();
      final activityService = _MockGroupActivityService();
      _stubStageEvent(eventService);

      await tester.pumpWidget(
        _wrapCreateRouted(
          prefs: prefs,
          eventService: eventService,
          activityService: activityService,
          members: [_live, _liveB, _shadow, _ghost],
        ),
      );
      await tester.pumpAndSettle();

      // Deselect all, then re-select all via the Select-All toggle.
      await tester.tap(find.byKey(EventKeys.selectAllButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventKeys.selectAllButton));
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      final stage = _capturedStage(eventService);
      expect(stage.ids, {'uid-a', 'uid-b', 'shadow-uuid-1'});
    });

    testWidgets(
      'legacy group (no activeMemberIds): tombstone doc still hidden',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreate(
            prefs: prefs,
            members: [_live, _liveB, _shadow, _ghost],
            groupStream: Stream.value(_groupLegacy),
          ),
        );
        await tester.pumpAndSettle();

        // A tombstone renders as "Dana (former member)" (MemberNameResolver
      // suffix), so match by substring — exact 'Dana' finds nothing pre-fix too.
      expect(find.textContaining('Dana'), findsNothing);
        expect(find.text('Alice'), findsOneWidget);
      },
    );

    testWidgets(
      'fail-open: group doc never resolves → non-tombstone members shown and '
      'default-selected',
      (tester) async {
        final eventService = _MockEventService();
        final activityService = _MockGroupActivityService();
        _stubStageEvent(eventService);

        await tester.pumpWidget(
          _wrapCreateRouted(
            prefs: prefs,
            eventService: eventService,
            activityService: activityService,
            members: [_live, _liveB, _shadow, _ghost],
            // Never-emitting stream → group stays unresolved (fail-open).
            groupStream: Completer<Group>().future.asStream(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('Chad'), findsOneWidget);
        // Tombstone drop is member-doc-only, so it applies even unresolved.
        // A tombstone renders as "Dana (former member)" (MemberNameResolver
      // suffix), so match by substring — exact 'Dana' finds nothing pre-fix too.
      expect(find.textContaining('Dana'), findsNothing);

        await _fillAndSubmit(tester);

        final stage = _capturedStage(eventService);
        expect(stage.ids, {'uid-a', 'uid-b', 'shadow-uuid-1'});
      },
    );

    testWidgets(
      'late group resolve prunes a stale initial selection (the race pin)',
      (tester) async {
        final controller = StreamController<Group>();
        addTearDown(controller.close);

        // A malformed-ghost salvage: isTombstone came back false, so the doc
        // enters the initial selection before the group doc resolves.
        final notActive = GroupMember(
          id: 'not-active',
          groupId: 'g1',
          userId: 'not-active',
          displayName: 'Ghosty',
          role: 'MEMBER',
          joinedAt: DateTime(2026),
        );
        final lateGroup = Group(
          id: 'g1',
          name: 'G',
          inviteCode: 'ABC123',
          createdBy: 'uid-a',
          memberIds: const ['uid-a', 'not-active'],
          activeMemberIds: const ['uid-a'],
          createdAt: DateTime(2026),
        );

        final eventService = _MockEventService();
        final activityService = _MockGroupActivityService();
        _stubStageEvent(eventService);

        await tester.pumpWidget(
          _wrapCreateRouted(
            prefs: prefs,
            eventService: eventService,
            activityService: activityService,
            members: [_live, notActive],
            groupStream: controller.stream,
          ),
        );
        await tester.pump(); // members data
        await tester.pump(); // post-frame seed rebuild

        // Group not resolved yet → not-active row is visible + default-selected.
        expect(find.text('Ghosty'), findsOneWidget);

        // Group resolves; its activeMemberIds excludes 'not-active'.
        controller.add(lateGroup);
        await tester.pumpAndSettle();

        expect(find.text('Ghosty'), findsNothing);

        await _fillAndSubmit(tester);

        final stage = _capturedStage(eventService);
        expect(stage.ids, isNot(contains('not-active')));
        expect(stage.ids, {'uid-a'});
      },
    );

    testWidgets(
      'degenerate: filtering would empty the list → unfiltered fallback',
      (tester) async {
        await tester.pumpWidget(
          _wrapCreate(
            prefs: prefs,
            members: [_ghost],
            groupStream: Stream.value(_groupR5),
          ),
        );
        await tester.pumpAndSettle();

        // Filter would drop the only (tombstone) member — never render an empty
        // picker because of a filter; fall back to the unfiltered list. (Renders
        // as "Dana (former member)", so match by substring.) This guard is green
        // both pre- and post-fix: the fix must not over-filter to empty.
        expect(find.textContaining('Dana'), findsOneWidget);
      },
    );
  });
}

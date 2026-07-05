import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/settings_service.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Build a minimal [Expense] for testing.
Expense _makeExpense({
  required String id,
  required String tripId,
  required String payerParticipantId,
  required Decimal amount,
}) {
  return Expense(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    amount: amount,
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Build a minimal [Settlement] for testing.
Settlement _makeSettlement({
  required String id,
  required String tripId,
  required String payerParticipantId,
  required String recipientParticipantId,
  required Decimal amount,
}) {
  return Settlement(
    id: id,
    tripId: tripId,
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    amount: amount,
    settledAt: DateTime(2026, 1, 2),
    scope: 'event',
  );
}

/// Build a minimal [Event] for testing.
Event _makeEvent({
  required String id,
  required String groupId,
  List<String>? participantIds,
  Map<String, String>? participantNames,
}) {
  return Event(
    id: id,
    name: 'Event $id',
    type: EventType.trip,
    groupId: groupId,
    createdBy: 'uid-1',
    participantIds: participantIds ?? [],
    participantNames: participantNames ?? {},
    modules: const EventModules(),
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Pump the event loop multiple times to resolve cascaded stream providers.
///
/// StreamProvider.family with Stream.value delivers asynchronously.
/// Using Future.delayed(Duration.zero) yields to the event loop (not just
/// the microtask queue) which is required for Riverpod stream delivery
/// per Phase 5 convention (STATE.md).
Future<void> _pumpAsync() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // eventExpensesProvider isolation tests
  // ---------------------------------------------------------------------------

  group('eventExpensesProvider', () {
    const groupId = 'grp-1';
    const eventId = 'evt-1';
    const eventRef = (groupId: groupId, eventId: eventId);

    test('emits expense list from stream override', () async {
      final testExpenses = [
        _makeExpense(
          id: 'exp-1',
          tripId: eventId,
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('10.500'),
        ),
        _makeExpense(
          id: 'exp-2',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('5.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(testExpenses)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventExpensesProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncData<List<Expense>>>());
      expect(result.value, equals(testExpenses));
      expect(result.value, hasLength(2));
    });

    test('emits empty list when no expenses exist', () async {
      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(<Expense>[])),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventExpensesProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncData<List<Expense>>>());
      expect(result.value, isEmpty);
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<Expense>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(
            eventRef,
          ).overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      // Synchronous read before stream emits — must be loading
      final result = container.read(eventExpensesProvider(eventRef));
      expect(result, isA<AsyncLoading<List<Expense>>>());
    });

    test('isolates different event keys independently', () async {
      const ref1 = (groupId: groupId, eventId: 'evt-a');
      const ref2 = (groupId: groupId, eventId: 'evt-b');

      final expensesA = [
        _makeExpense(
          id: 'exp-a',
          tripId: 'evt-a',
          payerParticipantId: 'uid-1',
          amount: Decimal.parse('20.000'),
        ),
      ];
      final expensesB = [
        _makeExpense(
          id: 'exp-b1',
          tripId: 'evt-b',
          payerParticipantId: 'uid-2',
          amount: Decimal.parse('30.000'),
        ),
        _makeExpense(
          id: 'exp-b2',
          tripId: 'evt-b',
          payerParticipantId: 'uid-3',
          amount: Decimal.parse('10.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventExpensesProvider(
            ref1,
          ).overrideWith((_) => Stream.value(expensesA)),
          eventExpensesProvider(
            ref2,
          ).overrideWith((_) => Stream.value(expensesB)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventExpensesProvider(ref1),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        eventExpensesProvider(ref2),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final resultA = container.read(eventExpensesProvider(ref1));
      final resultB = container.read(eventExpensesProvider(ref2));

      expect(resultA.value, hasLength(1));
      expect(resultA.value!.first.id, equals('exp-a'));
      expect(resultB.value, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // groupEventsProvider isolation tests
  // ---------------------------------------------------------------------------

  group('groupEventsProvider', () {
    const groupId = 'grp-1';

    test('emits event list from stream override', () async {
      final testEvents = [
        _makeEvent(
          id: 'evt-1',
          groupId: groupId,
          participantIds: ['uid-1', 'uid-2'],
        ),
        _makeEvent(id: 'evt-2', groupId: groupId, participantIds: ['uid-1']),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(testEvents)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupEventsProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupEventsProvider(groupId));
      expect(result, isA<AsyncData<List<Event>>>());
      expect(result.value, hasLength(2));
      expect(result.value!.first.id, equals('evt-1'));
    });

    test('emits empty list when group has no events', () async {
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            groupId,
          ).overrideWith((_) => Stream.value(<Event>[])),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupEventsProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupEventsProvider(groupId));
      expect(result, isA<AsyncData<List<Event>>>());
      expect(result.value, isEmpty);
    });

    test('different group IDs use independent streams', () async {
      final eventsG1 = [_makeEvent(id: 'evt-g1', groupId: 'grp-1')];
      final eventsG2 = [
        _makeEvent(id: 'evt-g2a', groupId: 'grp-2'),
        _makeEvent(id: 'evt-g2b', groupId: 'grp-2'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(
            'grp-1',
          ).overrideWith((_) => Stream.value(eventsG1)),
          groupEventsProvider(
            'grp-2',
          ).overrideWith((_) => Stream.value(eventsG2)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupEventsProvider('grp-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        groupEventsProvider('grp-2'),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result1 = container.read(groupEventsProvider('grp-1'));
      final result2 = container.read(groupEventsProvider('grp-2'));

      expect(result1.value, hasLength(1));
      expect(result2.value, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // eventSettlementsProvider isolation tests
  // ---------------------------------------------------------------------------

  group('eventSettlementsProvider', () {
    const groupId = 'grp-1';
    const eventId = 'evt-1';
    const eventRef = (groupId: groupId, eventId: eventId);

    test('emits settlement list from stream override', () async {
      final testSettlements = [
        _makeSettlement(
          id: 's1',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('10.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(testSettlements)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncData<List<Settlement>>>());
      expect(result.value, hasLength(1));
      expect(result.value!.first.id, equals('s1'));
    });

    test('emits empty list when no settlements exist', () async {
      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(<Settlement>[])),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncData<List<Settlement>>>());
      expect(result.value, isEmpty);
    });

    test('multiple settlements for an event all delivered', () async {
      final testSettlements = [
        _makeSettlement(
          id: 's1',
          tripId: eventId,
          payerParticipantId: 'uid-2',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('5.000'),
        ),
        _makeSettlement(
          id: 's2',
          tripId: eventId,
          payerParticipantId: 'uid-3',
          recipientParticipantId: 'uid-1',
          amount: Decimal.parse('8.500'),
        ),
        _makeSettlement(
          id: 's3',
          tripId: eventId,
          payerParticipantId: 'uid-3',
          recipientParticipantId: 'uid-2',
          amount: Decimal.parse('2.000'),
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(testSettlements)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventSettlementsProvider(eventRef),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result.value, hasLength(3));
      expect(
        result.value!.map((s) => s.id).toList(),
        containsAll(['s1', 's2', 's3']),
      );
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<Settlement>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(eventSettlementsProvider(eventRef));
      expect(result, isA<AsyncLoading<List<Settlement>>>());
    });
  });

  // ---------------------------------------------------------------------------
  // groupDetailProvider isolation tests
  // ---------------------------------------------------------------------------

  group('groupDetailProvider', () {
    const groupId = 'grp-1';

    Group makeGroup({required String id, String name = 'Test Group'}) {
      return Group(
        id: id,
        name: name,
        inviteCode: 'ABC123',
        createdBy: 'uid-1',
        memberIds: const ['uid-1'],
        currency: 'OMR',
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('emits group from stream override', () async {
      final testGroup = makeGroup(id: groupId, name: 'Adventure Crew');

      final container = ProviderContainer(
        overrides: [
          groupDetailProvider(
            groupId,
          ).overrideWith((_) => Stream.value(testGroup)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupDetailProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupDetailProvider(groupId));
      expect(result, isA<AsyncData<Group?>>());
      expect(result.value?.name, equals('Adventure Crew'));
      expect(result.value?.id, equals(groupId));
    });

    test('emits null when group does not exist', () async {
      final container = ProviderContainer(
        overrides: [
          groupDetailProvider(
            groupId,
          ).overrideWith((_) => Stream<Group?>.value(null)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupDetailProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupDetailProvider(groupId));
      expect(result, isA<AsyncData<Group?>>());
      expect(result.value, isNull);
    });

    test('different group IDs are isolated', () async {
      final group1 = makeGroup(id: 'grp-a', name: 'Group A');
      final group2 = makeGroup(id: 'grp-b', name: 'Group B');

      final container = ProviderContainer(
        overrides: [
          groupDetailProvider(
            'grp-a',
          ).overrideWith((_) => Stream.value(group1)),
          groupDetailProvider(
            'grp-b',
          ).overrideWith((_) => Stream.value(group2)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupDetailProvider('grp-a'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        groupDetailProvider('grp-b'),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final resultA = container.read(groupDetailProvider('grp-a'));
      final resultB = container.read(groupDetailProvider('grp-b'));
      expect(resultA.value?.name, equals('Group A'));
      expect(resultB.value?.name, equals('Group B'));
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<Group?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          groupDetailProvider(groupId).overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(groupDetailProvider(groupId));
      expect(result, isA<AsyncLoading<Group?>>());
    });
  });

  // ---------------------------------------------------------------------------
  // groupMembersProvider isolation tests
  // ---------------------------------------------------------------------------

  group('groupMembersProvider', () {
    const groupId = 'grp-1';

    GroupMember makeMember({
      required String id,
      required String userId,
      required String displayName,
      String role = 'MEMBER',
    }) {
      return GroupMember(
        id: id,
        groupId: groupId,
        userId: userId,
        displayName: displayName,
        role: role,
        joinedAt: DateTime(2026, 1, 1),
      );
    }

    test('emits member list from stream override', () async {
      final testMembers = [
        makeMember(
          id: 'm1',
          userId: 'uid-1',
          displayName: 'Alice',
          role: 'CREATOR',
        ),
        makeMember(id: 'm2', userId: 'uid-2', displayName: 'Bob'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupMembersProvider(
            groupId,
          ).overrideWith((_) => Stream.value(testMembers)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupMembersProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupMembersProvider(groupId));
      expect(result, isA<AsyncData<List<GroupMember>>>());
      expect(result.value, hasLength(2));
      expect(result.value!.first.displayName, equals('Alice'));
      expect(result.value!.first.role, equals('CREATOR'));
    });

    test('emits empty list when group has no members', () async {
      final container = ProviderContainer(
        overrides: [
          groupMembersProvider(
            groupId,
          ).overrideWith((_) => Stream.value(<GroupMember>[])),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupMembersProvider(groupId),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(groupMembersProvider(groupId));
      expect(result, isA<AsyncData<List<GroupMember>>>());
      expect(result.value, isEmpty);
    });

    test('different group IDs use independent streams', () async {
      final membersG1 = [
        makeMember(id: 'm-g1', userId: 'uid-1', displayName: 'Alice'),
      ];
      final membersG2 = [
        makeMember(id: 'm-g2a', userId: 'uid-2', displayName: 'Bob'),
        makeMember(id: 'm-g2b', userId: 'uid-3', displayName: 'Charlie'),
      ];

      final container = ProviderContainer(
        overrides: [
          groupMembersProvider(
            'grp-1',
          ).overrideWith((_) => Stream.value(membersG1)),
          groupMembersProvider(
            'grp-2',
          ).overrideWith((_) => Stream.value(membersG2)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        groupMembersProvider('grp-1'),
        (_, _) {},
        fireImmediately: true,
      );
      container.listen(
        groupMembersProvider('grp-2'),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result1 = container.read(groupMembersProvider('grp-1'));
      final result2 = container.read(groupMembersProvider('grp-2'));
      expect(result1.value, hasLength(1));
      expect(result2.value, hasLength(2));
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<GroupMember>>.broadcast();

      final container = ProviderContainer(
        overrides: [
          groupMembersProvider(groupId).overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(groupMembersProvider(groupId));
      expect(result, isA<AsyncLoading<List<GroupMember>>>());
    });
  });

  // ---------------------------------------------------------------------------
  // userGroupsProvider isolation tests
  // ---------------------------------------------------------------------------

  group('userGroupsProvider', () {
    Group makeGroup(String id, String name) {
      return Group(
        id: id,
        name: name,
        inviteCode: 'ABC123',
        createdBy: 'uid-1',
        memberIds: const ['uid-1'],
        currency: 'OMR',
        createdAt: DateTime(2026, 1, 1),
      );
    }

    test('emits group list from stream override', () async {
      final testGroups = [
        makeGroup('grp-1', 'Beach Trip'),
        makeGroup('grp-2', 'Camping Squad'),
      ];

      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((_) => Stream.value(testGroups)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(userGroupsProvider, (_, _) {}, fireImmediately: true);
      await _pumpAsync();

      final result = container.read(userGroupsProvider);
      expect(result, isA<AsyncData<List<Group>>>());
      expect(result.value, hasLength(2));
      expect(result.value!.first.name, equals('Beach Trip'));
    });

    test('emits empty list when user has no groups', () async {
      final container = ProviderContainer(
        overrides: [
          userGroupsProvider.overrideWith((_) => Stream.value(<Group>[])),
        ],
      );
      addTearDown(container.dispose);

      container.listen(userGroupsProvider, (_, _) {}, fireImmediately: true);
      await _pumpAsync();

      final result = container.read(userGroupsProvider);
      expect(result, isA<AsyncData<List<Group>>>());
      expect(result.value, isEmpty);
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<List<Group>>.broadcast();

      final container = ProviderContainer(
        overrides: [userGroupsProvider.overrideWith((_) => controller.stream)],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(userGroupsProvider);
      expect(result, isA<AsyncLoading<List<Group>>>());
    });

    test('delivers multiple sequential updates from stream', () async {
      final controller = StreamController<List<Group>>();
      final updatesReceived = <int>[];

      final container = ProviderContainer(
        overrides: [userGroupsProvider.overrideWith((_) => controller.stream)],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      container.listen(userGroupsProvider, (_, next) {
        if (next is AsyncData<List<Group>>) {
          updatesReceived.add(next.value.length);
        }
      }, fireImmediately: true);

      controller.add([makeGroup('grp-1', 'Group A')]);
      await _pumpAsync();

      controller.add([
        makeGroup('grp-1', 'Group A'),
        makeGroup('grp-2', 'Group B'),
      ]);
      await _pumpAsync();

      expect(updatesReceived, contains(1));
      expect(updatesReceived, contains(2));
    });
  });

  // ---------------------------------------------------------------------------
  // SettingsNotifier tests
  // ---------------------------------------------------------------------------

  group('SettingsNotifier', () {
    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('initial state has default AppSettings', () async {
      final container = await makeContainer();
      final settings = container.read(settingsProvider);
      expect(settings.deviceName, equals(''));
      expect(settings.currencyCode, equals('OMR'));
      expect(settings.languageCode, equals('en'));
      // D5a reverted (#900): default follows system now the dark pass shipped.
      expect(settings.themeMode, equals(AppThemeMode.system));
      expect(settings.pushNotificationsEnabled, isFalse);
    });

    test('setDeviceName updates deviceName in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDeviceName('Alice');
      expect(container.read(settingsProvider).deviceName, equals('Alice'));
    });

    test('setCurrency updates currencyCode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCurrency('USD');
      expect(container.read(settingsProvider).currencyCode, equals('USD'));
    });

    test('setLanguage updates languageCode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setLanguage('ar');
      expect(container.read(settingsProvider).languageCode, equals('ar'));
    });

    test('setThemeMode updates themeMode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setThemeMode(AppThemeMode.dark);
      expect(
        container.read(settingsProvider).themeMode,
        equals(AppThemeMode.dark),
      );
    });

    test(
      'setPushNotificationsEnabled updates pushNotificationsEnabled',
      () async {
        final container = await makeContainer();
        final notifier = container.read(settingsProvider.notifier);
        await notifier.setPushNotificationsEnabled(true);
        expect(
          container.read(settingsProvider).pushNotificationsEnabled,
          isTrue,
        );
      },
    );

    test('settingsServiceProvider returns SettingsService instance', () async {
      final container = await makeContainer();
      final service = container.read(settingsServiceProvider);
      expect(service, isA<SettingsService>());
    });

    test(
      'loadSettings reads stored deviceName from SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({'settings_device_name': 'Bob'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final settings = container.read(settingsProvider);
        expect(settings.deviceName, equals('Bob'));
      },
    );

    test('AppSettings.theme returns ThemeMode.dark for dark mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.dark);
      expect(settings.theme, equals(ThemeMode.dark));
    });

    test('AppSettings.theme returns ThemeMode.light for light mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.light);
      expect(settings.theme, equals(ThemeMode.light));
    });

    test('AppSettings.theme returns ThemeMode.system for system mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.system);
      expect(settings.theme, equals(ThemeMode.system));
    });
  });

  // ---------------------------------------------------------------------------
  // eventDetailProvider isolation tests
  // ---------------------------------------------------------------------------

  group('eventDetailProvider', () {
    const groupId = 'grp-1';
    const eventId = 'evt-1';
    const params = (groupId: groupId, eventId: eventId);

    test('emits event from stream override', () async {
      final testEvent = _makeEvent(id: eventId, groupId: groupId);

      final container = ProviderContainer(
        overrides: [
          eventDetailProvider(
            params,
          ).overrideWith((_) => Stream.value(testEvent)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventDetailProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventDetailProvider(params));
      expect(result, isA<AsyncData<Event?>>());
      expect(result.value?.id, equals(eventId));
    });

    test('emits null when event does not exist', () async {
      final container = ProviderContainer(
        overrides: [
          eventDetailProvider(
            params,
          ).overrideWith((_) => Stream<Event?>.value(null)),
        ],
      );
      addTearDown(container.dispose);

      container.listen(
        eventDetailProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      await _pumpAsync();

      final result = container.read(eventDetailProvider(params));
      expect(result, isA<AsyncData<Event?>>());
      expect(result.value, isNull);
    });

    test('returns AsyncLoading before stream emits', () {
      final controller = StreamController<Event?>.broadcast();

      final container = ProviderContainer(
        overrides: [
          eventDetailProvider(params).overrideWith((_) => controller.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(controller.close);

      final result = container.read(eventDetailProvider(params));
      expect(result, isA<AsyncLoading<Event?>>());
    });
  });
}

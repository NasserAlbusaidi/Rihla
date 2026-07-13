import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settings_screen.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

/// #363 — the per-group simplify-debts toggle.
///
/// Spec: docs/plans/2026-07-13-363-simplify-debts-toggle.md §6.3:
/// - `simplifyDebts: false` renders the DIRECT legs and the
///   settleUpDirectPayments intro copy;
/// - `true`/absent renders the optimizer output and the existing
///   settleUpOptimizedPayments copy;
/// - OFF zero-state renders settleUpNoDirectPayments;
/// - multi-bucket OFF renders the currencyExplainerBodyDirect variant;
/// - retained-screen propagation: the group stream emitting the SAME id with
///   the flag flipped updates the rendered mode (Group.== is id-only, so this
///   pins that no equality layer swallows the emission);
/// - the settings switch writes exactly {simplifyDebts, updatedAt} and is
///   creator-only.

const _groupId = 'grp-363';

Group _group({bool simplifyDebts = true}) => Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST363',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob', 'uid-charlie', 'uid-dana'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
  simplifyDebts: simplifyDebts,
);

const _names = <String, String>{
  'uid-alice': 'Alice',
  'uid-bob': 'Bob',
  'uid-charlie': 'Charlie',
  'uid-dana': 'Dana',
};

UserBalance _balance(String uid, String net) => UserBalance(
  participantId: uid,
  displayName: _names[uid],
  totalPaid: Decimal.zero,
  totalOwed: Decimal.zero,
  netBalance: Decimal.parse(net),
);

/// The mode-distinguishing bucket: the optimizer concentrates into 3 legs
/// (charlie→alice 9, dana→alice 1, dana→bob 5) while the direct fan-out emits
/// 4 (charlie→alice 6, charlie→bob 3, dana→alice 4, dana→bob 2).
final _fourWayBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      _balance('uid-alice', '10.000'),
      _balance('uid-bob', '5.000'),
      _balance('uid-charlie', '-9.000'),
      _balance('uid-dana', '-6.000'),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('15.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: _names,
  memberRawNames: _names,
);

final _settledBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [_balance('uid-alice', '0.000'), _balance('uid-bob', '0.000')],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: _names,
  memberRawNames: _names,
);

final _twoBucketBalances = (
  balances: <String, List<UserBalance>>{
    'OMR': [_balance('uid-alice', '10.000'), _balance('uid-bob', '-10.000')],
    'USD': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse('20.00'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse('-20.00'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{
    'OMR': Decimal.parse('10.000'),
    'USD': Decimal.parse('20.00'),
  },
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: _names,
  memberRawNames: _names,
);

Widget _wrapSettleUp({
  required Stream<Group?> groupStream,
  required AsyncValue<GroupBalances> balancesAsync,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => groupStream),
      groupBalancesProvider(_groupId).overrideWith((_) => balancesAsync),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Event>[])),
      currentUserIdProvider.overrideWithValue('uid-charlie'),
      ...extraOverrides,
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupSettleUpScreen(groupId: _groupId),
      ),
    ),
  );
}

void main() {
  final en = AppLocalizationsEn();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    try {
      await Firebase.initializeApp();
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
    }
  });

  group('#363 settle-up mode swap (group screen)', () {
    testWidgets(
      'simplifyDebts: false renders the direct fan-out legs and the '
      'direct intro copy',
      (tester) async {
        await tester.pumpWidget(
          _wrapSettleUp(
            groupStream: Stream.value(_group(simplifyDebts: false)),
            balancesAsync: AsyncValue.data(_fourWayBalances),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GroupSettlementTile), findsNWidgets(4));
        expect(
          find.text(en.settleUpDirectPayments('Test Crew')),
          findsOneWidget,
        );
        expect(
          find.text(en.settleUpOptimizedPayments('Test Crew')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'simplifyDebts absent (model default true) renders the optimizer '
      'legs and the optimized intro copy',
      (tester) async {
        await tester.pumpWidget(
          _wrapSettleUp(
            groupStream: Stream.value(_group()),
            balancesAsync: AsyncValue.data(_fourWayBalances),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GroupSettlementTile), findsNWidgets(3));
        expect(
          find.text(en.settleUpOptimizedPayments('Test Crew')),
          findsOneWidget,
        );
        expect(find.text(en.settleUpDirectPayments('Test Crew')), findsNothing);
      },
    );

    testWidgets('OFF zero-state renders settleUpNoDirectPayments', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapSettleUp(
          groupStream: Stream.value(_group(simplifyDebts: false)),
          balancesAsync: AsyncValue.data(_settledBalances),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupSettlementTile), findsNothing);
      expect(
        find.text(en.settleUpNoDirectPayments('Test Crew')),
        findsOneWidget,
      );
      expect(
        find.text(en.settleUpNoOptimizedPayments('Test Crew')),
        findsNothing,
      );
    });

    testWidgets('multi-bucket OFF renders the direct explainer variant', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _wrapSettleUp(
          groupStream: Stream.value(_group(simplifyDebts: false)),
          balancesAsync: AsyncValue.data(_twoBucketBalances),
          extraOverrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.currencyExplainerCard), findsOneWidget);
      expect(find.text(en.currencyExplainerBodyDirect), findsOneWidget);
      expect(find.text(en.currencyExplainerBody), findsNothing);
    });

    testWidgets(
      'retained screen: the group stream flipping the flag (same id — '
      'Group.== is id-only) swaps the rendered mode in place',
      (tester) async {
        final controller = StreamController<Group?>();
        addTearDown(controller.close);

        await tester.pumpWidget(
          _wrapSettleUp(
            groupStream: controller.stream,
            balancesAsync: AsyncValue.data(_fourWayBalances),
          ),
        );
        controller.add(_group());
        await tester.pumpAndSettle();

        expect(find.byType(GroupSettlementTile), findsNWidgets(3));
        expect(
          find.text(en.settleUpOptimizedPayments('Test Crew')),
          findsOneWidget,
        );

        controller.add(_group(simplifyDebts: false));
        await tester.pumpAndSettle();

        expect(find.byType(GroupSettlementTile), findsNWidgets(4));
        expect(
          find.text(en.settleUpDirectPayments('Test Crew')),
          findsOneWidget,
        );
        expect(
          find.text(en.settleUpOptimizedPayments('Test Crew')),
          findsNothing,
        );
      },
    );
  });

  group('#363 settle-up mode swap (event screen)', () {
    // The toggle governs BOTH scopes (spec §4) — pin the event screen's own
    // bucket-construction call site with the same distinguishing nets
    // (alice +10, bob +5, charlie −9, dana −6 → optimizer 3 legs, direct 4).
    const eventId = 'evt-363';
    const eventRef = (groupId: _groupId, eventId: eventId);

    final event = Event(
      id: eventId,
      groupId: _groupId,
      name: 'Beach Trip',
      type: EventType.trip,
      createdBy: 'uid-alice',
      participantIds: const ['uid-alice', 'uid-bob', 'uid-charlie', 'uid-dana'],
      participantNames: _names,
      modules: const EventModules(),
      createdAt: DateTime(2026, 5, 16),
    );

    final expenses = [
      Expense(
        id: 'e1',
        tripId: eventId,
        payerParticipantId: 'uid-alice',
        amount: Decimal.parse('10.000'),
        description: 'Dinner',
        scope: ExpenseScope.global,
        splitMode: SplitMode.exact,
        splitDistribution: {
          'uid-charlie': Decimal.parse('9.000'),
          'uid-dana': Decimal.parse('1.000'),
        },
        createdAt: DateTime(2026, 5, 16),
        createdBy: 'uid-alice',
      ),
      Expense(
        id: 'e2',
        tripId: eventId,
        payerParticipantId: 'uid-bob',
        amount: Decimal.parse('5.000'),
        description: 'Taxi',
        scope: ExpenseScope.global,
        splitMode: SplitMode.exact,
        splitDistribution: {'uid-dana': Decimal.parse('5.000')},
        createdAt: DateTime(2026, 5, 17),
        createdBy: 'uid-bob',
      ),
    ];

    final members = [
      for (final e in _names.entries)
        GroupMember(
          id: e.key,
          groupId: _groupId,
          userId: e.key,
          displayName: e.value,
          role: e.key == 'uid-alice' ? 'CREATOR' : 'MEMBER',
          joinedAt: DateTime(2026, 1, 1),
        ),
    ];

    testWidgets(
      'simplifyDebts: false swaps the EVENT screen to the direct fan-out',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              currentUserIdProvider.overrideWithValue('uid-charlie'),
              eventDetailProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(event)),
              eventExpensesProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(expenses)),
              eventSettlementsProvider(
                eventRef,
              ).overrideWith((_) => Stream.value(const <Settlement>[])),
              groupMembersProvider(
                _groupId,
              ).overrideWith((_) => Stream.value(members)),
              groupDetailProvider(
                _groupId,
              ).overrideWith((_) => Stream.value(_group(simplifyDebts: false))),
            ],
            child: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const SettleUpScreen(groupId: _groupId, eventId: eventId),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GroupSettlementTile), findsNWidgets(4));
        expect(
          find.text(en.settleUpDirectPayments('Beach Trip')),
          findsOneWidget,
        );
        expect(
          find.text(en.settleUpOptimizedPayments('Beach Trip')),
          findsNothing,
        );
      },
    );
  });

  group('#363 settings switch', () {
    final members = [
      GroupMember(
        id: 'uid-alice',
        groupId: _groupId,
        userId: 'uid-alice',
        displayName: 'Alice',
        role: 'CREATOR',
        joinedAt: DateTime(2026, 1, 1),
      ),
      GroupMember(
        id: 'uid-bob',
        groupId: _groupId,
        userId: 'uid-bob',
        displayName: 'Bob',
        role: 'MEMBER',
        joinedAt: DateTime(2026, 1, 2),
      ),
    ];

    Widget wrapSettings({
      required String viewerUid,
      required FakeFirebaseFirestore fakeDb,
      required SharedPreferences prefs,
    }) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(viewerUid),
          groupDetailProvider(
            _groupId,
          ).overrideWith((_) => Stream.value(_group())),
          groupMembersProvider(
            _groupId,
          ).overrideWith((_) => Stream.value(members)),
          groupBalancesProvider(
            _groupId,
          ).overrideWith((_) => AsyncValue.data(_settledBalances)),
          groupServiceProvider.overrideWith(
            (ref) => GroupService.withFirestore(ref, fakeDb),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupSettingsScreen(groupId: _groupId),
        ),
      );
    }

    testWidgets(
      'creator toggle writes exactly {simplifyDebts, updatedAt} via '
      'setSimplifyDebts',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final fakeDb = FakeFirebaseFirestore();
        await fakeDb.doc('groups/$_groupId').set({
          'name': 'Test Crew',
          'createdBy': 'uid-alice',
        });

        await tester.pumpWidget(
          wrapSettings(viewerUid: 'uid-alice', fakeDb: fakeDb, prefs: prefs),
        );
        await tester.pumpAndSettle();

        final switchFinder = find.byKey(GroupKeys.settingsSimplifyDebtsSwitch);
        await tester.ensureVisible(switchFinder);
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<Switch>(switchFinder).value, isTrue);
        expect(find.text(en.groupSimplifyDebtsOnSubtitle), findsOneWidget);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        final doc = await fakeDb.doc('groups/$_groupId').get();
        final data = doc.data()!;
        expect(data['simplifyDebts'], isFalse);
        expect(data['updatedAt'], isNotNull);
        // The 2-key contract: nothing else was touched (no glyph wipe — the
        // reason setSimplifyDebts is NOT updateGroupIdentity).
        expect(data.keys.toSet(), {
          'name',
          'createdBy',
          'simplifyDebts',
          'updatedAt',
        });
      },
    );

    testWidgets('non-creator sees no simplify-debts switch', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        wrapSettings(
          viewerUid: 'uid-bob',
          fakeDb: FakeFirebaseFirestore(),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.settingsSimplifyDebtsSwitch),
        findsNothing,
      );
    });
  });
}

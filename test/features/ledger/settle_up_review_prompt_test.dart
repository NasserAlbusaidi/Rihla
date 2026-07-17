import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/review_prompt.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/record_settlement_result.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/features/ledger/services/settlement_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../../helpers/recording_functions_service.dart';

// #1263: a CLEAN recorded settle-up is the natural moment for the store
// review ask — exactly one fire-and-forget ReviewPrompt call per completed
// single-tile record. An #1129 idempotent replay (alreadyRecorded) must NOT
// prompt: the user already had their moment for this exact payment (same
// reasoning as the #367 nudge gate).

class _SpyReviewPrompt extends ReviewPrompt {
  _SpyReviewPrompt(super.ref);
  int calls = 0;
  @override
  Future<void> maybeRequest() async => calls++;
}

class _MockInAppReview extends Mock implements InAppReview {}

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

void main() {
  const groupId = 'group-1';
  const eventId = 'event-1';
  const eventRef = (groupId: groupId, eventId: eventId);

  late SharedPreferences prefs;
  late RecordingFunctionsService recordingFunctions;
  _SpyReviewPrompt? spy;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recordingFunctions = RecordingFunctionsService();
    spy = null;
  });

  final event = Event(
    id: eventId,
    groupId: groupId,
    name: 'Beach Trip',
    type: EventType.trip,
    createdBy: 'alice',
    participantIds: const ['alice', 'bob'],
    participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 5, 16),
  );

  final expenses = [
    Expense(
      id: 'expense-1',
      tripId: eventId,
      payerParticipantId: 'alice',
      amount: Decimal.parse('20.000'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      splitMode: SplitMode.equally,
      createdAt: DateTime(2026, 5, 16),
      createdBy: 'alice',
    ),
  ];

  Widget buildScreen(
    FakeFirebaseFirestore fakeDb, {
    RecordingFunctionsService? functions,
    ValueNotifier<bool>? showScreen,
    // #1277: lets a test wire the REAL ReviewPrompt (+ a mocked InAppReview)
    // instead of the call-counting spy below, so it can assert on the actual
    // cooldown-prefs write, not just an invocation count.
    List<Override> extraOverrides = const [],
  }) {
    final overrides = [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue('bob'),
      eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((ref) => Stream.value(const <Settlement>[])),
      groupMembersProvider(groupId).overrideWith((ref) => Stream.value(const [])),
      groupDetailProvider(groupId).overrideWith(
        (ref) => Stream.value(
          Group(
            id: groupId,
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
          functionsService: functions ?? recordingFunctions,
        ),
      ),
      groupActivityServiceProvider.overrideWithValue(
        GroupActivityService.withFirestore(fakeDb),
      ),
      reviewPromptProvider.overrideWith((ref) => spy = _SpyReviewPrompt(ref)),
      ...extraOverrides,
    ];

    const screen = SettleUpScreen(groupId: groupId, eventId: eventId);
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // A swappable home lets the disposal test unmount ONLY the screen —
        // the ProviderScope container survives, as it does in real navigation.
        home: showScreen == null
            ? screen
            : ValueListenableBuilder<bool>(
                valueListenable: showScreen,
                builder: (_, visible, _) =>
                    visible ? screen : const SizedBox.shrink(),
              ),
      ),
    );
  }

  Future<void> recordOnce(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
    await tester.pumpAndSettle();
    // #367: the debtor recording their own payment gets the WhatsApp-notify
    // nudge sheet first — dismiss it; the review ask fires after the nudge.
    final notifySheet = find.byKey(GroupKeys.settleNotifySheet);
    if (notifySheet.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(GroupKeys.settleNotifyNotNowButton));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('#1263: a clean single-tile record asks for a review once', (
    tester,
  ) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await recordOnce(tester);

    expect(spy?.calls ?? 0, 1);
  });

  testWidgets('#1263: an alreadyRecorded (#1129) replay never prompts', (
    tester,
  ) async {
    recordingFunctions.result = const RecordSettlementResult(
      alreadyRecorded: true,
      eventScopeWrites: 0,
      groupScopeWrites: 0,
      shouldBumpLedgerRevision: false,
      settledAt: '2026-07-11T12:00:00.000Z',
    );
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(buildScreen(fakeDb));
    await tester.pumpAndSettle();

    await recordOnce(tester);

    expect(spy?.calls ?? 0, 0);
  });

  testWidgets(
    '#1263: screen disposed mid-record — the ask still fires and nothing '
    'reads ref on the disposed element',
    (tester) async {
      final gated = GatedRecordingFunctionsService();
      final showScreen = ValueNotifier<bool>(true);
      addTearDown(showScreen.dispose);
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(
        buildScreen(fakeDb, functions: gated, showScreen: showScreen),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
      // The callable is gated: the record continuation is parked at the
      // in-flight write. Let the sheet finish closing, then dispose ONLY the
      // screen (the user navigated away mid-write; the container survives).
      await tester.pumpAndSettle();
      showScreen.value = false;
      await tester.pumpAndSettle();

      gated.gate.complete();
      await tester.pumpAndSettle();

      // The settle WAS recorded — the app-level review ask must survive the
      // screen's disposal (the #104/#412 capture discipline), not throw a
      // ref-after-dispose StateError.
      expect(gated.recordSettlementCalls, hasLength(1));
      expect(spy?.calls ?? 0, 1);
    },
  );

  // #1277: an ACCEPTED WhatsApp nudge backgrounds the app (external launch or
  // the share-sheet fallback) — Play/StoreKit silently no-op while
  // backgrounded, but ReviewPrompt.maybeRequest still burns the 14-day
  // cooldown at review_prompt.dart:60 before the no-op request. These tests
  // wire the REAL ReviewPrompt (not the call-counting spy) against a mocked
  // InAppReview so a cooldown-prefs write is directly observable.
  group('#1277 review-ask deferred on WhatsApp hand-off', () {
    late _MockInAppReview review;

    setUp(() {
      review = _MockInAppReview();
      when(review.isAvailable).thenAnswer((_) async => true);
      when(review.requestReview).thenAnswer((_) async {});
    });

    testWidgets(
      'accepted nudge hand-off skips the review ask and does not burn the '
      'cooldown',
      (tester) async {
        registerFallbackValue(const LaunchOptions());
        final launcher = _MockUrlLauncher();
        UrlLauncherPlatform.instance = launcher;
        when(() => launcher.canLaunch(any())).thenAnswer((_) async => true);
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);

        final fakeDb = FakeFirebaseFirestore();
        await tester.pumpWidget(
          buildScreen(
            fakeDb,
            extraOverrides: [
              inAppReviewProvider.overrideWithValue(review),
              reviewPromptProvider.overrideWith(
                (ref) => ReviewPrompt(ref, emulatorRun: false),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(GroupKeys.settleUpRecordPaymentButton),
        );
        await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GroupKeys.markAsPaidButton));
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.settleNotifySheet), findsOneWidget);
        await tester.tap(find.byKey(GroupKeys.settleNotifyWhatsAppButton));
        await tester.pumpAndSettle();

        verifyNever(review.requestReview);
        expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNull);
      },
    );

    testWidgets('a declined nudge still asks for a review', (tester) async {
      final fakeDb = FakeFirebaseFirestore();
      await tester.pumpWidget(
        buildScreen(
          fakeDb,
          extraOverrides: [
            inAppReviewProvider.overrideWithValue(review),
            reviewPromptProvider.overrideWith(
              (ref) => ReviewPrompt(ref, emulatorRun: false),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // recordOnce dismisses the nudge sheet via "Not now" when it appears.
      await recordOnce(tester);

      verify(review.requestReview).called(1);
      expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNotNull);
    });
  });
}

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/ledger/models/correct_settlement_result.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #753/#889 — the group settle-up screen corrects a DECOMPOSED settle-up by
// reversing ALL its tagged docs atomically via the server-authoritative
// `correctLogicalSettleUp` callable (replaces the deleted client
// `SettlementCorrectionService` WriteBatch). The logical correct button on the
// regrouped history row drives it; idempotency guards (a fully-marked/
// bounded-legacy-corrected row hides the button + an in-flight guard) prevent
// double-reverse.

class _MockFunctionsService extends Mock implements FirebaseFunctionsService {}

const _groupId = 'grp-1';
const _note = 'Correction of a recorded payment'; // en sentinel

Group _group() => Group(
      id: _groupId,
      name: 'Test Crew',
      inviteCode: 'TST123',
      createdBy: 'uid-alice',
      memberIds: const ['uid-alice', 'uid-bob'],
      currency: 'OMR',
      createdAt: DateTime(2026, 1, 1),
    );

final _event1 = Event(
  id: 'event-1',
  name: 'Camping Weekend',
  type: EventType.camping,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

UserBalance _bal(String id, String name, String net) => UserBalance(
      participantId: id,
      displayName: name,
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.parse(net),
    );

// Settled group (zero balances) so history is the only thing on screen.
final _settled = (
  balances: <String, List<UserBalance>>{
    'OMR': [_bal('uid-alice', 'Alice', '0'), _bal('uid-bob', 'Bob', '0')],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.zero},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

Settlement _taggedOriginal({String id = 'evt-set-1'}) => Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'uid-bob',
      recipientParticipantId: 'uid-alice',
      amount: Decimal.parse('7.750'),
      settledAt: DateTime(2026, 4, 1),
      payerName: 'Bob',
      recipientName: 'Alice',
      currency: 'OMR',
      groupSettleUpId: 'su-1',
    );

// A #889 MARKED reverse — carries `correctionOfSettlementId` pointing at the
// original it corrects. This is the actual write-affordance signal; a
// note-only reverse (below) is the pre-#889 migration case.
Settlement _markedReverse({String originalId = 'evt-set-1'}) => Settlement(
      id: '$originalId-rev',
      tripId: 'event-1',
      payerParticipantId: 'uid-alice',
      recipientParticipantId: 'uid-bob',
      amount: Decimal.parse('7.750'),
      settledAt: DateTime(2026, 4, 2),
      payerName: 'Alice',
      recipientName: 'Bob',
      currency: 'OMR',
      note: _note,
      groupSettleUpId: 'su-1',
      correctionOfSettlementId: originalId,
    );

// A pre-#889 bounded-legacy reverse — sentinel note, NO marker. The client
// affordance must still hide the button via the bounded-legacy exact-inverse
// guard (the migration case: these rows predate the marker and can never
// carry one).
Settlement _legacyNoteOnlyReverse() => Settlement(
      id: 'evt-set-1-rev',
      tripId: 'event-1',
      payerParticipantId: 'uid-alice',
      recipientParticipantId: 'uid-bob',
      amount: Decimal.parse('7.750'),
      settledAt: DateTime(2026, 4, 2),
      payerName: 'Alice',
      recipientName: 'Bob',
      currency: 'OMR',
      note: _note,
      groupSettleUpId: 'su-1',
    );

CorrectSettlementResult _result({bool shouldBumpLedgerRevision = true}) =>
    CorrectSettlementResult(
      eventScopeWrites: 1,
      groupScopeWrites: 0,
      repaired: false,
      noop: false,
      shouldBumpLedgerRevision: shouldBumpLedgerRevision,
    );

Widget _wrap({
  required List<Settlement> tagged,
  required FirebaseFunctionsService functionsService,
  String currentUid = 'uid-alice',
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
      groupBalancesProvider(_groupId)
          .overrideWith((_) => AsyncValue.data(_settled)),
      groupSettlementsProvider(_groupId)
          .overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value([_event1])),
      groupTaggedEventSettlementsProvider(_groupId).overrideWithValue(tagged),
      firebaseFunctionsServiceProvider.overrideWithValue(functionsService),
      currentUserIdProvider.overrideWithValue(currentUid),
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
  setUpAll(() {
    registerFallbackValue('');
  });

  testWidgets(
    'tapping the logical correct invokes correctLogicalSettleUp + bumps '
    'revision on shouldBumpLedgerRevision',
    (tester) async {
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenAnswer((_) async => _result());

      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], functionsService: functionsService),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      verify(
        () => functionsService.correctLogicalSettleUp(
          groupId: _groupId,
          groupSettleUpId: 'su-1',
          correctionNote: l10n.settleUpCorrectionNote,
        ),
      ).called(1);
      // shouldBumpLedgerRevision: true (event-scope reverse) → home one-shot
      // must refresh.
      expect(container.read(ledgerRevisionProvider), 1);
      expect(find.text('Settlement recorded.'), findsOneWidget);
    },
  );

  testWidgets(
    'a group-only-noop result does NOT bump ledgerRevisionProvider',
    (tester) async {
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenAnswer((_) async => _result(shouldBumpLedgerRevision: false));

      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], functionsService: functionsService),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      expect(container.read(ledgerRevisionProvider), 0);
    },
  );

  testWidgets(
    'a FULLY MARKED settle-up hides the logical correct button '
    '(#889 marker affordance)',
    (tester) async {
      final functionsService = _MockFunctionsService();
      await tester.pumpWidget(
        _wrap(
          tagged: [_taggedOriginal(), _markedReverse()],
          functionsService: functionsService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.settleUpCorrectButton),
        findsNothing,
        reason:
            'a valid marked reverse hides the write affordance even though '
            'the display accent is note-based',
      );
    },
  );

  testWidgets(
    'a pre-#889 bounded-legacy note-only correction still hides the button '
    '(migration case)',
    (tester) async {
      final functionsService = _MockFunctionsService();
      await tester.pumpWidget(
        _wrap(
          tagged: [_taggedOriginal(), _legacyNoteOnlyReverse()],
          functionsService: functionsService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(GroupKeys.settleUpCorrectButton),
        findsNothing,
        reason:
            'the deterministic-id existence check can never find a pre-#889 '
            'uuid-id reverse — the bounded-legacy content guard is the ONLY '
            'detector, and must still hide the affordance',
      );
    },
  );

  testWidgets(
    'a PARTIALLY marked settle-up (2 originals, 1 reversed) keeps the '
    'correct button available so the callable can repair the remainder',
    (tester) async {
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenAnswer((_) async => _result());

      final originalA = _taggedOriginal(id: 'evt-set-a');
      final originalB = _taggedOriginal(id: 'evt-set-b');
      final reverseOfA = _markedReverse(originalId: 'evt-set-a');

      await tester.pumpWidget(
        _wrap(
          tagged: [originalA, originalB, reverseOfA],
          functionsService: functionsService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsOneWidget);

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      // The callable — not the client — decides which originals still need a
      // reverse; the client only decides whether the action is available.
      verify(
        () => functionsService.correctLogicalSettleUp(
          groupId: _groupId,
          groupSettleUpId: 'su-1',
          correctionNote: any(named: 'correctionNote'),
        ),
      ).called(1);
    },
  );

  testWidgets(
    'a double-tap correction invokes the callable ONCE (in-flight guard)',
    (tester) async {
      final gate = Completer<CorrectSettlementResult>();
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenAnswer((_) => gate.future);

      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], functionsService: functionsService),
      );
      await tester.pumpAndSettle();

      // First correction — holds in-flight on the open gate (awaited).
      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Record correction'));
      await tester.pump();
      verify(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).called(1);

      // Second correction while the first is still pending → guarded no-op.
      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Record correction'));
      await tester.pump();
      verifyNever(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      );

      gate.complete(_result());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'an offline/failed logical correction shows the write-error copy and '
    'writes nothing — never the queued/will-sync success copy',
    (tester) async {
      final functionsService = _MockFunctionsService();
      when(
        () => functionsService.correctLogicalSettleUp(
          groupId: any(named: 'groupId'),
          groupSettleUpId: any(named: 'groupSettleUpId'),
          correctionNote: any(named: 'correctionNote'),
        ),
      ).thenThrow(Exception('offline'));

      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], functionsService: functionsService),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupSettleUpScreen)),
      );

      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.settleUpRecordFailedGeneric), findsOneWidget);
      expect(find.text(l10n.settleUpRecordedWillSync), findsNothing);
      expect(find.text(l10n.settleUpRecorded), findsNothing);
      expect(container.read(ledgerRevisionProvider), 0);
    },
  );
}

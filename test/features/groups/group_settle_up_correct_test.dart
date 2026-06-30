import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/services/settlement_correction_service.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #753 — the group settle-up screen corrects a DECOMPOSED settle-up by reversing
// ALL its tagged docs atomically via SettlementCorrectionService. The logical
// correct button on the regrouped history row drives it; idempotency guards
// (corrected-row hides the button + an in-flight guard) prevent double-reverse.

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

Settlement _taggedOriginal() => Settlement(
      id: 'evt-set-1',
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

Settlement _taggedReverse() => Settlement(
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

class _RecordingCorrectionService extends SettlementCorrectionService {
  _RecordingCorrectionService({this.gate})
      : super.withFirestore(FakeFirebaseFirestore());

  /// When set, the returned future stays pending until completed — lets a test
  /// hold a correction "in flight" to exercise the double-tap guard.
  final Completer<void>? gate;

  final calls = <({
    String groupSettleUpId,
    List<Settlement> originals,
    String correctedBy,
  })>[];

  @override
  Future<void> reverseLogicalSettleUp({
    required String groupId,
    required String groupSettleUpId,
    required List<Settlement> originals,
    required String correctedBy,
    required String correctionNote,
  }) {
    calls.add((
      groupSettleUpId: groupSettleUpId,
      originals: originals,
      correctedBy: correctedBy,
    ));
    return gate?.future ?? Future<void>.value();
  }
}

Widget _wrap({
  required List<Settlement> tagged,
  required SettlementCorrectionService correction,
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
      settlementCorrectionServiceProvider.overrideWithValue(correction),
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
  testWidgets(
    'tapping the logical correct reverses the whole settle-up + bumps revision',
    (tester) async {
      final correction = _RecordingCorrectionService();
      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], correction: correction),
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

      expect(correction.calls, hasLength(1));
      final call = correction.calls.single;
      expect(call.groupSettleUpId, 'su-1');
      expect(call.originals.map((s) => s.id), ['evt-set-1']);
      expect(call.correctedBy, 'uid-alice');
      // The reverse includes an EVENT settlement → home one-shot must refresh.
      expect(container.read(ledgerRevisionProvider), 1);
      expect(find.text('Settlement recorded.'), findsOneWidget);
    },
  );

  testWidgets(
    'an already-corrected settle-up hides the logical correct button',
    (tester) async {
      final correction = _RecordingCorrectionService();
      await tester.pumpWidget(
        _wrap(
          tagged: [_taggedOriginal(), _taggedReverse()],
          correction: correction,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing,
          reason: 'idempotency: a corrected logical row has no correct button');
    },
  );

  testWidgets(
    'a double-tap correction reverses ONCE (in-flight guard)',
    (tester) async {
      final gate = Completer<void>();
      final correction = _RecordingCorrectionService(gate: gate);
      await tester.pumpWidget(
        _wrap(tagged: [_taggedOriginal()], correction: correction),
      );
      await tester.pumpAndSettle();

      // First correction — holds in-flight on the open gate (online ⇒ awaited).
      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Record correction'));
      await tester.pump();
      expect(correction.calls, hasLength(1));

      // Second correction while the first is still pending → guarded no-op.
      await tester.ensureVisible(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Record correction'));
      await tester.pump();
      expect(correction.calls, hasLength(1),
          reason: 'in-flight guard blocks the second reverse');

      gate.complete();
      await tester.pumpAndSettle();
    },
  );
}

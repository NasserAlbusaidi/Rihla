import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/expense_party_policy.dart';

/// #1149 — table-driven pin of the client mirror of firestore.rules
/// `expensePartiesAreCurrentMembers` (~L765). The `members` column is the
/// set the mirrored rules call site passes: CREATE → active set
/// (activeGroupMembers(), rules:890), UPDATE/soft-delete → full memberIds
/// (rules:1008/1041). Ghosts flip legality between the two sets; that flip
/// is the whole point of the table (Gate R1 P1).
void main() {
  const live = 'uid-live';
  const otherLive = 'uid-other';
  const ghostId = 'deleted-abc12345';
  const shadowUuid = 'shadow-uuid-1';
  const departedUid = 'uid-departed';

  const fullMemberIds = {live, otherLive, ghostId, shadowUuid};
  const activeSet = {live, otherLive, shadowUuid};

  const rosterCurrent = [live, otherLive];
  const rosterWithDeparted = [live, otherLive, departedUid];
  const rosterWithGhost = [live, otherLive, ghostId];

  ({
    String name,
    Set<String> members,
    String payer,
    ExpenseScope scope,
    SplitMode? mode,
    List<String>? custom,
    List<String>? distKeys,
    List<String> roster,
    bool expect,
  })
  c({
    required String name,
    required Set<String> members,
    String payer = live,
    required ExpenseScope scope,
    SplitMode? mode,
    List<String>? custom,
    List<String>? distKeys,
    required List<String> roster,
    required bool expect,
  }) => (
    name: name,
    members: members,
    payer: payer,
    scope: scope,
    mode: mode,
    custom: custom,
    distKeys: distKeys,
    roster: roster,
    expect: expect,
  );

  final cases = [
    c(
      name: '1 personal ignores departed roster (full set)',
      members: fullMemberIds,
      scope: ExpenseScope.personal,
      roster: rosterWithDeparted,
      expect: true,
    ),
    c(
      name: '2 equal split, all-current roster (full set)',
      members: fullMemberIds,
      scope: ExpenseScope.global,
      mode: SplitMode.equally,
      roster: rosterCurrent,
      expect: true,
    ),
    c(
      name: '3 equal split, departed in roster → roster fallback fails',
      members: fullMemberIds,
      scope: ExpenseScope.global,
      mode: SplitMode.equally,
      roster: rosterWithDeparted,
      expect: false,
    ),
    c(
      name: '4 exact mode escapes roster; ghost legal on UPDATE set',
      members: fullMemberIds,
      scope: ExpenseScope.global,
      mode: SplitMode.exact,
      distKeys: [live, ghostId],
      roster: rosterWithDeparted,
      expect: true,
    ),
    c(
      name: '5 departed dist key fails even with current roster',
      members: fullMemberIds,
      scope: ExpenseScope.global,
      mode: SplitMode.exact,
      distKeys: [live, departedUid],
      roster: rosterCurrent,
      expect: false,
    ),
    c(
      name: '6 custom non-empty escapes roster; shadow legal',
      members: fullMemberIds,
      scope: ExpenseScope.custom,
      mode: SplitMode.equally,
      custom: [live, shadowUuid],
      roster: rosterWithDeparted,
      expect: true,
    ),
    c(
      name: '7 departed custom participant fails',
      members: fullMemberIds,
      scope: ExpenseScope.custom,
      mode: SplitMode.equally,
      custom: [live, departedUid],
      roster: rosterCurrent,
      expect: false,
    ),
    c(
      name: '8 custom-empty falls to roster fallback and fails',
      members: fullMemberIds,
      scope: ExpenseScope.custom,
      mode: SplitMode.equally,
      custom: const [],
      roster: rosterWithDeparted,
      expect: false,
    ),
    c(
      name: '9 departed payer fails regardless of roster',
      members: fullMemberIds,
      payer: departedUid,
      scope: ExpenseScope.global,
      mode: SplitMode.equally,
      roster: rosterCurrent,
      expect: false,
    ),
    c(
      name: '10 shares with EMPTY dist falls to roster fallback and fails',
      members: fullMemberIds,
      scope: ExpenseScope.global,
      mode: SplitMode.shares,
      distKeys: const [],
      roster: rosterWithDeparted,
      expect: false,
    ),
    c(
      name: '11 ghost dist key ILLEGAL on CREATE (active) set — flip of #4',
      members: activeSet,
      scope: ExpenseScope.global,
      mode: SplitMode.exact,
      distKeys: [live, ghostId],
      roster: rosterCurrent,
      expect: false,
    ),
    c(
      name: '12 equal-split create doomed on ghost roster (active set)',
      members: activeSet,
      scope: ExpenseScope.global,
      mode: SplitMode.equally,
      roster: rosterWithGhost,
      expect: false,
    ),
    c(
      name: '13 custom among shadow+live escapes ghost roster (active set)',
      members: activeSet,
      scope: ExpenseScope.custom,
      mode: SplitMode.equally,
      custom: [live, shadowUuid],
      roster: rosterWithGhost,
      expect: true,
    ),
    c(
      name: '14 subGroup scope takes the roster branch like global',
      members: fullMemberIds,
      scope: ExpenseScope.subGroup,
      mode: SplitMode.equally,
      roster: rosterWithDeparted,
      expect: false,
    ),
  ];

  group('expensePartiesAreCurrentMembers mirrors rules ~L765', () {
    for (final tc in cases) {
      test(tc.name, () {
        expect(
          expensePartiesAreCurrentMembers(
            payerParticipantId: tc.payer,
            scope: tc.scope,
            splitMode: tc.mode,
            customSplitParticipants: tc.custom,
            splitDistributionKeys: tc.distKeys,
            eventParticipantIds: tc.roster,
            members: tc.members,
          ),
          tc.expect,
        );
      });
    }
  });

  group('expenseReferencesOnlyCurrentMembers (stored pre-state, full set)', () {
    Expense expense({
      String payer = live,
      ExpenseScope scope = ExpenseScope.global,
      SplitMode? mode,
      List<String>? custom,
      Map<String, Decimal>? dist,
    }) => Expense(
      id: 'e1',
      tripId: 't1',
      payerParticipantId: payer,
      amount: Decimal.parse('10'),
      scope: scope,
      customSplitParticipants: custom,
      splitMode: mode,
      splitDistribution: dist,
      createdAt: DateTime(2026),
      createdBy: live,
      lastEditedBy: live,
    );

    test('equal-split expense on departed roster is NOT all-current (R6)', () {
      expect(
        expenseReferencesOnlyCurrentMembers(
          expense(mode: SplitMode.equally),
          rosterWithDeparted,
          fullMemberIds,
        ),
        isFalse,
      );
    });

    test('ghost payer stays all-current on the full set (not frozen)', () {
      expect(
        expenseReferencesOnlyCurrentMembers(
          expense(
            payer: ghostId,
            mode: SplitMode.exact,
            dist: {ghostId: Decimal.parse('10')},
          ),
          rosterCurrent,
          fullMemberIds,
        ),
        isTrue,
      );
    });

    test('departed dist key marks the expense frozen', () {
      expect(
        expenseReferencesOnlyCurrentMembers(
          expense(
            mode: SplitMode.exact,
            dist: {live: Decimal.parse('4'), departedUid: Decimal.parse('6')},
          ),
          rosterCurrent,
          fullMemberIds,
        ),
        isFalse,
      );
    });
  });
}

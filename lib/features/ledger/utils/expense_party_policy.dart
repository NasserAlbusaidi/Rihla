import '../../../core/models/split_mode.dart';
import '../models/expense_model.dart';

/// #1149 client mirror of firestore.rules `expensePartiesAreCurrentMembers`
/// (~L765). [members] is whichever set the mirrored rules call site passes:
///
///  - CREATE checks → the ACTIVE set (`group.activeMemberIds ?? memberIds`,
///    mirroring rules `activeGroupMembers()` incl. its legacy fallback —
///    rules:890), which excludes deleteAccount tombstone ghosts.
///  - UPDATE / soft-delete checks → FULL `group.memberIds` (rules:1008/1041)
///    so ghost history stays editable.
///
/// Passing the wrong set is a correctness bug in BOTH directions: full-on-
/// create false-permits a doomed write; active-on-update false-blocks ghost
/// history. Departed (leave/remove) uids are in NEITHER set.
bool expensePartiesAreCurrentMembers({
  required String payerParticipantId,
  required ExpenseScope scope,
  SplitMode? splitMode,
  List<String>? customSplitParticipants,
  Iterable<String>? splitDistributionKeys,
  required List<String> eventParticipantIds,
  required Set<String> members,
}) {
  final custom = customSplitParticipants ?? const <String>[];
  final dist = splitDistributionKeys?.toList() ?? const <String>[];
  return members.contains(payerParticipantId) &&
      custom.every(members.contains) &&
      dist.every(members.contains) &&
      (scope == ExpenseScope.personal ||
          (scope == ExpenseScope.custom && custom.isNotEmpty) ||
          (const {SplitMode.shares, SplitMode.exact, SplitMode.percent}
                  .contains(splitMode) &&
              dist.isNotEmpty) ||
          eventParticipantIds.every(members.contains));
}

/// Pre-state check for the R6 freeze mirror: does the STORED [expense]
/// reference only current members? Always the FULL memberIds set here — this
/// mirrors the rules' soft-delete gate (`expensePartiesAreCurrentMembers(
/// resource.data, groupMembers())`, rules:1041) and the pre-state half of the
/// allocation-edit bundle. A ghost-party expense is NOT frozen.
bool expenseReferencesOnlyCurrentMembers(
  Expense expense,
  List<String> eventParticipantIds,
  Set<String> memberIds,
) => expensePartiesAreCurrentMembers(
  payerParticipantId: expense.payerParticipantId,
  scope: expense.scope,
  splitMode: expense.splitMode,
  customSplitParticipants: expense.customSplitParticipants,
  splitDistributionKeys: expense.splitDistribution?.keys,
  eventParticipantIds: eventParticipantIds,
  members: memberIds,
);

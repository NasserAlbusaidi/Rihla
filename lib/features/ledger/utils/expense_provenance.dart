/// Provenance shown in the expense editor byline (#248 PR5).
///
/// Distinguishes who **created** an expense (and who last **edited** it) from
/// who **paid** — the "Paid by" card already surfaces the payer. Now that any
/// event participant may edit any expense (PR4), the editor may be a different
/// person than the author, so the editor needs to see whose record it is.
class ExpenseProvenance {
  const ExpenseProvenance({required this.creatorName, this.editorName});

  /// Resolved display name of whoever created the expense.
  final String creatorName;

  /// Resolved display name of whoever last edited it — `null` when the last
  /// editor is the creator (a self-edit adds no new actor) or no edit is
  /// recorded. When `null`, the byline shows "Added by …" only.
  final String? editorName;
}

/// Builds the editor byline data, or `null` when there is nothing to show.
///
/// Returns `null` for legacy expenses with no [createdBy] (`''`) — there is no
/// attributable author to anchor the byline on. Otherwise resolves [createdBy]
/// via [resolveName], and includes the editor only when [lastEditedBy] is a
/// distinct, non-empty uid (so a creator editing their own expense does not get
/// a redundant "edited by" clause).
///
/// [resolveName] maps a uid to a display string and MUST already apply the
/// caller's disambiguation + unknown-uid fallback (e.g. the disambiguated
/// `participantNames` chain ending in the localized "Someone").
ExpenseProvenance? resolveExpenseProvenance({
  required String createdBy,
  required String lastEditedBy,
  required String Function(String uid) resolveName,
}) {
  if (createdBy.isEmpty) return null;
  final showEditor = lastEditedBy.isNotEmpty && lastEditedBy != createdBy;
  return ExpenseProvenance(
    creatorName: resolveName(createdBy),
    editorName: showEditor ? resolveName(lastEditedBy) : null,
  );
}

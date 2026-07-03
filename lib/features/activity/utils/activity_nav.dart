import '../../groups/models/group_activity_log_model.dart';

/// Deep-link target for an activity-feed row tap, resolved per activity type
/// (#840 PR-7; shared across surfaces by #852).
///
/// Callers: the History tab (`cross_group_activity_screen.dart`), the home
/// RECENTLY rows (`home_screen.dart`), and the per-group activity timeline
/// (`group_activity_screen.dart`).
///
/// CONTRACT — MUST stay total (never throw): the group activity screen
/// resolves this during build to decide row affordance, so a throwing
/// resolution would ErrorWidget every row in its day card (the #808 P1
/// class). Keep it out of list-wide match/filter passes
/// (`activityMatchesQuery` in `activity_display.dart`) for the same reason.
/// If you add a case, never target `/group/<gid>/activity` — the group
/// activity screen suppresses only the bare group root as a self-target, so
/// a target equal to its own route would push a duplicate of itself.
///
/// [groupId] must come ONLY from fetch context (`_enrich` in
/// `cross_group_activity_pager.dart`, the dashboard provider's `group.id`,
/// or the group screen's route param) — never `log.metadata['groupId']`.
/// That key is client-forgeable (e.g. on `member_joined`) and a forged
/// groupId would cross-group-navigate. A forged eventId under the TRUE
/// groupId only ever reaches a safe not-found state on the target screen.
String activityRowTarget({
  required String groupId,
  required GroupActivityLog log,
}) {
  switch (log.type) {
    case 'expense_added':
    case 'expense_edited':
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId/ledger';
    case 'expense_deleted':
      // The audit feed is the only place a deleted expense is still visible.
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId/activity';
    case 'event_created':
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId';
    case 'group_settlement':
      // Metadata carries no eventId even for #752 decomposed settle-ups —
      // group settle-up is the only honest target. No `?memberId=` in v1.
      return '/group/$groupId/settle-up';
    // event_deleted (target is gone), member_joined, member_left, and any
    // unknown/default type all fall through to group detail (unchanged).
    default:
      return '/group/$groupId';
  }
}

/// Type+non-empty guard for a metadata value read for NAVIGATION.
///
/// `firestore.rules`' #814 value-domain floor types 11 named metadata keys
/// but leaves `eventId`/`expenseId` OPAQUE, and legacy pre-#814 docs have no
/// floor at all — the map is client-forgeable end to end. A non-String OR
/// empty value reads as absent so a forged/legacy row degrades to the group
/// detail fallback instead of building a malformed path (an empty segment,
/// e.g. `/group/g1/event//ledger`). Deliberately NOT a reuse of
/// `activity_display.dart`'s file-private `_metadataString` (which is
/// `is String` only, without the `.isNotEmpty` guard this callsite needs).
String? _navMetadataString(GroupActivityLog log, String key) {
  final value = log.metadata[key];
  return value is String && value.isNotEmpty ? value : null;
}

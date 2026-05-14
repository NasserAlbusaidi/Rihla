import '../../groups/models/group_model.dart';
import '../models/event_model.dart';

/// Permission helpers for event mutations.
///
/// Mirrors the `validEventAdminUpdate` rule in `security/firestore.rules`:
/// admin ops (remove participant, toggle modules, soft-delete) require the
/// caller to be the event creator OR the group creator. Light ops (rename,
/// dates, add participant) are open to any current event participant and
/// don't need this helper.
class EventPermissions {
  EventPermissions._();

  /// True iff [currentUserId] is allowed to perform admin actions on [event].
  static bool isEventAdmin({
    required Event event,
    required Group group,
    required String? currentUserId,
  }) {
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return event.createdBy == currentUserId ||
        group.createdBy == currentUserId;
  }
}

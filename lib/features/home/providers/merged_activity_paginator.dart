import '../../groups/models/group_activity_log_model.dart';

/// Pure, Firestore-free merge engine for the cross-group Activity tab (#808
/// PR2). Given a per-group fetch buffer it emits the globally-newest entries
/// that are safe to display, holding back any entry that a not-yet-exhausted
/// group could still out-rank on its next page (D-PR2-4 frontier clamp).
///
/// Ownership split: the notifier owns Firestore (the per-group cursor + the
/// actual `fetchActivityPageRaw` calls) and the group name/currency context;
/// this file owns only the ordering + frontier arithmetic. So it is unit-pure
/// and exhaustively table-testable.

/// One emitted entry, tagged with its source group. The notifier enriches this
/// with the group name/currency to build the screen's display entry.
typedef MergedActivityEntry = ({GroupActivityLog log, String groupId});

/// Immutable per-group paging state fed into [mergeAvailable].
class GroupPageState {
  const GroupPageState({
    required this.groupId,
    this.buffer = const [],
    this.exhausted = false,
    this.failed = false,
  });

  final String groupId;

  /// Fetched-but-not-yet-emitted entries, sorted newest-first (timestamp desc,
  /// then id asc for ties). The notifier guarantees this ordering.
  final List<GroupActivityLog> buffer;

  /// The group's last fetch returned fewer than the page size — no more pages.
  final bool exhausted;

  /// The group's last fetch threw. Excluded from the frontier so one failing
  /// group never blocks the rest (the #244 OR-drop precedent); surfaced via
  /// [MergeResult.failedGroups] so the UI can offer a retry.
  final bool failed;

  GroupPageState copyWith({
    List<GroupActivityLog>? buffer,
    bool? exhausted,
    bool? failed,
  }) => GroupPageState(
    groupId: groupId,
    buffer: buffer ?? this.buffer,
    exhausted: exhausted ?? this.exhausted,
    failed: failed ?? this.failed,
  );
}

/// The result of one merge pass: the entries safe to append to the visible
/// list plus the advanced per-group state.
class MergeResult {
  const MergeResult({required this.emitted, required this.states});

  final List<MergedActivityEntry> emitted;
  final Map<String, GroupPageState> states;

  /// True while any group can still yield more: either a non-exhausted,
  /// non-failed group exists, or some buffer still holds withheld entries.
  bool get hasMore => states.values.any(
    (s) => (!s.exhausted && !s.failed) || s.buffer.isNotEmpty,
  );

  /// The non-exhausted, non-failed groups whose buffer is empty — exactly the
  /// groups the notifier must fetch to advance the frontier.
  Set<String> get needsFetch => {
    for (final s in states.values)
      if (!s.exhausted && !s.failed && s.buffer.isEmpty) s.groupId,
  };

  /// Groups whose last fetch threw — the UI surfaces a partial-failure retry.
  Set<String> get failedGroups => {
    for (final s in states.values)
      if (s.failed) s.groupId,
  };
}

/// Total order for emission: timestamp desc, then groupId asc, then log.id asc.
/// Returns true when [a] (in [aGid]) should be emitted before [b] (in [bGid]).
bool _isNewer(
  GroupActivityLog a,
  String aGid,
  GroupActivityLog b,
  String bGid,
) {
  final byTime = a.timestamp.compareTo(b.timestamp);
  if (byTime != 0) return byTime > 0;
  final byGroup = aGid.compareTo(bGid);
  if (byGroup != 0) return byGroup < 0;
  return a.id.compareTo(b.id) < 0;
}

/// Emit the globally-newest buffered entries while the frontier holds.
///
/// An entry may be emitted only while EVERY non-exhausted, non-failed group has
/// a non-empty buffer (else a later page from an empty group could insert a row
/// above the viewport — D-PR2-4). Emits the globally-newest head, pops it, and
/// repeats until a non-exhausted, non-failed group's buffer runs dry.
///
/// Pure: [input] and its buffers are never mutated; a new state map is returned.
MergeResult mergeAvailable(Map<String, GroupPageState> input) {
  // Local mutable working copies — the passed-in lists are never touched.
  final buffers = <String, List<GroupActivityLog>>{
    for (final entry in input.entries)
      entry.key: List<GroupActivityLog>.of(entry.value.buffer),
  };
  final emitted = <MergedActivityEntry>[];

  while (true) {
    // Frontier: any active (non-exhausted, non-failed) group with an empty
    // buffer blocks all further emission until it is refetched.
    final blocked = input.values.any(
      (s) => !s.exhausted && !s.failed && buffers[s.groupId]!.isEmpty,
    );
    if (blocked) break;

    // Pick the globally-newest head among the non-empty buffers.
    String? bestGid;
    GroupActivityLog? bestLog;
    for (final entry in buffers.entries) {
      if (entry.value.isEmpty) continue;
      final head = entry.value.first;
      if (bestLog == null || _isNewer(head, entry.key, bestLog, bestGid!)) {
        bestLog = head;
        bestGid = entry.key;
      }
    }
    if (bestLog == null) break; // nothing buffered anywhere

    buffers[bestGid!]!.removeAt(0);
    emitted.add((log: bestLog, groupId: bestGid));
  }

  final states = <String, GroupPageState>{
    for (final entry in input.entries)
      entry.key: entry.value.copyWith(
        buffer: List<GroupActivityLog>.unmodifiable(buffers[entry.key]!),
      ),
  };
  return MergeResult(emitted: emitted, states: states);
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable model for a group-level activity log entry.
///
/// Action types (D-31):
///   - event_created: A new event was created in the group
///   - event_deleted: An event was removed from the group
///   - group_settlement: A group-level settlement was recorded
///   - member_joined: A new member joined the group
///   - member_left: A member left the group
class GroupActivityLog {
  final String id;

  /// Activity type. One of: event_created, event_deleted, group_settlement,
  /// member_joined, member_left.
  final String type;

  /// Firebase UID of the actor who triggered this event.
  final String actorId;

  /// Display name of the actor.
  final String actorName;

  /// Human-readable description of the event.
  final String description;

  /// Optional metadata (eventId, amount, recipientName, etc.).
  final Map<String, dynamic> metadata;

  /// Client-side UTC timestamp of when the event occurred (ISO 8601 string
  /// in Firestore, per RESEARCH Pitfall 5 — avoids FieldValue.serverTimestamp
  /// ordering issues with optimistic local reads).
  final DateTime timestamp;

  const GroupActivityLog({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.description,
    this.metadata = const {},
    required this.timestamp,
  });

  /// Deserialize a [GroupActivityLog] from a Firestore document map.
  ///
  /// Handles both ISO 8601 string timestamps and Firestore [Timestamp] objects
  /// (fake_cloud_firestore may return Timestamp objects in some paths).
  factory GroupActivityLog.fromFirestore(Map<String, dynamic> data) {
    DateTime ts;
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.parse(rawTs);
    } else {
      ts = DateTime.now(); // fallback for pending writes without a timestamp
    }

    return GroupActivityLog(
      id: data['id'] as String,
      type: data['type'] as String,
      actorId: data['actorId'] as String,
      actorName: data['actorName'] as String? ?? 'Unknown',
      description: data['description'] as String,
      metadata: (data['metadata'] as Map<String, dynamic>?) ?? const {},
      timestamp: ts,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupActivityLog &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'GroupActivityLog(id: $id, type: $type, description: $description)';
}

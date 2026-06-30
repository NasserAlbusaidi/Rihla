import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/firestore_parse.dart';

/// Enum representing the five supported event types.
///
/// Each type carries a string value used for Firestore serialization.
/// nightDayOut serializes as 'night_day_out' per D-11.
enum EventType {
  trip('trip'),
  camping('camping'),
  travel('travel'),
  nightDayOut('night_day_out'),
  custom('custom');

  final String value;
  const EventType(this.value);

  /// Deserializes a Firestore string to the matching [EventType].
  ///
  /// Falls back to [EventType.custom] for unknown values per the plan spec.
  static EventType fromString(String value) {
    return EventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EventType.custom,
    );
  }
}

/// Module visibility configuration for an event.
///
/// After Phase 39 strip: only [ledger] survives. Custom events can still
/// toggle ledger off via [copyWith] per D-14. fromMap silently ignores
/// legacy keys (gear/logistics/vault/memories) on persisted Firestore docs.
///
/// #246 — VESTIGIAL: `ledger` is the single surviving module since Phase 39 and
/// is effectively always-true. NO read path filters by it — `group_balance_provider`
/// folds every event's expenses/settlements regardless of `modules.ledger`, and
/// `firestore.rules` validates only the SHAPE of `modules` (hasOnly['ledger']),
/// never gates writes on its value. So the toggle is a phantom: setting it false
/// hides nothing and blocks no money. Owner decision (2026-06-19): keep it as a
/// vestigial field — neither delete (Event-schema churn + migration) nor enforce
/// (a read-path + rules gate nobody needs) earns its cost. Revisit only if a
/// genuine per-event module need reappears; until then do not wire a read path
/// onto it without reopening #246.
class EventModules {
  final bool ledger;

  const EventModules({this.ledger = true});

  /// Every event type now exposes only ledger.
  factory EventModules.forType(EventType type) =>
      const EventModules(ledger: true);

  /// Deserializes from a Firestore/SQLite map. Legacy keys are tolerated.
  factory EventModules.fromMap(Map<String, dynamic> map) {
    return EventModules(ledger: map['ledger'] as bool? ?? true);
  }

  /// Serializes to a map for Firestore/SQLite storage.
  Map<String, dynamic> toMap() => {'ledger': ledger};

  /// Creates a copy with updated fields.
  EventModules copyWith({bool? ledger}) =>
      EventModules(ledger: ledger ?? this.ledger);
}

/// Immutable model representing an event inside a group.
///
/// Events are stored as a Firestore subcollection at
/// `groups/{groupId}/events/{eventId}` per D-29.
///
/// The bridge pattern (D-22) has been removed in Plan 04-05.
/// All module screens now use EventRef-based Firestore providers.
class Event {
  final String id;
  final String name;
  final EventType type;
  final String groupId;
  final String createdBy;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final EventModules modules;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;

  /// #723 close lifecycle — mirrors soft-delete (`isDeleted`+`deletedAt`).
  /// [isClosed] is the load-bearing, immediately-readable gate (offline-safe,
  /// unlike a pending [closedAt] serverTimestamp); [closedAt]/[closedBy] are
  /// display metadata for the "Closed by … · spending frozen" banner. A closed
  /// event stays visible and keeps contributing to balances — closed ≠ deleted.
  final bool isClosed;
  final DateTime? closedAt;
  final String? closedBy;

  const Event({
    required this.id,
    required this.name,
    required this.type,
    required this.groupId,
    required this.createdBy,
    required this.participantIds,
    required this.participantNames,
    required this.modules,
    this.startDate,
    this.endDate,
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
    this.description,
    this.isClosed = false,
    this.closedAt,
    this.closedBy,
  });

  /// Deserializes an Event from a Firestore document snapshot.
  ///
  /// TOTAL-PARSE (#532): every field is salvaged from a present-but-wrong-type
  /// value instead of hard-casting, so one malformed event doc can never throw
  /// a CastError that errors the whole [watchGroupEvents] stream.
  ///
  /// Handles multiple [createdAt] formats per Pitfall 3 in RESEARCH.md:
  /// - Firestore Timestamp (from server-written docs)
  /// - ISO 8601 String (from client-generated timestamps)
  /// - null (falls back to DateTime.now())
  factory Event.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Event(
      id: doc.id,
      name: data['name'] is String ? data['name'] as String : '',
      type: EventType.fromString(
        data['type'] is String ? data['type'] as String : 'custom',
      ),
      groupId: data['groupId'] is String ? data['groupId'] as String : '',
      createdBy: data['createdBy'] is String ? data['createdBy'] as String : '',
      participantIds: data['participantIds'] is List
          ? (data['participantIds'] as List).whereType<String>().toList()
          : const <String>[],
      participantNames: data['participantNames'] is Map
          ? Map<String, String>.from(
              (data['participantNames'] as Map).map(
                (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
              ),
            )
          : const <String, String>{},
      modules: data['modules'] is Map<String, dynamic>
          ? EventModules.fromMap(data['modules'] as Map<String, dynamic>)
          : const EventModules(),
      startDate: dateOrNull(data['startDate']),
      endDate: dateOrNull(data['endDate']),
      isDeleted: data['isDeleted'] == true,
      deletedAt: dateOrNull(data['deletedAt']),
      createdAt: dateOrNow(data['createdAt']),
      updatedAt: dateOrNull(data['updatedAt']),
      description: data['description'] is String
          ? data['description'] as String
          : null,
      isClosed: data['isClosed'] == true,
      closedAt: dateOrNull(data['closedAt']),
      closedBy: data['closedBy'] is String ? data['closedBy'] as String : null,
    );
  }

  /// Serializes this Event to a Firestore-ready map.
  ///
  /// - [createdAt] stored as ISO 8601 string (client-generated timestamp)
  /// - [serverCreatedAt] stored separately as FieldValue.serverTimestamp()
  /// - Date fields stored as Firestore Timestamps when non-null
  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name,
      'type': type.value,
      'groupId': groupId,
      'createdBy': createdBy,
      'participantIds': participantIds,
      'participantNames': participantNames,
      'modules': modules.toMap(),
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'createdAt': createdAt.toIso8601String(),
      'serverCreatedAt': FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'description': description,
      'isClosed': isClosed,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'closedBy': closedBy,
    };
  }

  /// Creates a copy with updated fields (immutable pattern).
  ///
  /// Note: the `?? this` idiom cannot null-out [closedAt]/[closedBy], so reopen
  /// (which clears them) goes through `EventService.reopenEvent`'s partial
  /// `.update()`, never `copyWith` (#723).
  Event copyWith({
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? participantIds,
    Map<String, String>? participantNames,
    EventModules? modules,
    bool? isDeleted,
    DateTime? deletedAt,
    DateTime? updatedAt,
    String? description,
    bool? isClosed,
    DateTime? closedAt,
    String? closedBy,
  }) {
    return Event(
      id: id,
      name: name ?? this.name,
      type: type,
      groupId: groupId,
      createdBy: createdBy,
      participantIds: participantIds ?? this.participantIds,
      participantNames: participantNames ?? this.participantNames,
      modules: modules ?? this.modules,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      isClosed: isClosed ?? this.isClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
    );
  }

  /// True when [endDate] is in the past.
  bool get isPast {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate!);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Event(id: $id, name: $name, type: ${type.value}, groupId: $groupId)';
}

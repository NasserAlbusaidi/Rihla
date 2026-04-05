import 'package:cloud_firestore/cloud_firestore.dart';

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
/// Mirrors [TripModules] but adds [memories] and removes [docs]/[itinerary].
/// The constructor does NOT force [ledger] to true — preset types enforce
/// ledger=true via [EventModules.forType]. Custom events can toggle ledger
/// off via [copyWith] per D-14.
class EventModules {
  final bool ledger;
  final bool gear;
  final bool logistics;
  final bool vault;
  final bool memories;

  const EventModules({
    this.ledger = true,
    this.gear = false,
    this.logistics = false,
    this.vault = false,
    this.memories = false,
  });

  /// Returns the correct module configuration for the given event type.
  ///
  /// Module config per D-12:
  /// - Trip: all modules enabled
  /// - Camping: ledger + gear + logistics + memories
  /// - Travel: ledger + logistics + vault + memories
  /// - Night/Day Out: ledger only
  /// - Custom: ledger only (default starting state — user can toggle via UI)
  factory EventModules.forType(EventType type) {
    switch (type) {
      case EventType.trip:
        return const EventModules(
          ledger: true,
          gear: true,
          logistics: true,
          vault: true,
          memories: true,
        );
      case EventType.camping:
        return const EventModules(
          ledger: true,
          gear: true,
          logistics: true,
          vault: false,
          memories: true,
        );
      case EventType.travel:
        return const EventModules(
          ledger: true,
          gear: false,
          logistics: true,
          vault: true,
          memories: true,
        );
      case EventType.nightDayOut:
        return const EventModules(
          ledger: true,
          gear: false,
          logistics: false,
          vault: false,
          memories: false,
        );
      case EventType.custom:
        return const EventModules(
          ledger: true,
          gear: false,
          logistics: false,
          vault: false,
          memories: false,
        );
    }
  }

  /// Deserializes from a Firestore/SQLite map.
  ///
  /// Preserves whatever ledger value is stored — supports custom type
  /// scenarios where ledger may have been toggled off.
  factory EventModules.fromMap(Map<String, dynamic> map) {
    return EventModules(
      ledger: map['ledger'] as bool? ?? true,
      gear: map['gear'] as bool? ?? false,
      logistics: map['logistics'] as bool? ?? false,
      vault: map['vault'] as bool? ?? false,
      memories: map['memories'] as bool? ?? false,
    );
  }

  /// Serializes all 5 booleans to a map for Firestore/SQLite storage.
  Map<String, dynamic> toMap() {
    return {
      'ledger': ledger,
      'gear': gear,
      'logistics': logistics,
      'vault': vault,
      'memories': memories,
    };
  }

  /// Creates a copy with updated fields.
  ///
  /// Includes [ledger] so Custom events can toggle it off per D-14.
  EventModules copyWith({
    bool? ledger,
    bool? gear,
    bool? logistics,
    bool? vault,
    bool? memories,
  }) {
    return EventModules(
      ledger: ledger ?? this.ledger,
      gear: gear ?? this.gear,
      logistics: logistics ?? this.logistics,
      vault: vault ?? this.vault,
      memories: memories ?? this.memories,
    );
  }
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
  final String currency;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? description;

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
    this.currency = 'OMR',
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
    this.updatedAt,
    this.description,
  });

  /// Deserializes an Event from a Firestore document snapshot.
  ///
  /// Handles multiple [createdAt] formats per Pitfall 3 in RESEARCH.md:
  /// - Firestore Timestamp (from server-written docs)
  /// - ISO 8601 String (from client-generated timestamps)
  /// - null (falls back to DateTime.now())
  factory Event.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse createdAt: handle Timestamp, String, or null fallback
    final DateTime createdAt;
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      createdAt = DateTime.parse(rawCreatedAt);
    } else {
      createdAt = DateTime.now();
    }

    // Parse nullable date fields from Firestore Timestamps
    final DateTime? startDate =
        data['startDate'] != null
            ? (data['startDate'] as Timestamp).toDate()
            : null;
    final DateTime? endDate =
        data['endDate'] != null
            ? (data['endDate'] as Timestamp).toDate()
            : null;
    final DateTime? deletedAt =
        data['deletedAt'] != null
            ? (data['deletedAt'] as Timestamp).toDate()
            : null;
    final DateTime? updatedAt =
        data['updatedAt'] != null
            ? (data['updatedAt'] as Timestamp).toDate()
            : null;

    return Event(
      id: doc.id,
      name: data['name'] as String,
      type: EventType.fromString(data['type'] as String? ?? 'custom'),
      groupId: data['groupId'] as String,
      createdBy: data['createdBy'] as String,
      participantIds: List<String>.from(
        data['participantIds'] as List? ?? [],
      ),
      participantNames: Map<String, String>.from(
        data['participantNames'] as Map? ?? {},
      ),
      modules: EventModules.fromMap(
        data['modules'] as Map<String, dynamic>? ?? {},
      ),
      startDate: startDate,
      endDate: endDate,
      currency: data['currency'] as String? ?? 'OMR',
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      description: data['description'] as String?,
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
      'currency': currency,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'createdAt': createdAt.toIso8601String(),
      'serverCreatedAt': FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'description': description,
    };
  }

  /// Creates a copy with updated fields (immutable pattern).
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
      currency: currency,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
    );
  }

  /// True when [endDate] is in the past. Same logic as Trip.isPast.
  bool get isPast {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate!);
  }

  /// True when now is between [startDate] and [endDate]. Same logic as Trip.isOngoing.
  bool get isOngoing {
    if (startDate == null || endDate == null) return false;
    final now = DateTime.now();
    return now.isAfter(startDate!) && now.isBefore(endDate!);
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

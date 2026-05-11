/// Canonical record type for referencing a specific event within a group.
///
/// Used as the family parameter for all EventRef-based Firestore stream
/// providers, replacing bare `String tripId` in legacy providers.
///
/// Example:
/// ```dart
/// final ref = (groupId: 'g1', eventId: 'e1');
/// ref.watch(eventExpensesProvider(ref));
/// ```
typedef EventRef = ({String groupId, String eventId});

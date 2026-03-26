import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/event_ref.dart';
import '../models/memory_model.dart';
import '../services/memory_service.dart';

/// Memory service provider
final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

/// Stream of memories for an event (Firestore-backed).
///
/// Keyed on [EventRef] for group + event co-location.
final eventMemoriesProvider =
    StreamProvider.family<List<Memory>, EventRef>((ref, eventRef) {
  final service = ref.watch(memoryServiceProvider);
  return service.watchMemories(eventRef.groupId, eventRef.eventId);
});

/// Backward-compatible shim for existing screens still on the trip-ID API.
///
/// Screens referencing [tripMemoriesProvider] will continue to compile.
/// Migrate callers to [eventMemoriesProvider] once EventRef is propagated.
@Deprecated('Use eventMemoriesProvider with EventRef instead')
final tripMemoriesProvider =
    FutureProvider.family<List<Memory>, String>((ref, tripId) async {
  // Cannot resolve groupId from tripId at this layer — return empty list
  // until callers are migrated to eventMemoriesProvider.
  return const [];
});

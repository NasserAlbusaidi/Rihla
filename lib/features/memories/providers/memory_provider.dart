import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/storage_gateway.dart';
import '../../../core/types/event_ref.dart';
import '../models/memory_model.dart';
import '../services/memory_service.dart';

/// Memory service provider
final memoryServiceProvider = Provider<MemoryService>((ref) {
  final service = MemoryService();
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of memories for an event with batch pre-issued signed URLs.
///
/// Uses [MemoryService.listMemoriesWithUrls] so every refresh performs a
/// single callable round-trip that pre-signs all URLs server-side (D-03).
/// Replaces per-item `getDownloadURL` calls that went through the direct
/// Storage SDK — those paths are now denied by `storage.rules`.
final eventMemoriesProvider =
    StreamProvider.family<List<Memory>, EventRef>((ref, eventRef) async* {
  final service = ref.watch(memoryServiceProvider);
  await for (final memories in service.watchMemories(
    eventRef.groupId,
    eventRef.eventId,
  )) {
    if (memories.isEmpty) {
      yield memories;
      continue;
    }
    try {
      final withUrls = await service.listMemoriesWithUrls(
        groupId: eventRef.groupId,
        eventId: eventRef.eventId,
      );
      final urlByPath = <String, String>{
        for (final m in withUrls)
          if (m.fields['storagePath'] is String)
            m.fields['storagePath'] as String: m.signedUrl,
      };
      yield memories
          .map((m) => urlByPath[m.storagePath] != null
              ? m.copyWith(signedUrl: urlByPath[m.storagePath])
              : m)
          .toList();
    } catch (_) {
      // If the callable fails (auth/transient), fall back to metadata without
      // URLs — screens render placeholders rather than crashing the stream.
      yield memories;
    }
  }
});

/// Backward-compatible shim for screens still on the trip-ID API.
@Deprecated('Use eventMemoriesProvider with EventRef instead')
final tripMemoriesProvider =
    FutureProvider.family<List<Memory>, String>((ref, tripId) async {
  return const [];
});

/// Keep [MemoryWithUrl] exported here so providers don't have to import the
/// gateway directly for type references.
typedef MemoryListing = MemoryWithUrl;

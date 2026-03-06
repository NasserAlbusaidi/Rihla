import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/memory_model.dart';
import '../services/memory_service.dart';

/// Memory service provider
final memoryServiceProvider = Provider<MemoryService>((ref) {
  return MemoryService();
});

/// Stream of memories for a trip
final tripMemoriesProvider =
    FutureProvider.family<List<Memory>, String>((ref, tripId) async {
  final service = ref.watch(memoryServiceProvider);
  return service.getMemories(tripId);
});

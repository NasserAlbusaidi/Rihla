import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/types/event_ref.dart';
import '../models/document_model.dart';
import '../services/document_service.dart';

/// Loading state for document operations
final documentLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for document operations
final documentErrorProvider = StateProvider<String?>((ref) => null);

/// Upload progress state (0.0 – 1.0)
final uploadProgressProvider = StateProvider<double>((ref) => 0);

/// Document service provider
final documentServiceProvider = Provider<DocumentService>((ref) {
  return DocumentService();
});

/// Stream of documents for an event (Firestore-backed).
///
/// Keyed on [EventRef] for group + event co-location.
final eventDocumentsProvider =
    StreamProvider.family<List<Document>, EventRef>((ref, eventRef) {
  final service = ref.watch(documentServiceProvider);
  return service.watchDocuments(eventRef.groupId, eventRef.eventId);
});

/// Backward-compatible shim for existing screens still on the trip-ID API.
///
/// Screens referencing [tripDocumentsProvider] will continue to compile.
/// Migrate callers to [eventDocumentsProvider] once EventRef is propagated.
@Deprecated('Use eventDocumentsProvider with EventRef instead')
final tripDocumentsProvider = StreamProvider.family<List<Document>, String>((
  ref,
  tripId,
) {
  // Cannot resolve groupId from tripId at this layer — return empty stream
  // until callers are migrated to eventDocumentsProvider.
  return const Stream.empty();
});

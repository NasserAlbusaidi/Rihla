import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore MemoryService tests.
// Real implementation added in Plan 04-04 (Memories Migration).

void main() {
  group('MemoryService (Firestore)', () {
    group('watchMemories', () {
      test(
        'returns a stream of memory metadata from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-04: MemoryService Firestore migration',
      );
    });

    group('uploadPhoto', () {
      test(
        'writes memory metadata to groups/{groupId}/events/{eventId}/memories',
        () {},
        skip: 'Awaiting Plan 04-04: MemoryService Firestore migration',
      );

      test(
        'uploads image to Firebase Storage (trip-memories bucket equivalent)',
        () {},
        skip: 'Awaiting Plan 04-04: MemoryService Firestore migration',
      );
    });

    group('deleteMemory', () {
      test(
        'removes Firestore memory metadata and Firebase Storage object',
        () {},
        skip: 'Awaiting Plan 04-04: MemoryService Firestore migration',
      );
    });

    group('Memory serialization', () {
      test(
        'Memory.fromFirestore and toFirestore round-trip produces equivalent object',
        () {},
        skip: 'Awaiting Plan 04-04: MemoryService Firestore migration',
      );
    });
  });
}

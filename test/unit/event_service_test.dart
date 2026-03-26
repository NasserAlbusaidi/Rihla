import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EventService', () {
    test(
      'createEvent writes event document to Firestore',
      () {},
      skip: 'Awaiting Plan 03-01: EventService implementation',
    );
    test(
      'createEvent creates Supabase bridge trip',
      () {},
      skip: 'Awaiting Plan 03-01: EventService bridge',
    );
    test(
      'createEvent seeds gear items for Camping type',
      () {},
      skip: 'Awaiting Plan 03-01: EventService camping presets',
    );
    test(
      'createEvent skips gear seeding for non-Camping types',
      () {},
      skip: 'Awaiting Plan 03-01: EventService',
    );
    test(
      'createEvent skips bridge if Supabase not initialized',
      () {},
      skip: 'Awaiting Plan 03-01: EventService',
    );
    test(
      'deleteEvent sets isDeleted flag',
      () {},
      skip: 'Awaiting Plan 03-01: EventService',
    );
    test(
      'updateParticipants updates participantIds and participantNames',
      () {},
      skip: 'Awaiting Plan 03-01: EventService',
    );
  });
}

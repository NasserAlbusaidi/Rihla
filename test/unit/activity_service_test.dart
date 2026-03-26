import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: Firestore ActivityService tests.
// Real implementation added in Plan 04-04 (Activity Migration).

void main() {
  group('ActivityService (Firestore)', () {
    group('watchActivityLogs', () {
      test(
        'returns a stream of activity logs from Firestore subcollection',
        () {},
        skip: 'Awaiting Plan 04-04: ActivityService Firestore migration',
      );

      test(
        'orders logs by createdAt descending',
        () {},
        skip: 'Awaiting Plan 04-04: ActivityService Firestore migration',
      );
    });

    group('addActivityLog', () {
      test(
        'writes activity log document to groups/{groupId}/events/{eventId}/activityLogs',
        () {},
        skip: 'Awaiting Plan 04-04: ActivityService Firestore migration',
      );
    });
  });
}

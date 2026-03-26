import 'package:flutter_test/flutter_test.dart';

// Wave 0 stub: ConnectivityProvider tests (Firestore-based).
// Real implementation added in Plan 04-04 (Connectivity Migration).

void main() {
  group('ConnectivityProvider (Firestore)', () {
    group('checkConnectivity', () {
      test(
        'returns true when Firestore is reachable',
        () {},
        skip: 'Awaiting Plan 04-04: ConnectivityProvider Firestore migration',
      );

      test(
        'returns false when Firestore throws a network error',
        () {},
        skip: 'Awaiting Plan 04-04: ConnectivityProvider Firestore migration',
      );
    });
  });
}

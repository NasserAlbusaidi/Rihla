import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/auth/services/auth_recovery_service.dart';

// #170: the recovery cleanup intent gains an `expiresAt` field so a Firestore
// TTL can reap abandoned bearer-secret docs. The write happens inside the
// default cleanup-intent factory, which no other test exercises (all inject a
// stub). `buildCleanupIntentPayload` is the pure, testable seam for the exact
// wire shape the client serializes — the OUTBOUND contract the rules gate
// (`validCleanupIntent`) must admit and the TTL keys on.
void main() {
  group('AuthRecoveryService.buildCleanupIntentPayload (#170)', () {
    test('produces exactly {secret, createdAt, expiresAt} with a 24h TTL', () {
      final fixedNow = DateTime.utc(2026, 6, 5, 12);
      const secret = 'a-secret-with-at-least-32-characters-1234567890';

      final payload = AuthRecoveryService.buildCleanupIntentPayload(
        secret,
        clock: () => fixedNow,
      );

      expect(
        payload.keys.toSet(),
        {'secret', 'createdAt', 'expiresAt'},
        reason: 'exact key set the rules `hasOnly([...])` must mirror',
      );
      expect(payload['secret'], secret);
      expect(
        payload['createdAt'],
        isA<FieldValue>(),
        reason: 'createdAt stays a server-timestamp sentinel (the security '
            'control: server validity reads createdAt, not expiresAt)',
      );
      expect(
        payload['expiresAt'],
        isA<Timestamp>(),
        reason: 'expiresAt is a concrete client Timestamp the TTL keys on',
      );
      expect(
        payload['expiresAt'],
        Timestamp.fromDate(fixedNow.add(const Duration(hours: 24))),
        reason: 'TTL window is 24h — comfortably > the 15-min server validity '
            'plus any realistic client clock skew, so a still-valid intent is '
            'never reaped early',
      );
    });

    test(
      'expiresAt is strictly after creation (satisfies the rule lower bound '
      'expiresAt > createdAt)',
      () {
        final fixedNow = DateTime.utc(2026);

        final payload = AuthRecoveryService.buildCleanupIntentPayload(
          'another-secret-with-enough-entropy-aaaaaaaaaa',
          clock: () => fixedNow,
        );

        final expiresAt = payload['expiresAt']! as Timestamp;
        expect(expiresAt.toDate().isAfter(fixedNow), isTrue);
      },
    );
  });
}

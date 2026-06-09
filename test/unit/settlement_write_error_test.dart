import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/settlement_write_error.dart';

FirebaseException _fe(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  group('classifySettlementWriteError', () {
    final cases = <(String, Object, SettlementWriteErrorKind)>[
      ('permission-denied', _fe('permission-denied'), SettlementWriteErrorKind.denied),
      ('unauthenticated', _fe('unauthenticated'), SettlementWriteErrorKind.denied),
      ('invalid-argument', _fe('invalid-argument'), SettlementWriteErrorKind.denied),
      ('failed-precondition', _fe('failed-precondition'), SettlementWriteErrorKind.denied),
      ('out-of-range', _fe('out-of-range'), SettlementWriteErrorKind.denied),
      ('already-exists', _fe('already-exists'), SettlementWriteErrorKind.denied),
      ('unavailable', _fe('unavailable'), SettlementWriteErrorKind.network),
      ('deadline-exceeded', _fe('deadline-exceeded'), SettlementWriteErrorKind.network),
      ('cancelled', _fe('cancelled'), SettlementWriteErrorKind.network),
      ('internal', _fe('internal'), SettlementWriteErrorKind.unknown),
      ('resource-exhausted', _fe('resource-exhausted'), SettlementWriteErrorKind.unknown),
      ('non-firebase StateError', StateError('boom'), SettlementWriteErrorKind.unknown),
      ('plain ArgumentError', ArgumentError('bad'), SettlementWriteErrorKind.unknown),
    ];

    for (final (name, error, expected) in cases) {
      test('$name → $expected', () {
        expect(classifySettlementWriteError(error), expected);
      });
    }
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/settlement_write_error.dart';

FirebaseException _fe(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

FirebaseFunctionsException _fx(String code, {Object? details}) =>
    FirebaseFunctionsException(message: 'x', code: code, details: details);

void main() {
  group('classifySettlementWriteError — Firestore (legacy replay/update paths)', () {
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

  group('classifySettlementWriteError — recordSettlement callable (#1129)', () {
    final cases = <(String, Object, SettlementWriteErrorKind)>[
      (
        'over-outstanding cap → staleBalance',
        _fx('failed-precondition', details: {
          'kind': 'over-outstanding',
          'outstandingFils': 2000,
          'currency': 'OMR',
        }),
        SettlementWriteErrorKind.staleBalance,
      ),
      (
        'stale-decomposition → staleBalance',
        _fx('failed-precondition', details: {'kind': 'stale-decomposition'}),
        SettlementWriteErrorKind.staleBalance,
      ),
      (
        'conflicting dedup doc (already-exists) → staleBalance',
        _fx('already-exists'),
        SettlementWriteErrorKind.staleBalance,
      ),
      (
        'party-not-member → denied (authz, not staleness)',
        _fx('failed-precondition', details: {'kind': 'party-not-member'}),
        SettlementWriteErrorKind.denied,
      ),
      (
        'party-not-participant → denied',
        _fx('failed-precondition', details: {'kind': 'party-not-participant'}),
        SettlementWriteErrorKind.denied,
      ),
      (
        'failed-precondition without details → denied',
        _fx('failed-precondition'),
        SettlementWriteErrorKind.denied,
      ),
      ('permission-denied → denied', _fx('permission-denied'), SettlementWriteErrorKind.denied),
      ('invalid-argument → denied', _fx('invalid-argument'), SettlementWriteErrorKind.denied),
      ('unavailable (offline) → network', _fx('unavailable'), SettlementWriteErrorKind.network),
      ('deadline-exceeded → network', _fx('deadline-exceeded'), SettlementWriteErrorKind.network),
      ('internal → unknown', _fx('internal'), SettlementWriteErrorKind.unknown),
    ];

    for (final (name, error, expected) in cases) {
      test(name, () {
        expect(classifySettlementWriteError(error), expected);
      });
    }
  });

  group('overOutstandingFils', () {
    test('extracts the fresh outstanding from an over-outstanding rejection', () {
      final e = _fx('failed-precondition', details: {
        'kind': 'over-outstanding',
        'outstandingFils': 4000,
        'currency': 'OMR',
      });
      expect(overOutstandingFils(e), 4000);
    });

    test('null for other kinds, garbage details, and non-callable errors', () {
      expect(
        overOutstandingFils(
          _fx('failed-precondition', details: {'kind': 'stale-decomposition'}),
        ),
        isNull,
      );
      expect(
        overOutstandingFils(_fx('failed-precondition',
            details: {'kind': 'over-outstanding', 'outstandingFils': 'lots'})),
        isNull,
      );
      expect(overOutstandingFils(_fx('failed-precondition')), isNull);
      expect(overOutstandingFils(_fe('failed-precondition')), isNull);
      expect(overOutstandingFils(StateError('x')), isNull);
    });
  });
}

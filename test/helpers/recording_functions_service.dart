import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/firebase_functions_service.dart';
import 'package:safar/features/ledger/models/record_settlement_result.dart';

/// #1129 test seam: records every `recordSettlement` payload the services
/// send to the callable, so tests assert the WIRE CONTRACT (mode, integer
/// subunits, epoch, legs order) instead of Firestore doc shapes — the doc
/// shapes are pinned server-side by the emulator tables in
/// `functions/test/callables/recordSettlement.*.test.ts`.
class RecordingFunctionsService extends Fake implements FirebaseFunctionsService {
  /// One map per call, keyed by the callable's exact input field names.
  final List<Map<String, Object?>> recordSettlementCalls = [];

  /// The result returned to the service (override per test).
  RecordSettlementResult result = const RecordSettlementResult(
    alreadyRecorded: false,
    eventScopeWrites: 1,
    groupScopeWrites: 0,
    shouldBumpLedgerRevision: true,
    settledAt: '2026-07-11T12:00:00.000Z',
  );

  /// When set, [recordSettlement] throws it AFTER recording the payload.
  Object? error;

  Map<String, Object?> get lastCall => recordSettlementCalls.last;

  @override
  Future<RecordSettlementResult> recordSettlement({
    required String groupId,
    required String mode,
    String? eventId,
    required String payerParticipantId,
    required String recipientParticipantId,
    required int amountFils,
    required String currency,
    String? note,
    String? payerName,
    String? recipientName,
    required int observedPairEpoch,
    List<Map<String, Object>>? legs,
  }) async {
    recordSettlementCalls.add({
      'groupId': groupId,
      'mode': mode,
      'eventId': eventId,
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      'amountFils': amountFils,
      'currency': currency,
      'note': note,
      'payerName': payerName,
      'recipientName': recipientName,
      'observedPairEpoch': observedPairEpoch,
      'legs': legs,
    });
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

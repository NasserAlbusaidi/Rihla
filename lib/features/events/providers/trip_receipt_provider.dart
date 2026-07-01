import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/models/activity_log_model.dart';
import '../../activity/services/activity_service.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/providers/ledger_view_provider.dart';
import '../models/trip_receipt.dart';
import '../utils/trip_receipt_builder.dart';
import 'event_provider.dart';

/// Loads the event's correction/audit history for the Trip Receipt (#704).
///
/// `.autoDispose` so each time the export sheet opens it RE-FETCHES — the data
/// sections are live streams, so a non-autoDispose one-shot would freeze the
/// corrections at first fetch and a re-export would miss newer edits. Audit
/// errors are non-fatal: they degrade to empty corrections + an honest coverage
/// flag rather than failing the whole receipt.
final tripReceiptAuditProvider = FutureProvider.autoDispose.family<
    ({List<ActivityLog> corrections, AuditCoverage coverage}), EventRef>((
  ref,
  r,
) async {
  final service = ref.read(activityServiceProvider);
  try {
    final res = await service.fetchAllEventAuditLogs(r.groupId, r.eventId);
    final corrections = res.logs
        .where((l) => l.category == 'MONEY' && (l.isUpdate || l.isDelete))
        .toList();
    final coverage = res.fromCacheEmpty
        ? AuditCoverage.unverifiedOffline
        : res.capHit
            ? AuditCoverage.capped
            : AuditCoverage.complete;
    return (corrections: corrections, coverage: coverage);
  } catch (_) {
    return (
      corrections: const <ActivityLog>[],
      coverage: AuditCoverage.unavailable,
    );
  }
});

/// Composes the [TripReceipt] for one event from the live ledger providers plus
/// the audit fetch. Emits `AsyncLoading` until the event doc, group members,
/// expenses, settlements AND audit have ALL resolved — never builds from a
/// partially-loaded snapshot (a one-shot CSV must not silently omit sections,
/// nor present an empty defensive `ledgerView` as a complete receipt).
///
/// Balances + roster + the participant universe come VERBATIM from
/// [ledgerViewProvider] (the single per-event `calculateBalances` pass) — no
/// recompute, never `groupBalancesProvider` (wrong, group-aggregated universe).
/// `.autoDispose` so `generatedAt` is stamped fresh on each open.
final tripReceiptProvider = Provider.autoDispose
    .family<AsyncValue<TripReceipt>, EventRef>((ref, r) {
  final eventAsync = ref.watch(eventDetailProvider(r));
  final expensesAsync = ref.watch(eventExpensesProvider(r));
  final settlementsAsync = ref.watch(eventSettlementsProvider(r));
  final membersAsync = ref.watch(groupMembersProvider(r.groupId));
  final auditAsync = ref.watch(tripReceiptAuditProvider(r));

  final inputs = [
    eventAsync,
    expensesAsync,
    settlementsAsync,
    membersAsync,
    auditAsync,
  ];
  if (inputs.any((a) => a.isLoading)) return const AsyncValue.loading();

  // Audit is non-fatal (its own provider degrades to a coverage flag); the
  // ledger inputs are required.
  final required = [eventAsync, expensesAsync, settlementsAsync, membersAsync];
  for (final a in required) {
    if (a.hasError) {
      return AsyncValue.error(a.error!, a.stackTrace ?? StackTrace.current);
    }
  }

  final event = eventAsync.value;
  if (event == null) return const AsyncValue.loading();

  final view = ref.watch(ledgerViewProvider(r));
  final audit = auditAsync.value!;

  return AsyncValue.data(
    buildTripReceipt(
      event: event,
      expenses: expensesAsync.value!,
      settlements: settlementsAsync.value!,
      participants: view.participants,
      auditLogs: audit.corrections,
      correctionsCoverage: audit.coverage,
      balancesByCurrency: view.balances,
      roster: view.rosterDisplayNames,
      generatedAt: DateTime.now(),
    ),
  );
});

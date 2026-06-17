import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_functions_service.dart';
import '../models/claim_models.dart';

// #278 PR9 — the creator's view of pending claim requests for a group.
//
// `autoDispose` is CORRECT here (NOT the #104 ledger/balance rule): this is
// watched ONLY on the group-settings screen and is never pinned by the
// always-mounted home dashboard, so it disposes when the screen closes. It is a
// one-shot creator-gated callable read, refreshed via
// `ref.invalidate(groupClaimRequestsProvider(groupId))` after each
// approve/decline and on pull-to-refresh.
final groupClaimRequestsProvider = FutureProvider.autoDispose
    .family<List<GroupClaimRequest>, String>((ref, groupId) {
  return ref
      .read(firebaseFunctionsServiceProvider)
      .listGroupClaimRequests(groupId: groupId);
});

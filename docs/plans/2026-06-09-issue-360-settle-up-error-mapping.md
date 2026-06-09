# #360 — settle-up error mapping mislabels permission-denied as "check your connection"

**Issue:** #360 (P3). Both settle-up write surfaces catch *every* error and show `settleUpRecordFailed` ("Couldn't record settlement. Check your connection and try again."), so a real `PERMISSION_DENIED` / validation rejection is misattributed to the network.

**Gate:** NOT required. Client-only error-message mapping. No `BalanceCalculator`/money math, no `firestore.rules`/Functions, no routing, no schema. The write itself is unchanged.

## Verified state (against code)
- Event surface: `lib/features/ledger/screens/settle_up_screen.dart:379` — `catch (_)` → `settleUpRecordFailed`.
- Group surface: `lib/features/groups/screens/group_settle_up_screen.dart:448` — `catch (e)` → `settleUpRecordFailed`.
- `record_payment_sheet.dart` (#282 creditor path) has no own write/catch — delegates to the group handler.
- `addSettlement` (`settlement_service.dart`) `await …doc().set()` and rethrows `FirebaseException`.
- **Acceptance #2 (offline-queued "saved, will sync") is NOT on `origin/main`.** `noteLocalWrite`/`bannerSavedWillSync` do not exist on main; #357 (which adds them) is OPEN, with WIP on another branch (`fix/rtl-forward-chevrons`) — verified against code, not the WIP branch I'd first read. So box #2 is genuinely unbuilt and belongs to #357. This PR scopes to the error-mislabel half (acceptance #1 + #3) and uses **`Refs #360`** (box #2 deferred to #357).

## Design
Add a pure, testable classifier `lib/core/utils/settlement_write_error.dart`:

```dart
enum SettlementWriteErrorKind { network, denied, unknown }
SettlementWriteErrorKind classifySettlementWriteError(Object error);   // FirebaseException.code → kind; non-Firebase → unknown
String settlementWriteErrorMessage(AppLocalizations l10n, SettlementWriteErrorKind kind);
```

- `network`  ← codes `unavailable`, `deadline-exceeded`, `cancelled` → `settleUpRecordFailed` (existing copy).
- `denied`   ← codes `permission-denied`, `unauthenticated`, `invalid-argument`, `failed-precondition`, `out-of-range`, `already-exists` → new `settleUpRecordFailedDenied`.
- `unknown`  ← anything else (incl. non-Firebase `StateError`) → new `settleUpRecordFailedGeneric` (NOT a network claim).

The settle-up write throws `FirebaseException` (or an `ArgumentError` programming-bug → unknown), so code-based classification is sufficient; no `dart:io`.

## Steps (TDD)
1. **RED** unit test `test/unit/settlement_write_error_test.dart` — table-driven: denied/network/unknown codes + non-Firebase → unknown.
2. **RED** widget: extend `settle_up_screen_test.dart` + `group_settle_up_screen_test.dart` with a `permission-denied` FirebaseException case → assert the **denied** message (not the network one). Update the existing `StateError('write failed')` cases to assert the **generic** message (unknown ≠ network).
3. Implement the classifier + util.
4. l10n: `settleUpRecordFailedDenied`, `settleUpRecordFailedGeneric` (en + ar).
5. Wire both screens: `catch (e)` → `settlementWriteErrorMessage(context.l10n, classifySettlementWriteError(e))`. Do NOT touch the write or the success/`noteLocalWrite` path.
6. `flutter gen-l10n`, `flutter analyze` clean, run unit + both settle-up suites + full home/ledger/groups.

## Copy
- denied: "This settlement wasn't allowed. Please check the details and try again."
- generic: "Couldn't record settlement. Please try again."

## Scope
PR `Refs #360` — delivers acceptance #1 + #3. Acceptance #2 (offline-queued confirmation) is unbuilt on main and belongs to #357; #360 stays open re-scoped to that box. Out of scope: the broader shared error translator (#356).

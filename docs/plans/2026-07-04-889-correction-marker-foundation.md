# #889 Correction Marker Foundation (`correctionOfSettlementId`)

Date: 2026-07-04 (refresh of the salvaged 831B spec, branch `codex/831-event-settlement-activity`)
Base: `origin/main` `6cda9da3` — **PR #891 (#831 client-write activity fan-in) is
MERGED and included in this base** (landed 2026-07-04; #831 CLOSED). The branch is
rebased onto it, so delta 4's event correction site is present and every line number
below is post-#891 (verified 2026-07-04 against the rebased tree). **#891 added
`'event_settlement'` to the client activity-type allow-list in
`security/firestore.rules` (~L1108, now 5 client entries).** #889 also edits
`security/firestore.rules` (`groupSettleUpId` blank-deny + cross-ref comments) — that
delta MUST be authored **additively on top of** #891's allow-list; confirm the branch
`git diff origin/main -- security/firestore.rules` is purely additive and does not
drop the `event_settlement` entry (the #812 stale-worktree clobber class).
Issue: #889. Refs #283, #753, #831.

## Origin & relationship to #831

Three fresh Gate rounds on the original #831 server-fan-in spec established that the
localized free-text correction note (`settleUpCorrectionNote`) is **not a safe machine
discriminator** for correction reversals:

- a normal payment note can equal the EN/AR correction sentinel (user-typed free text);
- an inverse payer/recipient/amount match is not proof of intent — a real later payment
  can legitimately offset an older one;
- event / group / logical correction paths do not share one write service;
- `settledAt` is a non-fixed-width ISO string (`DateTime.toIso8601String()`), so
  timestamp ordering is not a rules-safe contract.

**#831 no longer depends on this.** It shipped as a client-side `logGroupEvent` write
(PR #891) that knows correction-vs-record at the write site and suppresses corrections
there (`logActivity: false`). The old 831B sentence "do not implement #831 until this
foundation is merged" is obsolete — the dependency was severed by design.

This foundation now serves the **settlement-corrections track (#283 / #753)**: any
server-side surface that must classify a settlement row as a correction (push
notifications, write-rate accounting, future correction activity labeling, atomic
logical correction) needs a machine-readable marker, not note text.

## Decision

Add an optional machine-readable link on correction rows:

```txt
correctionOfSettlementId: <original settlement document id>
```

Only server-authoritative correction callables write this field (Admin SDK). Normal
payment creation never writes it, even if the user-entered note equals a localized
correction sentinel — and **Firestore rules deny any client-created settlement carrying
the key** (see Rules below), which is what makes marker presence un-forgeable and
therefore usable as a trigger-side classifier without reads.

Marked correction writes continue to carry the localized `settleUpCorrectionNote`
sentinel for display compatibility (`isCorrectionNote`,
`lib/features/ledger/utils/correction_note.dart:16`, matches the sentinel in every
supported locale). The note is display-compat only; it is never the source of truth.

Correction marker validity is structural, not timestamp-based: a marked row is valid
only when the referenced source row exists in the same settlement collection and
matches the exact inverse money contract. No `settledAt` string comparison anywhere in
this split.

## Deltas from the salvaged 831B spec

Applied in this refresh; everything else carries over:

1. **Framing** — #831 shipped client-write (PR #891); consumers of this foundation are
   the #283/#753 track, not an #831 `settlementActivityLogger` (which was never built
   and is no longer planned).
2. **Rules: deny-by-omission, not allow-list addition.** 831B added
   `correctionOfSettlementId` to the settlement `hasOnly()` key lists AND denied it on
   client creates. Admin SDK bypasses rules entirely and settlement updates are
   hard-denied (`allow update: if false`, `security/firestore.rules:976` event,
   `:1212` group), so adding the key to the allowed lists has zero live effect — the
   existing `hasOnly()` lists (event `:900`, group `:1153`) already deny any
   marker-bearing client create. This split leaves the key lists **unchanged** and pins
   the deny with rules tests instead. Cheaper on the expression budget, one less
   surface to drift.
3. **Trigger skips are presence-only, not structural.** Because rules deny client
   marker creates, `typeof data.correctionOfSettlementId === 'string' && non-empty`
   proves the row is a server-written correction — the same un-forgeability rationale
   as the `expense_*` skip in `writeRateMonitor.ts:127-137` (#808). `settlementNotifier`
   and `writeRateMonitor` skip on presence, no async read, no shared classifier import.
   Structural inverse validation lives where it is needed: inside the correction
   callables' shared module, exported for future #283/#753 consumers. Each trigger skip
   site and the rules key lists carry a cross-referencing comment: if a future rules
   edit ever admits client-written markers, the skips become forgeable.
4. **Event correction site is post-#891** (`settle_up_screen.dart:371-385`):
   `onCorrect: canRecord ? (s) => _recordSettlement(..., logActivity: false) : null`.
   This split replaces the `_recordSettlement(...)` body with the callable invocation
   **while preserving the `canRecord ? … : null` guard** (an unauthorized viewer must
   not see a Correct action that fails on tap; server authz is defense-in-depth, not
   the affordance). It removes the now-dead `logActivity` parameter from
   `settle_up_screen.dart`'s `_recordSettlement` (`:742` sig, `:752` param, `:800`
   branch — the correction site `:385` was its only `false` caller; forward path `:670`
   defaults true). **Symmetry:** `group_settle_up_screen.dart`'s `onCorrect`
   (`:270-280`) is also a `logActivity: false` caller of *its* `_recordSettlement`
   (`:946` sig, `:962` param); moving it to `correctSettlement(scope: 'group')` leaves
   that param with no `false` caller too — remove it there as well (or the spec is
   asymmetric). Re-point #891's pinned "corrections emit no `event_settlement` activity
   row" test (`test/features/ledger/settle_up_screen_test.dart`): the "no activity row"
   assertion holds trivially (the callable path writes no client activity), but its
   companion "reverse settlement written to the fake DB with swapped parties" assertion
   **cannot hold under a mocked `FirebaseFunctionsService`** (no client write reaches
   the fake DB) — convert it to a "`correctSettlement(scope:'event')` invoked with the
   original id + sentinel" assertion. NOT "same assertion" — new assertion, new
   mechanism.
5. **`shortHash` is a NEW helper** (verified absent from `functions/src`) — add it to
   `functions/src/callables/shared/ids.ts` alongside the existing
   `validId(value, label)` (`ids.ts:7`): deterministic, path-safe, bounded (e.g.
   sha256 hex slice).

## Scope

### Settlement model

`lib/features/ledger/models/settlement_model.dart` — current fields (enumerated from
the type, 2026-07-04): `id, tripId, payerParticipantId, recipientParticipantId, amount,
note, settledAt, payerName, recipientName, isDeleted, deletedAt, scope, groupId,
createdBy, currency, groupSettleUpId`. No marker field exists anywhere in
`lib/ functions/ security/` (grep verified).

Add:

```dart
final String? correctionOfSettlementId;

bool get isMarkedCorrection =>
  correctionOfSettlementId != null && correctionOfSettlementId!.trim().isNotEmpty;
```

`Settlement.fromFirestore` reads `correctionOfSettlementId` when it is a string,
otherwise null. The helper is intentionally marker-only: `isCorrectionNote` may remain
for legacy display code, but new persistence/derived-surface decisions must not use it.

`Settlement.fromJson` / `toJson` are legacy Supabase-shape serializers and do not need
to round-trip the marker in this split.

### Write paths

Persist the marker from every live correction path by replacing the client-direct
reverse writes with callable invocations:

- **Event settle-up correction** — `lib/features/ledger/screens/settle_up_screen.dart`,
  the `onCorrect` site (`:371-385`, `canRecord ? (s) => _recordSettlement(..., logActivity: false) : null`).
  Replace the `_recordSettlement(...)` body with
  `FirebaseFunctionsService.correctSettlement(groupId: gid, scope: 'event', eventId: eid,
  settlementId: original.id, correctionNote: l10n.settleUpCorrectionNote)` (all-named
  args, matching the signature below) and keep the `canRecord ? … : null` wrapper.
  Remove the dead `logActivity` parameter from `_recordSettlement` (delta 4).

- **Standalone group settlement correction** —
  `lib/features/groups/screens/group_settle_up_screen.dart:270-280`
  (`onCorrect: (s) => _recordSettlement(..., logActivity: false)`, client-direct).
  Replace with `correctSettlement(groupId: gid, scope: 'group', settlementId: original.id,
  correctionNote: l10n.settleUpCorrectionNote)`. Remove that screen's now-dead
  `logActivity` param too (delta 4 symmetry).

- **Decomposed logical group-settle correction** —
  `group_settle_up_screen.dart` `_correctLogicalSettleUp` (`:1093`; invokes
  `SettlementCorrectionService.reverseLogicalSettleUp` at `:1155`, a client-side
  `WriteBatch` with uuid ids). A large logical settle-up can exceed 20 event slices
  plus residual; rules-side `get()` validation per marked create would exceed
  Firestore's per-request rules read limit, so the client batch cannot become the
  marker write path. Replace with `correctLogicalSettleUp(groupId, groupSettleUpId,
  correctionNote)`; the callable validates the full logical set server-side and writes
  every reverse row with `correctionOfSettlementId: original.id` (event-scope slices
  and residual group-scope rows). **Delete `SettlementCorrectionService`** — its only
  production caller is `_correctLogicalSettleUp` (`:1155`); keeping the unmarked
  client batch reachable invites drift back to the unmarked path. Deleting the class
  also requires: (1) removing `settlementCorrectionServiceProvider`
  (`group_balance_provider.dart:35-38` — a dangling provider is a compile error);
  (2) rewriting `test/features/groups/group_settle_up_correct_test.dart`, whose
  mechanism **subclasses** the service (`_RecordingCorrectionService extends
  SettlementCorrectionService`, `:100`) and overrides
  `settlementCorrectionServiceProvider` (`:145`) — it converts to mocking
  `FirebaseFunctionsService` and asserting the `correctLogicalSettleUp` invocation,
  NOT a re-point of the same assertions. (3) **Delete
  `test/features/groups/settlement_correction_service_test.dart`** — it directly
  instantiates `SettlementCorrectionService.withFirestore` (`:105`), so leaving it
  breaks compilation; its atomicity/shape coverage moves to the callable emulator
  tests.

Unmarked settlement writes stay client-direct with their existing shape (offline
persistence + replay is a project invariant). Normal `SettlementService` /
group-settlement forward-payment paths never write the marker.

**Corrections become online-only** (HTTPS callables do not use Firestore's offline
write queue). The UI must not show queued-success copy for correction callables; if
offline, disable the correction affordance or surface the existing unavailable/offline
error copy without writing. This is an accepted UX regression vs the current
offline-queueable client-direct corrections; no-real-users deploy posture applies.

Callables remain **append-only** (B3): reverse rows are created; original settlement
documents are never mutated.

### Firestore rules

- **No change to the settlement `hasOnly()` key lists** (event
  `security/firestore.rules:900`, group `:1153` post-#891). A client create carrying
  `correctionOfSettlementId` already fails `hasOnly()` — pin this with rules tests for
  both collections (delta 2). Add a comment at both key lists cross-referencing the
  trigger skips (delta 3).
- **Tighten `groupSettleUpId`**: the current shared guard in `validSettlementCore`
  (`:104`; guard at `:119`: `!('groupSettleUpId' in data) || data.groupSettleUpId is string`)
  accepts blank strings. Require a non-empty, non-whitespace string when present, for
  unmarked creates (marked creates are Admin-only and never rules-evaluated). Rules
  have no `trim()` — use a rules-compatible non-whitespace check. Note
  `string.matches()` is a **full-string RE2 match**, so write it to full-match (e.g.
  `data.groupSettleUpId.matches('.*[^ ].*')` — a non-space char anywhere), NOT a
  substring "contains." Blank strings are denied rather than normalized differently by
  rules, model code, and history grouping.
- Settlement updates stay hard-denied (event `:976`, group `:1212` post-#891) — do not reopen
  note/soft-delete edits. Beware the documented trap: `validEventSettlementUpdate` is
  dead code behind `allow update: if false`; editing it does nothing.
- Rules do **not** validate marker inverse shape. Marker inverse/source validation
  lives in the server callables. Rules never compare `settledAt` strings.

The conceptual shape contract (enforced by the callables, not rules):

- **Reverse row the callable writes:** carries `correctionOfSettlementId` = a
  non-empty path-safe string that is the original's id and is not the reverse's own
  new document id; inverse payer/recipient vs the original; equal `amountFils` and
  `currency`; `note` = the caller's `correctionNote` written **verbatim** for display
  compat (bounded by generic free-text validation only — see callables).
- **Original being corrected:** must exist in the same collection
  (`groups/{gid}/events/{eid}/settlements/{settlementId}` for event scope,
  `groups/{gid}/settlements/{settlementId}` for group scope), be live
  (`isDeleted != true`), and be unmarked (no `correctionOfSettlementId`) and not
  itself a bounded-legacy note-only correction.

**Sentinel set — frozen historical constant, legacy-classification only.** The
callable holds one hand-copied TS constant:

```ts
// functions/src/callables/shared/settlementCorrection.ts
const CORRECTION_NOTE_SENTINELS = [
  'Correction of a recorded payment', // EN — mirrors lib/l10n/app_en.arb:1039
  'تصحيح لدفعة مُسجَّلة',              // AR — mirrors lib/l10n/app_ar.arb:411
];
```

It is used **only** to classify a pre-existing original as a legacy note-only
correction (to reject double-correction), **never** to validate the incoming
`correctionNote`. A Node callable cannot import Flutter-generated Dart
localizations, so the "derive from the same generated-localizations set / auto-extends
per locale" phrasing of earlier drafts is dropped — it is factually impossible and
also unnecessary: **this set never needs to grow.** Legacy note-only corrections can
exist only for locales that shipped *before* the marker (EN/AR); any locale added
after this foundation always writes a marker, so it never produces a note-only
correction needing sentinel classification. Pin the frozen list with a cross-list
guard test asserting it equals the current `app_en.arb:1039` / `app_ar.arb:411`
values (renaming a *shipped* sentinel means retaining the historical string too, so
old rows still classify). Adding a *new* locale requires **no** TS change.

### Correction callables

Add server-authoritative callables, exported from `functions/src/index.ts` as
`export { … } from` re-exports (required — a bare `export const` in `index.ts` is
invisible to `tool/list_expected_functions.sh` and escapes the deploy drift check):

```txt
correctSettlement(groupId, scope, settlementId, eventId?, correctionNote)
correctLogicalSettleUp(groupId, groupSettleUpId, correctionNote)
```

Both defined with `{ enforceAppCheck: true }` (matches `addShadowMember.ts:46`,
`joinGroupByInviteCode.ts:178`, `deleteGroup.ts:319`).

Add methods to `FirebaseFunctionsService`
(`lib/core/services/firebase_functions_service.dart`):

```dart
Future<CorrectSettlementResult> correctSettlement({
  required String groupId,
  required String scope, // 'event' | 'group'
  String? eventId,
  required String settlementId,
  required String correctionNote,
})

Future<CorrectSettlementResult> correctLogicalSettleUp({
  required String groupId,
  required String groupSettleUpId,
  required String correctionNote,
})
```

Wire result shape for both:

```ts
{
  eventScopeWrites: number,
  groupScopeWrites: number,
  repaired: boolean,
  noop: boolean,
  shouldBumpLedgerRevision: boolean,
}
```

Dart parses this into a typed `CorrectSettlementResult`. For direct event corrections
`shouldBumpLedgerRevision` is true when the callable wrote or confirmed the event
reverse; for standalone group corrections it is false; for logical corrections it is
true when any event-scope reverse was written, confirmed, or repaired.

Both callables must:

- require auth and group membership;
- validate raw path/note inputs before constructing Firestore paths: `groupId`,
  `eventId`, `settlementId` via the existing `validId(value, label)`
  (`functions/src/callables/shared/ids.ts:7`); `groupSettleUpId` must be a non-empty
  string without `/` within a bounded length, used only as data and as `shortHash`
  input, never embedded raw in a document id;
- mirror the rules write-lock `groupAllowsClientWrites`
  (`security/firestore.rules:134`) server-side — reject missing, `isDeleted`,
  `deletingInProgress`, `claimingInProgress`, or `accountDeletionInProgress` groups.
  Precedent: the identical four-flag inline gate in `addShadowMember.ts:79-82`
  ("Honor the same write-lock as firestore.rules… mirroring joinGroupByInviteCode");
- accept `correctionNote` as a display-only string and write it **verbatim** on the
  reverse row, bounded by generic free-text validation only (non-empty after trim,
  length ≤ the `validFreeText` cap, no control chars). Do **not** validate it against
  the sentinel set — the note is never the discriminator (the structural inverse
  contract is), and a Node callable cannot import the Dart sentinel source. A
  non-sentinel note simply fails to render the "Correction" tag on the note-based
  display until the marker-based UI migration; it never affects money or
  classification;
- use Admin SDK only after validation;
- be append-only — never mutate original settlements.

`correctSettlement` must:

- for `scope: 'event'`: require non-empty `eventId`, load
  `groups/{gid}/events/{eid}/settlements/{settlementId}`, mirror
  `eventAllowsClientWrites` (`firestore.rules:188` — group writable + event exists +
  event not soft-deleted; **not** the expense-only closed-event gate
  `eventAcceptsExpenseWrites`: settlements stay writable after close), and require
  both parties are event participants;
- for `scope: 'group'`: load `groups/{gid}/settlements/{settlementId}` and require
  both parties are current group members;
- reject any original with a non-empty `groupSettleUpId` — tagged originals belong to
  one logical group-settle and are corrected only via `correctLogicalSettleUp`, never
  piecemeal (mirrors the client-side hidden correct button on tagged rows, #752);
- reject missing/deleted originals and originals already classified as marked
  corrections;
- reject bounded legacy note-only correction originals using the exact
  same-collection inverse guard before writing: original note is a sentinel; the same
  collection holds a live unmarked source row with inverse payer/recipient, equal
  `amountFils` **and** `currency`, `isDeleted === false`, `deletedAt == null`,
  non-sentinel note; and `groupSettleUpId` absent on both or exactly equal on both.
  **This content guard is the ONLY detector for pre-#889 correction rows** — those
  were written by the deleted `SettlementCorrectionService` with uuid ids (not the
  `correction_${shortHash(...)}` deterministic scheme), so the deterministic-id
  existence check can never find them. The exactness of this match is therefore
  load-bearing across the migration boundary: it must be strict enough that two
  independent legitimate offsetting payments (a real later payment that happens to
  reverse an earlier one) are NOT misclassified as a correction pair — the
  sentinel-note requirement on the correction side is what separates the two, which
  is exactly why #889 exists. **Accepted asymmetric false-positive:** if the original
  X you are correcting *coincidentally* carries the exact localized sentinel as a real
  user note AND an independent inverse real payment Y (same amount/currency, inverse
  parties, non-sentinel note) exists live in the same collection, this guard
  misclassifies X as an already-recorded legacy correction of Y and no-ops the
  correction. This is fail-closed (never wrong money, only a blocked correction),
  vanishingly rare (the user must type the exact localized sentinel string as a
  genuine note), and consistent with #889's own "note is not a safe discriminator"
  premise — a known accepted limitation, pinned as such in the callable-test matrix,
  not a bug to design around;
- if the selected original is a live unmarked source row that already has a live
  bounded-legacy note-only inverse correction in the same collection, return
  success/no-op with no new write (prevents double-reversing pre-marker-corrected
  rows while keeping normal sentinel-note payments without an exact inverse
  correctable);
- write one deterministic reverse row in the same collection as the original.

`correctLogicalSettleUp` must:

- reject blank `groupSettleUpId`;
- load all live group-scope and event-scope settlement docs with that
  `groupSettleUpId`: group-scope by querying `groups/{gid}/settlements`; event-scope
  by iterating the group's **live events only** (`groups/{gid}/events` filtered
  `isDeleted == false` — mirroring the client's `watchGroupEvents` query,
  `event_service.dart:40`, and the oracle's soft-deleted-event skip in `recomputeNet`,
  `groupNetBalance.ts:627-633`) and querying each live event's `settlements`
  subcollection (or an equivalent ancestor/path-scoped lookup — never an unscoped
  collectionGroup scan). A slice under a soft-deleted event is **out of the balance
  universe on both client and server** — the oracle skips soft-deleted events
  wholesale ("their live children must NOT enter the balance"), so such a slice
  contributes zero. It is therefore **IGNORED**: never enumerated, never a failure
  reason. Reversing the live event slices plus the residual group settlement is
  money-correct and matches today's client path —
  `groupTaggedEventSettlementsProvider` (`group_balance_provider.dart:252-268`)
  draws `_correctLogicalSettleUp`'s originals from the live events list only ("a
  soft-deleted event never enters the events list"), so the current client
  `WriteBatch` correction also skips such slices and succeeds;
- for every event-scope original, mirror `eventAllowsClientWrites` on that event and
  require both parties are event participants; for every group-scope residual
  original, require both parties are current group members;
- reject if no originals exist;
- detect already-corrected logical sets using marker-classified reverse rows and the
  bounded legacy exact-inverse guard; use only unmarked, non-legacy-correction source
  rows as originals;
- write one reverse row per original, in the original's own collection, with
  `correctionOfSettlementId: original.id`, the same `groupSettleUpId` preserved, and
  the caller's localized correction-note sentinel for display compatibility;
- stay idempotent for retry/double-tap and partial repair via deterministic reverse
  ids.

Reverse write shapes (mirror the current `SettlementCorrectionService` /
`addSettlement` shapes exactly so `validEventSettlementBase` / group base `hasOnly()`
lists would accept the non-marker keys; the marker key is Admin-only):

Event reverse at `groups/{gid}/events/{eid}/settlements/{newId}`:

```ts
{
  id: newId,
  eventId: eid,
  payerParticipantId: original.recipientParticipantId,
  recipientParticipantId: original.payerParticipantId,
  payerName: original.recipientName ?? null,
  recipientName: original.payerName ?? null,
  amountFils: original.amountFils,
  currency: original.currency,
  note: correctionNote,
  isDeleted: false,
  deletedAt: null,
  settledAt: nowIso,
  createdBy: callerUid,
  ...(original.groupSettleUpId ? { groupSettleUpId: original.groupSettleUpId } : {}),
  correctionOfSettlementId: original.id,
}
```

Group residual reverse at `groups/{gid}/settlements/{newId}`:

```ts
{
  id: newId,
  groupId: gid,
  eventId: gid,
  scope: 'group',
  payerParticipantId: original.recipientParticipantId,
  recipientParticipantId: original.payerParticipantId,
  payerName: original.recipientName ?? null,
  recipientName: original.payerName ?? null,
  amountFils: original.amountFils,
  currency: original.currency,
  note: correctionNote,
  isDeleted: false,
  deletedAt: null,
  settledAt: nowIso,
  createdBy: callerUid,
  ...(original.groupSettleUpId ? { groupSettleUpId: original.groupSettleUpId } : {}),
  correctionOfSettlementId: original.id,
}
```

Concurrency/idempotency:

- Deterministic reverse ids so retries and concurrent calls cannot duplicate reverses:
  direct `correction_${shortHash(original.ref.path)}`; logical
  `correction_${shortHash(groupSettleUpId)}_${shortHash(original.ref.path)}`.
  `shortHash` is a new deterministic, path-safe, bounded helper in
  `callables/shared/ids.ts` (delta 5) — a **≥16-hex-char** sha256 slice so intra-group
  id collisions stay negligible (a collision is fail-closed anyway: the second
  correction finds a non-validating reverse and fails the whole call, never wrong
  money). Never raw ids/paths in a document id.
- Treat an already-existing deterministic reverse that validates structurally as the
  expected correction as success/no-op: same collection, inverse parties, equal
  amount/currency, same `correctionOfSettlementId`, matching `groupSettleUpId` state,
  `isDeleted === false`, `deletedAt == null`. Must NOT require
  `createdBy == callerUid` or `note == correctionNote`, so a retry by a different
  member or locale stays idempotent.
- If some expected deterministic reverses exist, complete only the missing ones; never
  a second reverse per original. Write all missing reverses in one create-only
  transaction/batch after validation; never `set`/overwrite an existing reverse.
- If any deterministic reverse id exists but does not validate as the expected
  correction, fail the entire call with no new writes.
- Logical corrections preserve the live all-or-nothing behavior: if a call cannot
  create every missing expected reverse in one invocation, it fails with no partial
  new writes.

Shared validation module: `functions/src/callables/shared/settlementCorrection.ts` —
houses the inverse-contract validator, the bounded legacy guard, and the
marker-classification used by both callables. Exported so future #283/#753 consumers
(correction activity labeling, atomic logical correction PR2) import one classifier
instead of duplicating it. No trigger imports it in this split (delta 3).

### Existing notification derived surface

`settlementNotifier` (`functions/src/triggers/settlementNotifier.ts` —
`eventSettlementNotifier` `:89`, `groupSettlementNotifier` `:100`) must skip marked
corrections: early-return in `notifySettlement` when
`data.correctionOfSettlementId` is a non-empty string (alongside the existing
`isDeleted` early-return). Presence-only, no read (delta 3). Without this, the first
marker-enabled correction sends the counterparty a fresh-payment push. (Today's
client-direct corrections DO send that push — a live wart this split fixes for the
callable path.) Unmarked normal settlements, including sentinel-note user text, keep
notifying.

### Existing write-rate derived surface

`writeRateMonitor` (`functions/src/triggers/writeRateMonitor.ts`) must skip marked
corrections in `eventWriteRateMonitor` (T1, settlements module) and
`groupSettlementWriteRateMonitor` (T2): presence-only check on
`correctionOfSettlementId`, mirroring the T3 `expense_*` skip's un-forgeability
rationale (predicate `:136-137`, comment block `:127-135`). T1
`eventWriteRateMonitor` counts settlements via `COUNTED_EVENT_MODULES` (`:34`, `:116`)
and T2 counts every group-settlement create unconditionally (`:122-125`), so both need
the new early-return. These rows are server-owned reverse writes stamped
`createdBy: callerUid` — a 21-slice logical correction would otherwise bill 22 counted
writes to one tap. Normal unmarked settlement creates stay counted.

### Minimum client guards

This split does not migrate all payment-history/ledger display, but it must remove
note text from correction **write-affordance** gates and **write idempotency**.
**Display state stays note-based; only the write-affordance moves to marker/legacy.**
The two are physically distinct code paths in `settle_up_page_body.dart` — the
earlier draft mislocated the solo fix onto the display line, which §Explicit
Non-Scope simultaneously protects. The corrected mapping (all line numbers verified
against the review tree):

**DISPLAY — stays note-based, do NOT change (protected by Non-Scope):**
- `_HistoryTile` `isCorrection = isCorrectedLogical || isCorrectionNote(settlement.note)`
  (`:983-984`) → drives the accent, undo icon, and "Correction" tag only.
- `LogicalHistoryRow.isCorrected` built at `:851`
  (`members.any((m) => isCorrectionNote(m.note))`) → passed as
  `isCorrectedLogical: row.isCorrected` (`:752`) for that display.
- `groupSettlementHistory`'s `totalAmount`/`representative` derivation, which also
  note-classifies (`:831` `originals = members.where((m) => !isCorrectionNote(m.note))`)
  → display total, stays note-based.

**WRITE-AFFORDANCE — moves to marker + bounded-legacy in THIS split:**
- **Logical rows.** Add a SECOND named field `bool affordanceCorrected` to
  `LogicalHistoryRow` (alongside the existing display `isCorrected`), built from
  marker classification across the tagged set: true iff every eligible original in the
  set provably has a valid marked reverse (`member.isMarkedCorrection` present for its
  reverse) or a bounded-legacy exact inverse. The null-ing at `:753-755` switches from
  `row.isCorrected` to `row.affordanceCorrected`
  (`onCorrectLogical: row.affordanceCorrected ? null : () => onCorrectLogical!(...)`);
  `:752` `isCorrectedLogical: row.isCorrected` (display) is left as-is. When the marker
  set is only partially present, `affordanceCorrected` is false so the action stays
  available for the callable to repair. **Intentional transient:** during a
  partial-marker repair a logical row may render as "corrected" (display
  `isCorrected` is note-based, `:851`) while its Correct action stays live
  (`affordanceCorrected` false) — that display/affordance mismatch is by design so
  the callable can repair the missing reverses.
- **Solo rows.** The real gate is the Correct **button** visibility at `:1104-1109`
  (`((onCorrect != null && settlement.groupSettleUpId == null) || onCorrectLogical != null)
  && payerId/recipientId present`) — which references **no** correction state today, so
  a solo note-only correction row currently still shows Correct. Add `&& !soloCorrectionHidden`
  to the solo branch (guard only the `onCorrect != null && groupSettleUpId == null`
  path, not the logical path), where `soloCorrectionHidden` is a new bool computed
  upstream in the `_HistoryTile`-building loop and threaded into `_HistoryTile`:
  `settlement.isMarkedCorrection || <bounded-legacy note-only inverse present>`.
  **The bounded-legacy inverse lookup must use that screen's own settlement list**
  (the two callers pass different lists — the event screen renders solo rows from its
  event-settlements list `settle_up_page_body.dart:717-728`; the group screen from
  `groupSettlementHistory(settlements)` `:730-757`), so compute `soloCorrectionHidden`
  in each screen's own build, never against a cross-screen list. Do **not** touch
  `:984`.
- `_correctLogicalSettleUp` (`group_settle_up_screen.dart:1116-1119`, currently
  note-gated `if (tagged.any((s) => isCorrectionNote(s.note))) return;`) uses
  `Settlement.isMarkedCorrection` + the bounded legacy guard for its local
  already-corrected decision, then calls the callable — the server stays authoritative
  for selecting originals and writing reverses. Hide locally only when every eligible
  original provably has a valid marked reverse or bounded-legacy inverse; otherwise
  keep the action available so the callable can repair partial marker sets.
- Bounded legacy guard (client mirror of the callable's): a note-only row counts as an
  already-recorded correction only when it carries the sentinel AND an exact inverse
  unmarked source row exists in the same `groupSettleUpId` set / visible list
  (inverse payer/recipient, same `amountFils` and `currency`, source not deleted,
  source unmarked, source note non-sentinel). Prevents re-reversal of old rows without
  classifying arbitrary sentinel-note payments as corrections. A normal unmarked
  settlement whose note equals the sentinel but has NO exact inverse source stays
  correctable.

### Client liveness

After a successful correction callable:

- `correctSettlement(scope: 'event')` bumps `ledgerRevisionProvider`
  (`lib/features/ledger/providers/expense_provider.dart:41`) so the home one-shot
  balance aggregation sees the new event reverse (#104/#233 contract: every new
  event-level settlement write path must bump).
- `correctLogicalSettleUp` bumps when the callable reports any event-scope reverse
  written or repaired (`shouldBumpLedgerRevision`).
- Standalone group-only correction does not bump (group settlements are live-watched).
- No queued-write success copy anywhere on the correction paths (online-only). All
  THREE correction sites — solo `onCorrect` (`settle_up_screen.dart:371`), group
  `onCorrect` (`group_settle_up_screen.dart:270`), and `_correctLogicalSettleUp`
  (`group_settle_up_screen.dart:1093`) — treat an offline/failed correction callable
  identically: surface the existing settlement write-error copy
  (`settlementWriteErrorMessage` — already the failure copy at
  `settle_up_screen.dart:862` and `group_settle_up_screen.dart:929/:1070/:1132/:1194`) and
  write nothing. Never show the queued/"will sync" success copy
  (`settleUpRecordedWillSync`, `settle_up_screen.dart:844`,
  `group_settle_up_screen.dart:907/:1052/:1178`) — that copy is for offline-queueable
  client-direct writes, which corrections no longer are.

## Explicit Non-Scope

- Does **not** touch #831/#891's activity fan-in. The pinned "corrections emit no
  `event_settlement` activity row" contract holds under the callable mechanism (the
  callable writes no activity row). Re-pointing the #891 test is **not** a
  same-assertion move: its "no activity row" check stays (now trivially true), but its
  companion "reverse settlement written to the fake DB" check must convert to a
  "`correctSettlement(scope:'event')` invoked" check, because the mocked callable
  writes nothing to the fake DB (see delta 4). Correction activity labeling (showing
  corrections AS corrections in feeds) is future #283/#753 work that this marker
  enables.
- Does **not** migrate note-based UI/history **display**: the `isCorrection` accent /
  undo icon / "Correction" tag (`:983-984`), the `LogicalHistoryRow.isCorrected`
  display flag (`:851` → `:752`), and the `totalAmount`/`representative` derivation
  (`:831`) all stay `isCorrectionNote`-based; a separate UI/legacy split decides that
  transition. Only the **write-affordance** gates (`:1104` solo button, `:753` logical
  null-ing) and write idempotency move to marker/bounded-legacy here — that is not a
  display change and does not contradict this line.
- Does **not** backfill historical note-only correction rows.
- Does **not** add correction-of-correction support.
- Does **not** change the balance oracle or aggregates: reverse rows are ordinary
  settlement docs to `recomputeNet`/`balanceAggregator` — the marker is
  oracle-invisible, same contract as `splitExplanation` and `groupSettleUpId` (never
  wire the server oracle to read it).

## Tests

Client/service tests:

- `Settlement.fromFirestore` reads a string `correctionOfSettlementId`; non-string /
  empty / absent values read as null / non-marked (`isMarkedCorrection` false).
- Normal event and group settlement writes omit the marker, including when `note`
  equals an EN/AR sentinel.
- Event correction invokes `correctSettlement(scope: 'event')` with the original id
  and localized sentinel; solo group correction invokes `scope: 'group'`; logical
  correction invokes `correctLogicalSettleUp` (functions service mocked).
- Post-correction: no `event_settlement` activity row (re-pointed #891 test).
- `_correctLogicalSettleUp` treats an unmarked tagged row with a sentinel note as an
  original, not as already corrected; hides/no-ops locally only when every eligible
  original has a valid marked reverse or bounded-legacy inverse; keeps the action
  available for partial marker sets.
- `groupSettlementHistory` builds `isCorrected` (display, note-based, `:851`) and
  `affordanceCorrected` (marker/bounded-legacy) as SEPARATE fields: a fully-marked set
  nulls `onCorrectLogical` via `affordanceCorrected`; an unmarked sentinel-note tagged
  source row keeps `isCorrected` true for display BUT `affordanceCorrected` false, so
  `onCorrectLogical` is NOT nulled; a partially-marked set keeps the action available.
- Solo history rows drive the hide at the button gate (`:1104`), not the display line
  (`:984`, which stays unchanged): a marked solo row and a bounded-legacy note-only
  solo row both hide Correct; a sentinel-note solo row with no exact inverse source
  stays correctable; its display accent/tag (`:984`) is unaffected either way.
- Ledger revision: event correction success bumps; logical success bumps iff any
  event-scope reverse written/repaired; group-only success does not bump.
- Offline correction actions show no queued-success copy and write nothing.

Rules tests (`functions/test/firestore-rules-publish-readiness.test.ts`):

- Unmarked event and group settlement creates remain allowed.
- Client-created event settlement with `correctionOfSettlementId` is denied
  (hasOnly-omission pin); same for group settlements.
- Blank/whitespace `groupSettleUpId` is denied on create; non-empty stays allowed.
- No test implies `settledAt` string ordering.

Callable tests (emulator, both callables):

- `correctSettlement` event path rejects: missing auth, non-member caller,
  locked/deleted group (all four flags), deleted event, non-participant parties,
  missing/deleted/marked/bounded-legacy originals, tagged `groupSettleUpId` original,
  unsupported `scope`, missing `eventId` for event scope, and an empty/over-length/
  control-char `correctionNote` (generic free-text bounds ONLY — a **non-sentinel**
  note is ACCEPTED and written verbatim, proving no locale-sentinel input validation).
- Cross-list guard test: `CORRECTION_NOTE_SENTINELS` (TS) equals the current
  `app_en.arb:1039` / `app_ar.arb:411` sentinel values — catches a shipped-sentinel
  rename that drops the historical string (which would silently stop classifying old
  legacy rows).
- Event path writes the exact event reverse map with deterministic hashed id; retry is
  idempotent; returns `shouldBumpLedgerRevision: true`; returns no-op with no write
  when the source already has a live bounded-legacy inverse; fails without writing
  when a deterministic reverse id exists but does not validate.
- Group path: same rejection matrix (group-member parties), exact group reverse map,
  idempotent retry, `shouldBumpLedgerRevision: false`, legacy no-op, invalid-collision
  failure.
- `correctLogicalSettleUp` rejects: missing auth, non-member caller, blank/path-unsafe
  `groupSettleUpId`, locked/deleted group, invalid parties, invalid note, no originals.
- A logical set with one slice under a **soft-deleted event** reverses the live event
  slices + residual and SUCCEEDS; the soft-deleted event's slice is ignored (out of
  balance universe — never enumerated, never reversed, never a failure reason).
- Logical path writes exact event/group reverse maps with deterministic path-safe ids
  derived from `groupSettleUpId` + `original.ref.path`; succeeds for 21 event slices
  plus residual (no rules-read-limit dependence); idempotent for retry/double
  invocation; completes missing reverses for partial marker sets; all-or-nothing on
  invalid deterministic-id collision; event lookups scoped to the target group's
  ancestry only; `shouldBumpLedgerRevision` true for event-only/mixed/partial-repair,
  false for group-only no-op; overlong valid inputs still produce bounded path-safe
  ids; correction of settlements after event close succeeds (settlements-stay-live
  contract — `eventAllowsClientWrites`, not `eventAcceptsExpenseWrites`).

Trigger tests:

- `settlementNotifier` skips marked corrections (event + group creates); still sends
  for unmarked settlements including sentinel-note user text.
- `writeRateMonitor` T1/T2 skip valid marked corrections; unmarked settlement creates
  stay counted.

## Deploy

Gate-category: Cloud Functions + rules. One deploy ceremony after merge
(`tool/deploy_firebase_backend.sh` moves `backend-deployed`): two new callables
(`export { … } from` re-exports so `tool/list_expected_functions.sh` sees them), two
modified triggers, modified rules (`groupSettleUpId` blank-deny + comments). No client
compat ordering (no real users).

## Embedded Verification Pass (7 principles, re-run 2026-07-04 against rebased `origin/main` `6cda9da3` — PR #891 merged)

1. **Callsite classification.** Marker writes are OUTBOUND (settlement docs, Admin).
   Readers: `Settlement.fromFirestore` → `groupSettlementHistory` / solo-correct
   affordances (BOTH — they gate the correction write affordance → treated as
   OUTBOUND, specced above); `settlementNotifier` / `writeRateMonitor` (INBOUND,
   skip-only); oracle/aggregator ignore unknown fields (verified: `recomputeNet`
   consumes amount/parties/soft-delete only). No display surface renders the marker.
2. **Concrete claims re-verified by grep/read this session:** `validId` at
   `ids.ts:7`; `shortHash` ABSENT (new helper); `groupAllowsClientWrites`
   rules `:134` (4 flags), `eventAllowsClientWrites` `:188`,
   `eventAcceptsExpenseWrites` `:206` (expense-only close gate — settlements keep
   using the former); `validEventSettlementCreate` `:916` / event `allow update: if
   false` `:976`; `validGroupSettlementCreate` `:1177` / `:1212`; hasOnly key lists
   `:900` / `:1153` (include `groupSettleUpId`, exclude the marker);
   `groupSettleUpId` type-only guard in `validSettlementCore` `:104`/`:119`; sentinels `app_en.arb:1039` /
   `app_ar.arb:411`; `isCorrectionNote` `correction_note.dart:16` (locale-set based);
   `SettlementCorrectionService.reverseLogicalSettleUp` (client WriteBatch, uuid ids)
   called from `group_settle_up_screen.dart:1155`; group `onCorrect` `:270-280`;
   `onCorrectLogical` `:285`; note-gated logical guard `:1116-1119`; DISPLAY
   `isCorrection` OR at `settle_up_page_body.dart:983-984` (NOT the affordance);
   solo Correct **button** gate `:1104-1109`; logical `onCorrectLogical` null-ing
   `:753-755`; `LogicalHistoryRow.isCorrected` build `:851`; `groupSettlementHistory`
   `:812`; `eventSettlementNotifier`/`groupSettlementNotifier`
   `settlementNotifier.ts:89/:100` (no correction awareness today); `writeRateMonitor.ts`
   T1 counts the settlements module (`:34`/`:116`), T2 `:122-125` unconditional, T3
   `expense_*` skip predicate `:136-137`; `enforceAppCheck: true` precedent
   `addShadowMember.ts:46`; four-flag server mirror `addShadowMember.ts:79-82`;
   `index.ts` uses `export { } from` re-exports; `ledgerRevisionProvider`
   `expense_provider.dart:41`; correction site on merged main
   `settle_up_screen.dart:371-385` (`canRecord ? … logActivity: false`), `_recordSettlement`
   `:742`/`:752`/`:800`; group correction site `group_settle_up_screen.dart:270-280`.
3. **One read-path per write-path.** Marked event reverse → read by
   `eventSettlementNotifier` (skips), `eventWriteRateMonitor` (skips),
   `balanceAggregator`/`recomputeNet` (folds as ordinary settlement — intended),
   settle-up history tiles (renders as correction via note-compat display; affordance
   hidden via marker). Marked group reverse → same set on the group path.
4. **Fields enumerated from the type.** `Settlement` 16 fields listed above from the
   model file, not memory; reverse maps enumerate every Firestore key explicitly.
5. **Exact contracts spelled out.** Callable signatures, wire result shape, reverse
   maps, deterministic id scheme, skip predicates, sentinel strings — all literal.
6. **Arithmetic decomposition.** No new arithmetic: reverses copy `amountFils` /
   `currency` verbatim and swap parties; conservation is inherited from the original
   rows (a reverse exactly cancels its original per-currency). The oracle folds
   event/group reverses by collection path exactly as it folds originals (#752
   contract, untouched).
7. **Orthogonal-axis check (identity + time).** Identity: third-party recorder — any
   group member may invoke corrections (matches #752's relaxed
   `validEventSettlementCreate`/`isGroupMember` posture); idempotency deliberately
   ignores `createdBy`/locale so a different member's retry no-ops. Time: event-closed
   axis — corrections must keep working after event close (settlements-stay-live);
   pinned by a callable test. Offline axis: corrections go online-only (explicit,
   accepted); normal payments keep offline replay.

## Gate round-1 resolutions (applied 2026-07-04)

Two P1s and the coupled P2/P3s from the first fresh-context pair, resolved against
re-read code:

- **[P1-A] Solo Correct affordance was mislocated.** The earlier draft put the
  `isMarkedCorrection` hide on `settle_up_page_body.dart:984`, which is the
  **display-only** `isCorrection` flag (accent / undo icon / "Correction" tag) that
  §Explicit Non-Scope simultaneously protects — a self-contradiction. The real solo
  Correct **button** gate is `:1104-1109` and references no correction state today.
  Fixed: solo hide moves to `:1104` via a new upstream `soloCorrectionHidden` bool;
  logical hide moves off the note-based `row.isCorrected` onto a new
  `LogicalHistoryRow.affordanceCorrected` field driving the `:753` null-ing; all
  display lines (`:984`/`:851`/`:831`/`:752`) stay note-based and untouched.
- **[P1-B] "Derive the sentinels from generated Dart l10n" was impossible.** A Node
  callable cannot import Flutter-generated localizations. Fixed: the callable does NOT
  validate the incoming `correctionNote` (written verbatim, generic free-text bounds
  only), and the sentinel set is a **frozen hand-copied `{EN, AR}` constant used only
  to classify pre-existing legacy note-only rows** — it never grows (post-marker
  locales always write markers), pinned by a cross-list guard test. This removes the
  new-locale correction-outage the earlier phrasing implied.
- **[P2] Migration double-reverse:** made explicit that pre-#889 uuid-id reverses are
  detected ONLY by the bounded-legacy content guard (never the deterministic-id
  check), so that guard's exactness is load-bearing across the boundary.
- **[P2] `LogicalHistoryRow` split** now names the second field (`affordanceCorrected`)
  rather than gesturing at "two states."
- **[P2] #891 dependency** promoted to a hard, stated prerequisite in the header;
  delta 4 must be re-verified against #891's merged shape.
- **[P3]** `shortHash` ≥16-hex bound stated; `writeRateMonitor` citation corrected to
  predicate `:136-137` / comment `:127-135`; `:831` display derivation named as
  note-based-and-unchanged. The blank-`groupSettleUpId` rules tightening is retained
  here but is independently extractable to a one-line PR if One-PR-does-one-thing is
  preferred.

## Gate round-2 resolutions (applied 2026-07-04)

Round 2 returned **1 P1** — and it was purely environmental: PR #891 **merged mid-Gate**
(`6cda9da3`, 14:40Z), so the review base (`f51acd2c`) went stale. Both reviewers
confirmed the spec's *logic* clean (rubric 0 P1; adversary's only P1 was the base).
Resolved:

- **[P1] Stale base would clobber #891's rules.** The branch is **rebased onto
  `6cda9da3`** (post-#891); the header base is updated; the `groupSettleUpId` rules
  delta is now explicitly required to be additive over #891's `event_settlement`
  allow-list, verified by `git diff origin/main -- security/firestore.rules`. All
  `settle_up_screen.dart` / `firestore.rules` line numbers re-run against the rebased
  tree (`settle_up_screen.dart` onCorrect `:371-385`; group rules `+4`:
  `validGroupSettlementCreate:1177`, `allow update:if false:1212`, hasOnly `:1153`).
  `settle_up_page_body.dart` was untouched by #891 — the round-1 affordance citations
  still hold.
- **[P2] Soft-deleted-event enumeration** — round 2 resolved this as "enumerate all
  events including `isDeleted:true`; fail the whole call on a soft-deleted slice."
  **Round 3 REVERSED that fix as a regression** (see Gate round-3 resolutions):
  soft-deleted events are out of the balance universe on both client and server, so
  their slices are ignored, and reversing live slices + residual matches today's
  client and the oracle.
- **[P2] Re-pointed #891 test is NOT "same assertion"** — the settlement-written
  assertion converts to a callable-invocation assertion under the mocked service;
  fixed in delta 4, §Write paths, and Non-Scope.
- **[P3]** `canRecord ? … : null` preservation on the event `onCorrect` stated;
  `group_settle_up_screen.dart`'s own now-dead `logActivity` param removal added
  (symmetry); named-arg call examples; rules citation drift corrected. The
  blank-`groupSettleUpId` extraction remains an optional split.

## Gate round-3 resolutions (applied 2026-07-04)

- **[P1] Round-2's soft-deleted-event enumeration was REVERSED as a regression.**
  Both round-3 reviewers flagged it: a slice under a soft-deleted event is out of the
  balance universe on both client (`watchGroupEvents` filters
  `isDeleted == false`, `event_service.dart:40`; `groupTaggedEventSettlementsProvider`
  never sees it, `group_balance_provider.dart:252-268`) and server (`recomputeNet`
  skips soft-deleted events wholesale, `groupNetBalance.ts:627-633`) — it contributes
  zero, so NOT reversing it is money-correct, and today's client `WriteBatch`
  correction already drops such slices and succeeds. The round-2 shape would have
  made any logical settle-up with a slice under a later-soft-deleted event
  permanently uncorrectable. `correctLogicalSettleUp` now enumerates **live events
  only** and ignores soft-deleted-event slices (never enumerate-then-reject, never
  fail the call for them); the callable-test matrix gained the matching
  "soft-deleted slice → live slices + residual reversed, SUCCESS" case and dropped
  "deleted event for any event original" from the rejection list.
- **[P2] `SettlementCorrectionService` deletion reference count expanded**: also
  remove `settlementCorrectionServiceProvider` (`group_balance_provider.dart:35-38`)
  and rewrite `group_settle_up_correct_test.dart` (subclass `:100`, override `:145`)
  to a `FirebaseFunctionsService` mock — not a re-point.
- **[P2] Offline correction treatment named per site** (solo/group/logical): existing
  `settlementWriteErrorMessage` copy, nothing written, never `settleUpRecordedWillSync`.
- **[P3]** Partial-marker display/affordance transient documented as intentional;
  citation nits fixed (`eventAcceptsExpenseWrites` `:206`; `addShadowMember.ts:79-82`).

## Gate outcome

Fresh-context Gate (run-the-gate) run to convergence, 2026-07-04:

- **Round 1** — 2 P1 (affordance-guard mislocation `:984`→`:1104`; infeasible "derive
  sentinels from Dart l10n"). Fixed.
- **Round 2** — 1 P1 (environmental: PR #891 merged mid-run; stale base would clobber
  #891's `event_settlement` rules allow-list). Rebased onto `6cda9da3`; fixed.
- **Round 3** — 1 P1 (round-2's own soft-deleted-event enumeration fix was a
  regression — soft-deleted slices are out of the balance universe; must enumerate
  LIVE events only). Reversed.
- **Round 4** — **0 P1 / (P2+P3 folded)** from BOTH the rubric reviewer AND the
  orthogonal adversary in the same round. **Gate PASSED.**

Each round used a fresh pair of zero-history Opus reviewers (rubric + orthogonal
adversary); neither saw the other's verdict. Extra rounds were driven by an external
merge (#891) and one overcorrecting fix, not spec over-scoping — the money design was
confirmed conservation-safe and idempotent in rounds 3 and 4.

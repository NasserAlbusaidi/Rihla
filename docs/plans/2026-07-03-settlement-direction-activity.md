# Settlement direction in activity feeds (#818 Wave 3.1)

**Refs #818.** Review finding: every settlement row in the activity feeds reads
"recorded a settlement" (direction discarded) and the in-group feed renders an
unconditional green `+` amount — a money-feed lie for the payer. Gate-category:
data-shape change with a write-path (activity metadata) and a read-path (three feed
surfaces + search), plus a `firestore.rules` edit.

## Verified terrain (all re-checked in-session against origin/main, 2026-07-03)

- **Exactly ONE code path writes settlement activity rows**: the group settle-up screen,
  at two sites — the atomic path (`group_settle_up_screen.dart:1019-1036`) and the #752
  decomposed path (`:881-896`, which logs **once** for the whole logical settle-up; the
  exactly-one-call invariant is pinned by `group_settle_up_decompose_test.dart:297-299`).
  Both write the identical shape:
  `type: 'group_settlement'`, `description: 'settled {formatted} with {counterpartyName}'`,
  `metadata: {'amount': amount.toString(), 'recipientId': toUserId, 'currency': currency}`.
  The #283 correction call-site passes `logActivity: false` (and reverses from/to on
  purpose at `:273-276`) — corrections never log; untouched.
- **`fromUserId`/`toUserId`/`fromName`/`toName` are all in scope at both write sites**
  (decomposed path `:770-896`, atomic path `:942-1035`; the `:544-545` params belong to
  `_showRecordPaymentSheet`, which feeds both — Gate r1 citation fix) — stamping
  direction requires no new plumbing.
- **Event-scoped settle-up writes NO activity log at all** (`settle_up_screen.dart` has
  zero `logGroupEvent`/activity hits) and there is no server settlement fan-in
  (`settlementNotifier.ts` is FCM-only; `expenseAuditLogger` is the only audit writer).
  Event settlements are invisible to every feed today. **Out of scope** — separate
  follow-up issue (needs a rules type-allow-list addition, which is COUPLED to the
  writeRateMonitor `expense_*` skip per the rules comment, and a fan-in decision).
- **Rules floor** (`security/firestore.rules:991-1000`, the #814 block): absent-or-typed
  `md.get(key, default) is type` checks on 6 known keys + `md.size() <= 16`; **unknown
  keys currently pass unvalidated** (proven by the live emulator test
  `firestore-rules-publish-readiness.test.ts:2813-2823`, where `recipientId` rides
  through). The `type` allow-list already contains `'group_settlement'` — **no type-list
  change, so the monitor-coupling trap is not triggered.**
- **Read surfaces**: `activity_display.dart:42` maps `'group_settlement'` to the static
  `l10n.activityGroupSettlementDescription` ("recorded a settlement" / AR "سجّل تسوية",
  no placeholders). All three row renderers funnel through `localizedGroupActivityText`:
  `group_activity_screen.dart:512`, `cross_group_activity_screen.dart:673`,
  `activity_row.dart:32`. The #816 search matcher (`activity_display.dart:161-187`)
  haystacks description/localized text/actorName/groupName/`eventName`/formatted amount.
  Metadata reads go through the `_metadataString` type guard (`:26-35`) — client-forgeable
  map, never raw-cast (the #808 PR2 rule).
- **The green `+`**: `group_activity_screen.dart:566-575` — settlement rows render a
  second 11px `RAmount(sign: true, tone: AmountTone.sage)` **in place of the timestamp**
  (the `else` branch is the relative-time `Text` every other row gets). So the current
  layout both lies about direction AND drops the timestamp from settlement rows. Pinned
  by `group_activity_screen_test.dart:617-621` (2 settlement rows → 4 `RAmount`s) and the
  #382 PR-4 per-log-currency test (`:585-633`).
- **Row composition**: rows render `Text.rich(actorName + description)`
  (`group_activity_screen.dart` `_ActivityRow`) — the description MUST remain an
  **actor-relative verb phrase** with no actor name inside it.
- `AmountTone` = `{auto, sage, rust, ink}` (`r_amount.dart:13`).
- **Legacy rows** carry only `{amount, recipientId, currency}` — direction keys read as
  absent → the read path must degrade to today's generic string.

## Design

One PR: client write-path + read-path + rules floor + tests. Rules change → **deploy
ceremony after merge** (no-real-users rule: no client/server ordering constraint).

### 1. Write path — stamp direction (both sites, identical)

Metadata gains four keys; existing keys kept byte-identical (legacy shape stability —
`recipientId` stays even though it now duplicates `toUserId`; the emulator anchor test
asserts the legacy shape still passes):

```dart
metadata: {
  'amount': amount.toString(),
  'recipientId': toUserId,
  'currency': currency,
  'fromUserId': fromUserId,
  'toUserId': toUserId,
  'fromName': fromName,
  'toName': toName,
},
```

7 keys ≤ 16 cap. `description` composition unchanged (actor-relative, only a fallback for
unknown types + a search haystack). Log **cardinality unchanged** — the decomposed path
still logs exactly once (the pinned invariant); this spec only widens the metadata map.

Identity note: `fromUserId`/`toUserId` are member userIds — either real uids or shadow
uuids (#278). `actorId` is always the recorder's auth uid.

### 2. Rules floor — extend `validActivityMetadata` (Gate-category, deploy)

Add five absent-or-typed checks in the same `md.get` idiom (cheap; the activity-create
path is nowhere near the #723 1000-expression ceiling, which afflicts the event-update
OR-chain):

```
&& md.get('recipientId', '') is string
&& md.get('fromUserId', '') is string
&& md.get('toUserId', '') is string
&& md.get('fromName', '') is string
&& md.get('toName', '') is string
```

(`recipientId` promoted from opaque to typed while we're in the block — it is now a
documented key of this shape.) No change to the type allow-list, `hasOnly` key list, or
any other rule.

### 3. Read path — directional phrase

`activity_display.dart`: replace the static branch with a guarded resolver. Exact
contract:

```dart
'group_settlement' => _settlementText(l10n, log),
```

```dart
String _settlementText(AppLocalizations l10n, GroupActivityLog log) {
  final fromName = _metadataString(log, 'fromName');
  final toName = _metadataString(log, 'toName');
  final fromUserId = _metadataString(log, 'fromUserId');
  final toUserId = _metadataString(log, 'toUserId');
  // Gate r1 [P2]: null-checks must be inline (or re-read into non-null locals) —
  // a separate `hasDirection` bool does NOT null-promote the variables and the
  // l10n calls take non-nullable String.
  if (fromName == null || fromName.isEmpty ||
      toName == null || toName.isEmpty ||
      fromUserId == null || fromUserId.isEmpty ||
      toUserId == null || toUserId.isEmpty) {
    return l10n.activityGroupSettlementDescription; // legacy/forged fallback
  }
  if (log.actorId == fromUserId) return l10n.activitySettlementPaid(toName);
  if (log.actorId == toUserId) return l10n.activitySettlementReceived(fromName);
  return l10n.activitySettlementBetween(fromName, toName); // #595 third-party recorder
}
```

(With sequential inline null/empty checks, Dart's flow analysis promotes all four locals
to non-null `String` at the l10n call sites — compiles clean.)

All four reads type-guarded (`_metadataString`) — a forged non-string value degrades to
the legacy generic string, never a crash (the #808 P1 class: the search matcher calls
this for EVERY row, so a per-row crash would take out the whole tab).

The three actor cases are real, not defensive fiction: payer records (normal), creditor
records (#282 "Mark received"), third party records (#595 settle-on-behalf).

### 4. Read path — kill the green `+`, restore the timestamp

`group_activity_screen.dart:566-575`: **delete the second signed sage `RAmount` and the
`isSettlement` special-case** — settlement rows render the relative timestamp like every
other row. The 14px unsigned per-log-currency `RAmount` (the main amount) stays. Amount
becomes direction-neutral; direction lives in the phrase (the review explicitly offered
"neutral or viewer-relative" — neutral is chosen: no viewer-uid plumbing, no tone
semantics to invent).

**Gate r1 [P2]: also delete the `isSettlement` declaration at
`group_activity_screen.dart:511`** — its ONLY reference is the branch being removed;
leaving it makes `flutter analyze` red (unused local). Note the `'group_settlement' =>`
arms at `group_activity_screen.dart:612` / `cross_group_activity_screen.dart:781` are
`_CategoryIcon` color/icon maps, NOT description resolvers — leave them alone.

Cross-group tab and `activity_row.dart` need **no widget change** (already neutral,
single `RAmount`); they inherit the directional phrase via the shared
`localizedGroupActivityText` (signature unchanged — `log.actorId` is already on the log).

### 5. Search matcher

Add the two name keys to the haystacks (type-guarded, same idiom as `eventName`):

```dart
_metadataString(log, 'fromName'),
_metadataString(log, 'toName'),
```

Legacy rows stay searchable by counterparty via the raw `description` haystack (already
present).

### 6. l10n (EN + AR, generated files committed)

| Key | EN | AR |
|---|---|---|
| `activitySettlementPaid` | `paid {toName}` | `دفع إلى {toName}` |
| `activitySettlementReceived` | `received a payment from {fromName}` | `استلم دفعة من {fromName}` |
| `activitySettlementBetween` | `recorded a settlement from {fromName} to {toName}` | `سجّل تسوية من {fromName} إلى {toName}` |

Each key gets its `@key` placeholder-metadata block in `app_en.arb` (mirror the neighbor
`@activityGroupEventCreated` at `:1639-1644` — e.g.
`"@activitySettlementPaid": {"placeholders": {"toName": {}}}`). Words, not arrows
(RTL-safe — an `→` glyph would point the wrong way in Arabic).
`activityGroupSettlementDescription` unchanged (it is now the legacy/forged fallback).

## Non-goals

- Event-scoped settlement feed visibility (follow-up issue; type allow-list + monitor
  coupling + fan-in decision).
- `amountFils` modernization of settlement metadata (legacy `amount` string stays; the
  `activityAmount` coercion path already handles both shapes).
- Viewer-relative "you" phrasing or viewer-relative amount tone.
- Correction-path logging (stays `logActivity: false`).
- Backfill of legacy rows (they keep the generic phrase forever; acceptable — no real
  users).

## Tests (RED first)

1. **Unit — `activity_display_test.dart`**: directional branches (actor==from → "paid",
   actor==to → "received", third party → "between"); legacy fallback (no direction keys);
   forged types (`fromName: 5` → fallback, not crash); empty-string names → fallback;
   matcher matches a directional row by `toName` query and a legacy row by description.
2. **Write shape — `group_settle_up_decompose_test.dart`**: extend the single-call pin to
   assert the four new metadata keys (and that cardinality is still exactly 1). Same for
   the atomic path's test if one pins metadata.
3. **Widget — `group_activity_screen_test.dart`**: settlement rows render NO signed sage
   `RAmount` (2 rows → 2 `RAmount`s) and DO render the relative timestamp. The breaking
   asserts are all inside the single #382 PR-4 test (`:585-633`): `hasLength(4)→2` at
   `:621` AND the per-currency `hasLength(2)→1` pair at `:625-626` (Gate r1 note).
   **Fixture trap (Gate r1)**: `_todayActivity()` (`:41-48`) has no metadata → its rows
   exercise the legacy fallback, asserted as "recorded a settlement" at `:424/:546/:710`.
   Keep that fixture direction-key-FREE and add a NEW directional fixture for the new
   assertions — do not retrofit direction keys into `_todayActivity()`.
4. **Emulator rules — `firestore-rules-publish-readiness.test.ts`**: the full directional
   shape is accepted; a wrong-typed key (`fromName: 5`) is rejected; the legacy 3-key
   shape still passes (extend the `:2813-2823` anchor); 16-key cap unchanged.

## Deploy / process

- Client + rules in one PR; `/automerge` (rules path → GATE classification); after merge
  → deploy ceremony (`pending_deploy.sh` → commit-bound deploy → tag → ledger row).
- Commit body `Refs #818`.
- File the follow-up issue for event-settlement feed invisibility when this PR opens.

## Verification principles — run at spec time

1. **Callsite classification**: the two `logGroupEvent` calls are OUTBOUND (enumerated
   exhaustively — grep confirmed no other settlement writer, client or server); all new
   reads are INBOUND and type-guarded; the matcher is INBOUND.
2. **Concrete claims verified in-session**: both write sites read (`:881-896`,
   `:1019-1036`); variable scope grep (`fromUserId` et al. at `:544-571`); rules block
   read (`:985-1038`) incl. the coupled-pair comment; row composition read (`Text.rich`
   actorName+description); `AmountTone` enum read; `localizedGroupActivityText` caller
   grep (3 callers + matcher); l10n keys grep'd in both ARBs.
3. **Read-path per write-path**: new metadata keys → named readers: `_settlementText`
   (reached from all three row renderers via `localizedGroupActivityText`) + the matcher
   haystacks + the emulator rules floor.
4. **Fields enumerated from the type**: the metadata map is spelled key-exhaustively at
   both write sites; `GroupActivityLog` model is untouched (metadata is an opaque map —
   its doc comment at `group_activity_log_model.dart:27` is stale about the real shape;
   do not trust it).
5. **Contracts spelled out**: exact 7 metadata keys, exact 3 l10n keys + placeholders,
   exact 5 rules clauses, exact resolver logic.
6. **Arithmetic decomposition**: N/A — amount serialization untouched; the decomposed
   path's single aggregate-amount log entry is deliberately unchanged.
7. **Adversarial pass on the identity axis** (fix is on the direction axis): all three
   recorder identities exercised (payer, #282 creditor, #595 third party); shadow-member
   counterparties (uuid `fromUserId`/`toUserId` — `actorId` is an auth uid, so a
   shadow-involving settlement recorded by a live member resolves to "paid {shadow}" /
   "received from {shadow}" correctly, and a shadow can never be the actor); #283
   correction reverses direction but never logs; legacy rows (time axis) fall back
   generically; forged metadata (security axis) degrades via type guards and is now
   type-floored at the rules.

## Acceptance

- [ ] New settlement rows show "Ali paid Sarah"-class directional phrases on all three
      feed surfaces; legacy rows keep the generic phrase.
- [ ] No unconditional green `+`: signed sage row deleted, timestamp restored on
      settlement rows.
- [ ] Search matches directional rows by either party's name.
- [ ] Rules floor extended + emulator tests green (`npm run test:emulator -- firestore-rules-publish-readiness.test.ts`).
- [ ] Decomposed settle-up still logs exactly once.
- [ ] `flutter analyze` clean; ledger/groups/home test dirs green; EN+AR parity.
- [ ] Deploy ceremony completed after merge (rules change).
- [ ] Follow-up issue filed: event-scoped settlements invisible to activity feeds.

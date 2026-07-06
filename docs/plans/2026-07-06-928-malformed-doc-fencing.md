# #928 — Malformed-doc fencing for money + activity read paths (oracle-parity total-parse)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** DRAFT — pre-Gate.
**Issue:** #928.
**Gate class:** GATE (money read-paths: `expense_provider.dart` consumers, `**/models/**.dart` schema read-path).

**Goal:** One malformed Firestore doc must never blank the ledger, the settle-up stream, the home balance, or an activity feed — while keeping the client's per-doc money interpretation byte-identical to the TS server oracle `recomputeNet`.

**Architecture:** Two layers, mirroring the established Group/Member/Event pattern (`safe_deserialize.dart` doc comment): (1) make the two MONEY factories (`Expense.fromFirestore`, `Settlement.fromFirestore`) **total-parse** — per-field salvage with fallbacks that mirror the oracle's per-field reads exactly; (2) route every list-map site through `decodeDocsSkippingMalformed` (or an inline per-doc try/catch where a cache makes the helper unusable) as a doc-catastrophe **backstop**. Activity feeds (display-only, no oracle) get layer 2 only — skip-and-report, matching the existing `fetchAllEventAuditLogs` precedent.

**Tech stack:** Dart/Flutter, FakeFirebaseFirestore, existing `decodeDocsSkippingMalformed` helper.

---

## Why NOT the issue's literal fix (doc-skip only) — the parity argument

The issue proposes routing the money maps through `decodeDocsSkippingMalformed` and stopping there. Verified against `functions/src/callables/groupNetBalance.ts` (2026-07-06), that would **break client↔server balance parity**:

- `recomputeNet` is total-parse and includes every live doc: `amountFilsOf` → `typeof data.amountFils === 'number' ? … : 0` (:293-295), `currencyOf` → OMR fence (:52), non-string `payerParticipantId` → paid simply not credited (:407-410), `decodeSplitMode` → `'equally'` fallback (:77-84), `persistedInt` → `0` fallback (:86-93), `stringArray` filters non-strings (:329-331).
- `recomputeNet` **never reads `createdAt` or `settledAt`** (grep 2026-07-06: zero doc-field reads of either — only `deletedAt` inside the deleteGroup lock-window branch, `timestampMillis` :304).
- So a doc with garbage `createdAt` (the most likely field-level corruption) is **fully counted** by the server aggregate (`balanceAggregator.ts` reuses `recomputeNet`). If the client SKIPPED that doc, the home balance would silently flip between the aggregate value (online) and a different once-path value (offline) — a silent money-wrong divergence, worse than today's loud stream error.

Therefore: money docs are **salvaged, not skipped**, field-by-field mirroring the oracle. The skip-fence remains as backstop for doc-level catastrophes only (e.g. a decode that still throws), exactly the contract already documented in `safe_deserialize.dart:13-16`.

## Verified throw-site inventory (principle 2 & 4 — enumerated from the model files, 2026-07-06)

### `Expense.fromFirestore` (`lib/features/ledger/models/expense_model.dart:177-230`)

| Field | Today (throws on) | New salvage | Oracle mirror |
|---|---|---|---|
| `id` | `as String` (non-string/missing) | `is String ? v : ''` | oracle keys by doc.id; all live callsites spread `{'id': doc.id}` — fallback unreachable, totality only |
| `eventId` | `as String` | `is String ? v : ''` | never read by oracle (event context = collection path) |
| `payerParticipantId` | `as String` | `is String ? v : ''` **+ universe guard (below)** | oracle `typeof === 'string'` gates BOTH the paid credit (:406-408) AND the universe fold (`financial.add`, :651). The salvage alone is NOT enough — see §Payer-salvage universe guard (R1 rubric P1) |
| `amountFils` | `as int?` (non-int) | `is int ? v : 0` | oracle `typeof === 'number' ? v : 0`; JS-double divergence accepted — client zeroes ONE doc's amount, corrupts no one else's shares; rules pin `positiveInt(data.amountFils)` on the expense create path (firestore.rules:761; :108 is the settlement pin `validSettlementCore`) so only Admin/legacy docs can differ. Named for symmetry with the payer case: BOTH are bounded to the same Admin/forged/legacy class; payer gets the universe guard because its blast radius is co-participants' shares, amount-double stays accepted because its blast radius is its own doc |
| `currency` | — (already fenced #47) | unchanged | `currencyOf` |
| `description` | `as String?` (non-string) | `is String ? v : null` | display-only |
| `scope` | `as String?` cast | `is String ? v : 'global'` (then existing `fromString`) | oracle reads scope? — NO (universe from participantIds); client scope affects owed-universe per BalanceCalculator; `'global'` is the write-default, matches absent-field semantics |
| `subGroupId` | `as String?` | `is String ? v : null` | legacy scope only |
| `customSplitParticipants` | `List<String>.from` (non-string element) | `rawList.whereType<String>().toList()` | mirrors TS `stringArray` filter :329-331 |
| `splitMode` | — (already total) | unchanged | `decodeSplitMode` |
| `splitDistribution` | `_persistedInt` last branch `Decimal.parse(v.toString())` throws on non-numeric strings | final branch → `Decimal.tryParse(value.toString())?.toBigInt().toInt() ?? 0` | mirrors TS `persistedInt` (`Number(v)` finite ? trunc : 0) :86-93 |
| `splitExplanation` | `as Map` cast (non-map) | `is Map ? try { fromMap } catch → null : null` | INBOUND/display-only, never read by any Function (CLAUDE.md contract) |
| `receiptUrl`, `categoryId`, `note` | `as String?` | `is String ? v : null` | display-only |
| `createdAt` | `DateTime.parse(as String)` | `is String ? DateTime.tryParse(v) : null`, fallback `DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)` | oracle never reads it; list position comes from the Firestore query's raw-field order, parsed value only feeds day-card grouping (epoch card at list end — honest) |
| `isDeleted` | `as bool?` (non-bool) | `is bool ? v : false` | query filters `== false` server-side; oracle `=== false` strict — a non-bool doc never arrives via any live query |
| `deletedAt` | `DateTime.parse` | `is String ? DateTime.tryParse(v) : null` (fallback null) | oracle reads it only in the deleteGroup lock window via `timestampMillis` (total) |
| `createdBy`, `lastEditedBy` | — (`as String? ?? ''` still throws on non-string) | `is String ? v : ''` | not read by oracle money fold |

### `Settlement.fromFirestore` (`lib/features/ledger/models/settlement_model.dart:125-170`)

| Field | Today | New salvage | Oracle mirror |
|---|---|---|---|
| `id` | `as String` | `is String ? v : ''` | as above |
| `eventId`/`groupId` → `tripId` | `as String?` casts throw on non-string | type-gate both: `eventId is String ? : (groupId is String ? : '')` | oracle folds by collection PATH, not these fields |
| `payerParticipantId`, `recipientParticipantId` | `as String?` | `is String ? v : null` | oracle `typeof === 'string'` gates both parties |
| `amountFils` | `as int?` | `is int ? v : 0` | as expense |
| `currency` | — (fenced #193/#220) | unchanged | `currencyOf` |
| `note`, `payerName`, `recipientName` | `as String?` | `is String ? v : null` | display-only |
| `settledAt` | `DateTime.parse(as String)` — **the issue's named repro** | `is String ? DateTime.tryParse(v) : null`, fallback epoch UTC | **oracle never reads `settledAt`** (grep :0 hits) — the doc's money MUST keep counting |
| `isDeleted`, `deletedAt` | as expense | as expense | as expense |
| `scope` | `as String? ?? 'event'` | `is String ? v : 'event'` | oracle uses path, not scope |
| `createdBy` | `as String? ?? ''` | `is String ? v : ''` | — |
| `groupSettleUpId` | `as String?` | `is String ? v : null` | oracle-invisible (CLAUDE.md contract) |
| `correctionOfSettlementId` | — (already `is String` gated, #889) | unchanged | — |

Factories stay **pure** (no Sentry import): field salvage is silent, matching the existing in-factory currency fences (#47/#193). Telemetry for a bad doc comes from the layer-2 fence only. Accepted gap, named here on purpose.

### Payer-salvage universe guard (R1 rubric P1 — verified 2026-07-06)

The salvage table alone ships a money bug: `eventBalanceUniverse` (`expense_provider.dart:106-115`) folds `e.payerParticipantId` into the universe UNCONDITIONALLY, while the oracle gates with `typeof === 'string'` before `financial.add` (`groupNetBalance.ts:651`). A non-string payer salvaged to `''` would therefore enter the CLIENT universe (phantom `''` row seeded by `calculateBalances`' `bucketFor`, equal-split divisor inflated by 1 — participants [alice,bob] + one OMR 10.000 expense with `payerParticipantId: 42`: client would say alice/bob owe 3.333 each + phantom `''` +6.666; oracle says 5.000/5.000, no phantom) but never the oracle's.

**Fix:** in `eventBalanceUniverse`'s `payersAndSettlers` set, guard the expense payer fold: `if (e.payerParticipantId.isNotEmpty) e.payerParticipantId`. One choke point covers all four consumers (verified: `ledger_view_provider.dart:95`, `settle_up_screen.dart:240` + `:536`, `group_balance_provider.dart:340`). Settlement parties need no guard — nullable, salvaged to `null`, already null-gated at :116-117 and mirrored by the oracle's typeof gates (:454-457).

**Named residual (accepted):** a doc whose STORED payer is the literal string `''` — the oracle's `typeof` check passes and seeds a phantom `''` row server-side while the guarded client drops it. Unreachable by any rules-valid write (`payerParticipantId in participants()` — `''` cannot be a participant), i.e. Admin/forged-only, and the divergence direction is the harmless one (client shows less, not more). Symmetric to the amountFils-double acceptance above.

**Paid-credit side needs NO change:** `calculateBalances` already drops the credit via `paidMap.containsKey(payerId)` (:290-292) once `''` is outside the universe — same shape as the oracle's `.has()` gate (:407).

### Fence sites (layer 2 — backstop + activity skip)

| Site | Today | Change |
|---|---|---|
| `expense_service.dart` `_reconcileExpenses` :68-83 | bare parse in docChanges loop (:76) + `??=` build loop (:81) | per-doc `try/catch` at BOTH parse points: on catch, `cache.remove(doc.id)` / skip from list + `Sentry.captureException` + debug print (inline — the helper's iterable shape doesn't fit the cache). A persistently-throwing doc re-reports per tick via the `??=` miss; accepted — the total factory makes this branch practically unreachable |
| `expense_service.dart` `getExpenses` :96-98 | bare `.map` | `decodeDocsSkippingMalformed(snap.docs, (d) => Expense.fromFirestore({...d.data()! as Map<String, dynamic>, 'id': d.id}), context: 'ExpenseService.getExpenses')` |
| `settlement_service.dart` `watchSettlements` :38-45, `getSettlements` :57-59 | bare `.map` | helper, contexts `'SettlementService.watchSettlements'` / `.getSettlements` |
| `lib/features/groups/services/group_settlement_service.dart` `watchGroupSettlements` :38-45 (NOT under `ledger/services/` like the other two) | bare `.map` — **not in the issue's list but the identical gap on the same money surface** (feeds `groupSettlementsProvider` → home once-path); same one-concern | helper |
| `activity_feed_screen.dart` `_loadPage` :98-100 | bare `.map` inside a whole-page `catch (_)` → one bad row kills the page (initial → `_initialError`, later → silently stalls pagination since `_lastDocument` still advances but rows are lost — actually the catch discards the WHOLE page incl. cursor advance) | helper, context `'ActivityFeed.page'`; page keeps remaining rows + cursor advance |
| `group_activity_service.dart` `watchRecentActivity` :47-55, `fetchActivityPage` :75-81 | bare `.map` | helper |
| `group_activity_screen.dart` `_loadPage` :106-111 | bare `.map` in whole-page catch | helper, context `'GroupActivity.page'` |
| `cross_group_activity_pager.dart` `_fetchOne` :121-130 | bare `.map` in per-group catch (one bad row silently drops the whole GROUP from the merged feed) | helper, context `'CrossGroupActivity.fetch'` (keep the existing sort chained after) |

NOT fenced (verified own-data, always well-formed): `expense_service.dart:258` (`stageExpense` return), `settlement_service.dart:124`, `group_settlement_service.dart:103` (add* returns). `activity_service.dart` `fetchAllEventAuditLogs` already fenced (precedent). `watchExpensesInRange` (`expense_service.dart:111-125`) is covered automatically — it maps through the same `_reconcileExpenses`; note for any future reviver (it has zero live consumers today): its server-side STRING range filter on `createdAt` excludes a number-typed `createdAt` doc that the oracle includes — a latent view-level parity quirk of the query, not of this fix (R1 adversary P3).

**Money-fence semantics caveat (R1 adversary P2):** `safe_deserialize.dart`'s "exactly the docs the server oracle also excludes" lockstep claim is TRUE for Group/Member/Event but FALSE for money docs — the money oracle is total and drops essentially nothing, so any client-side money-doc SKIP has no server counterpart. The fence on money paths is therefore a last-resort against doc-level catastrophe, NOT a safety net for factory regressions: if a future field is added to `Expense`/`Settlement.fromFirestore` without a total-parse fallback, the fence would convert its throw into a silent home-balance divergence. Guardrails shipped with this PR: (1) a **factory-totality regression test** — a fixture with EVERY field simultaneously wrong-typed must deserialize without throwing (new fields that throw turn it red); (2) a comment at each money fence site stating this exact caveat.

`ActivityLog.fromFirestore` / `GroupActivityLog.fromFirestore` factories: **untouched** — skip-and-report is the correct semantic for display-only feed rows (no oracle to stay in lockstep with), and it's the shipped Trip Receipt behavior.

## Callsite classification (principle 1)

Every touched site is INBOUND (Firestore → model deserialization for display/compute). No OUTBOUND path changes: `toFirestore`, `stageExpense`, `addSettlement`, `addGroupSettlement`, `_encodeDistribution` are untouched. The salvaged values never feed a write (edit screens hydrate from the same model but rules re-validate every write; a salvaged `''` payer cannot produce a rules-valid write).

## Read-path per write-path (principle 3)

No write path changes. Read-paths gaining robustness, each with a named consumer:
- `watchExpenses` → `eventExpensesProvider` → ledger list + `groupBalancesProvider` (in-group balances).
- `getExpenses`/`getSettlements` → `groupBalancesOnceProvider` → `homeGroupBalanceProvider` offline/fallback path → home `BalanceHeroCard`.
- `watchSettlements` → `eventSettlementsProvider` → settle-up screen.
- `watchGroupSettlements` → `groupSettlementsProvider` → group settle-up + home once-path fold.
- activity sites → History feed, group activity screen, cross-group feed, home recent strip.

## Arithmetic decomposition (principle 6)

Unchanged — no allocator or fold is touched. The parity table above IS the per-field decomposition proof: for every field the oracle reads, the client fallback now produces the value the oracle produces.

## Adversarial pass on an orthogonal axis (principle 7)

Fix axis = deserialization robustness. Orthogonal worked example (identity × money-flow): a settlement doc whose `recipientParticipantId` is an int `42`. Today: `as String?` throws → settle-up stream AND home once-path error. Post-fix: salvaged to `null` → client `calculateBalances` settlement fold skips a null party; oracle `typeof === 'string'` gate skips the same leg — parity holds. **R1 caveat, kept as scar tissue:** this example accidentally picked the SAFE case (settlement parties are nullable → null-guarded everywhere). The NON-nullable expense `payerParticipantId` was the live mine — v1 of this spec over-generalized from the settlement case and claimed `''` was "dropped by both calculators", which is false at `eventBalanceUniverse:114`. The R1 rubric reviewer's identity-axis example (expense payer int `42` → phantom `''` row + inflated divisor) is now §Payer-salvage universe guard + parity test 4.

## Acceptance (issue boxes, restated post-parity-design)

- [ ] Malformed Expense doc (garbage `createdAt`): ledger renders ALL docs (salvaged one under the epoch day-card); home once-path computes a balance that INCLUDES its amount (oracle parity), not merely "the parseable docs".
- [ ] Malformed Settlement (`settledAt: 12345`): settle-up stream + home once-path compute; doc's money counted.
- [ ] **Client net == oracle net on a non-string-payer doc** — the mirrored-fixture parity pin (test 4) passes on BOTH sides with identical hand-computed values; no phantom row.
- [ ] Malformed ActivityLog / GroupActivityLog row: feed page renders remaining rows, cursor advances, bad row skipped + Sentry-reported.
- [ ] Factory-totality guardrail test (test 7) green — the money fence stays a dead branch.
- [ ] RED-first regression tests per surface (below).
- [ ] `flutter analyze` clean; full `flutter test` green; `functions` jest suite for `groupNetBalance.test.ts` green.

## Test plan (RED first — each written before its fix lands)

New file `test/unit/malformed_doc_fencing_test.dart` (FakeFirebaseFirestore, service-level) + one widget test each in `test/features/activity/` and `test/features/groups/` for the paged feeds. **Sort-key rule (R1 rubric P2): query-level tests must corrupt NON-sort-key fields only** — `FakeFirebaseFirestore`'s cross-type comparator on `orderBy('createdAt')`/`orderBy('settledAt')` can throw or misorder BEFORE deserialization, making a RED fail for the wrong reason. Timestamp salvage is covered by direct `fromFirestore(map)` unit tests instead.

1. **Timestamp salvage — direct unit** (RED): `Expense.fromFirestore({... 'createdAt': 12345})` → epoch `createdAt`, amount intact, no throw; `Settlement.fromFirestore({... 'settledAt': {'x': 1}})` → epoch, amount intact.
2. **Query-level salvage** (RED): seed 2 good + 1 expense with `payerParticipantId: 42` (NOT a sort key) → `watchExpenses` emits 3 and `getExpenses` returns 3 (today: stream error). Same shape for settlements (`recipientParticipantId: 42`) through `watchSettlements`/`getSettlements`/`watchGroupSettlements`.
3. **Expense split-garbage** (RED, direct unit): `splitDistribution: {'uid-b': 'abc'}`, mode exact → decodes to 0-value entry (not throw), matching TS `persistedInt`.
4. **Client↔oracle parity pin — mirrored fixtures (R1 rubric P1)**: identical scenario in BOTH suites, asserting identical hand-computed nets. Fixture: participants [alice, bob], one global OMR 10.000 expense with `payerParticipantId: 42` (non-string). Expected on BOTH sides: alice −5.000, bob −5.000, NO phantom row, universe = {alice, bob}. Dart side: `eventBalanceUniverse` + `calculateBalances` in `test/unit/balance_calculations_test.dart` (or the new file); TS side: the same doc through `recomputeNet` in `functions/test/callables/groupNetBalance.test.ts`. RED today on the Dart side (throws pre-salvage; post-salvage-without-guard it would show the phantom — the test pins BOTH layers of the fix).
5. **Activity page fencing** (RED): event feed — 1 good + 1 `logText: null` row → `_loadPage` renders the good row (today: `_initialError` empty-state); group screen + pager equivalents at service level (`watchRecentActivity`, `fetchActivityPage`) and pager merge (bad row in group A doesn't drop group A's good rows).
6. **Reconcile cache fence**: malformed doc arrives via a docChanges tick alongside good docs → list carries the salvaged expense. (A doc whose decode STILL throws is unreachable through the total factory — the inline catch is covered by review + the totality test, stated honestly in the PR.)
7. **Factory-totality guardrail (R1 adversary P2)**: one fixture per money model with EVERY field simultaneously wrong-typed (int strings, map numbers, list maps…) → `fromFirestore` returns a salvaged object, never throws. This is the standing pin that keeps the money fence a dead branch.

Existing suites to re-run (may assert on throw behavior): `test/unit/` expense/settlement model tests, `balance_calculations_test.dart`, `group_balance_provider_test.dart`, `delete_group_balance_parity_test.dart`, activity feed tests. Fixture-drift rule applies: if an existing test PINS the throwing behavior, migrate it to pin the salvage instead (name it in the PR).

## Non-goals

- No write-path, rules, or oracle change (parity is achieved client-side; the TS side only GAINS a mirrored test fixture).
- No `ActivityLog`/`GroupActivityLog` factory rewrite.
- No new SplitMode / no `splitExplanation` server wiring (standing contracts).
- No Sentry reporting for silent field salvage (matches #47/#193 precedent) — revisit only with a real prod signal need.
- `stageExpense`/`add*` return-path maps untouched.
- No edit-UX handling for corrupt-doc docs (R1 adversary P3, accepted): a salvaged doc becomes visible/tappable where it previously blanked the stream; an edit against stored garbage can be rules-rejected (`permission-denied`) and surfaces through the existing update-failure snackbar. Admin-corrupted docs don't get bespoke UX.

## Implementation-task deltas from R1

Task 1 additionally carries the `eventBalanceUniverse` payer guard (`expense_provider.dart:114`) + parity test 4's Dart side + totality test 7; a new Task 1b adds the mirrored TS fixture to `functions/test/callables/groupNetBalance.test.ts` (run: `cd functions && npm run test:emulator -- callables/groupNetBalance.test.ts`). Task 2's fence commits carry the money-fence caveat comments.

## Implementation tasks (bite-sized)

### Task 1: Money-model total-parse
- Modify: `lib/features/ledger/models/expense_model.dart:177-230` (+ `_persistedInt` final branch), `lib/features/ledger/models/settlement_model.dart:125-170` per the salvage tables.
- Step 1: write tests 1–4 above → run → RED (paste output). Step 2: apply factory changes. Step 3: tests GREEN. Step 4: `flutter test test/unit/ test/features/ledger/` green. Step 5: commit `fix(models): total-parse Expense/Settlement factories — oracle-parity field salvage (Refs #928)`.

### Task 2: Money service fences
- Modify: `expense_service.dart` (`_reconcileExpenses` inline try/catch + `getExpenses` helper), `settlement_service.dart`, `group_settlement_service.dart` (helper). Import `safe_deserialize.dart`.
- Steps: reconcile-cache test (6) first if feasible → implement → green → commit `fix(ledger): fence money list maps through decodeDocsSkippingMalformed (Refs #928)`.

### Task 3: Activity fences
- Modify: `activity_feed_screen.dart:_loadPage`, `group_activity_screen.dart:_loadPage`, `cross_group_activity_pager.dart:_fetchOne`, `group_activity_service.dart` (2 sites).
- Steps: test 5 RED → implement → GREEN → commit `fix(activity): skip malformed feed rows instead of failing the page (Refs #928)`.

### Task 4: Full verify + PR
- `flutter analyze`; full `flutter test`; `bash tool/check_theme_purity.sh`.
- PR one concern (`Closes #928`), body carries `Spec:` line to this file + RED outputs. `/automerge` will classify GATE (money) — expected.

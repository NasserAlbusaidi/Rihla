# Spec: Expense-created push notifier (#179, partial)

**Date:** 2026-06-13 · **Issue:** #179 (transactional push notifications) · **Gate:** required (`functions/**`)
**Delivery:** `Refs #179` (partial — closes the "Expense created" box only; issue stays open re-scoped).

## What this unit adds

ONE Firestore trigger — `expenseNotifier`, an `onDocumentCreated('groups/{gid}/events/{eid}/expenses/{expenseId}')` — that buzzes the people an expense is split onto (minus the actor) when it is created. This is the single highest-value remaining v1 sender: the 2026-06-13 issue comment names the missing expense-created notification "the single most important event in an expense splitter is silent … a retention blocker." It mirrors the shipped `settlementNotifier` (#53) byte-for-byte in structure.

## Explicitly OUT of scope (deferred, named — `Refs #179`, do not build here)

- **Event-created notifier** (`onCreate groups/{gid}/events/{eid}`) — the other missing v1 sender; separate follow-up.
- **Expense edited / soft-deleted** notifications (the deferred fold-in items).
- **Tap → deep-link routing** (v2 per the issue; the `data` payload carries the route hint for forward-compat, but no client routing changes — keeps this unit out of `lib/core/router/**`).
- **Multi-device `fcm_tokens` fan-out** (schema change, its own Gate).
- **member_left / group_deleted** awareness pushes.

## The load-bearing fact (verified against code, not issue text — principle 2)

Expense `payerParticipantId`, `splitDistribution` keys, `customSplitParticipants` entries, and `event.participantIds` are **all auth UIDs**, so they map directly to `fcm_tokens/{uid}` exactly like settlement parties — **no participantId→uid join needed.** Evidence (the real enforcers, re-cited per Gate R1 [P3] — the CREATE path that fires this trigger is rules-gated to participant uids):
- `firestore.rules:548` — `payerParticipantId in participants()` on expense create.
- `firestore.rules:554` — `customSplitParticipants.hasOnly(participants())`.
- `firestore.rules:477` — `splitDistribution.keys().hasOnly(participants())` (via `validExpenseSplit(data, true)`).
- `firestore.rules:367` — `participantIds.hasOnly(groupMembers())`; `create_event_screen.dart:248` seeds participantIds from `members.map((m) => m.userId)`.
- `settlementNotifier.ts:12-15` already verifies settlement parties + `createdBy` are uids; `expense_model.dart:28,33,36,45` are opaque `String`s carrying these uids.

So a rules-allowed create can only carry participant **auth uids** — a shadow/placeholder id cannot reach this trigger via the create path.

Shadow/unclaimed members have no `fcm_tokens/{uid}` doc → silently skipped by `sendToUids` (existing). No special handling needed.

## Recipient resolution (the contract — principles 4, 5)

Enumerated from `Expense` (`expense_model.dart`): `payerParticipantId`, `splitDistribution` (nullable map), `customSplitParticipants` (nullable list), `scope`, `amountFils`, `currency`, `isDeleted`, `createdBy`, `lastEditedBy`.

```
notifyExpenseCreated(gid, eid, snap):
  data = snap.data(); if !data → return
  if data.isDeleted === true → return            // mirror settlementNotifier.ts:41 (create-as-deleted)
  if typeof data.amountFils !== 'number' → return // mirror settlementNotifier.ts:44
  createdBy = asString(data.createdBy)            // actor on CREATE (== lastEditedBy at create time)
  payer     = asString(data.payerParticipantId)

  // WHO shares the cost — splitDistribution-first, because it is the authoritative
  // "who owes" set when present, for ANY scope (shares/exact/percent persist it).
  // NON-ZERO values only: the editor persists every selected participant INCLUDING
  // value 0 (custom_split_sheet.dart builds {p.id: value} for all rows; expense_service
  // _encodeDistribution does NOT drop zeros) — a 0-share participant owes nothing
  // (expense_provider.dart allocates them 0), so notifying them is a false buzz (Gate R1 [P2]).
  shareSet =
    (data.splitDistribution is a non-empty object)
        ? Object.entries(data.splitDistribution).filter(([,v]) => typeof v==='number' && v>0).map(([k])=>k)
    : (Array.isArray(data.customSplitParticipants) && len>0) ? data.customSplitParticipants  // custom+equally
    : (data.scope === 'personal') ? []                                                        // payer-only
    : await eventParticipantIds(gid, eid)   // global / sub_group / equally-with-no-distribution

  targets = unique( [...shareSet, payer] ).filter(uid => uid.length>0 && uid !== createdBy)
  if targets.length === 0 → return

  actorName = await resolveActorName(gid, createdBy)   // members where userId==createdBy; null if unresolved
  amountText = formatAmount(data.amountFils, asString(data.currency) || 'OMR')
  groupName  = await resolveGroupName(gid)
  await sendToUids(targets, locale => ({
    title: expenseTitle(locale, groupName),
    body:  expenseBody(locale, actorName ?? actorFallback(locale), amountText, asString(data.description)),
  }), { type: 'expense', groupId: gid, eventId: eid })
```

**Why splitDistribution-first then participantIds fallback (principle 2, verified):** `expense_editor_body.dart:61-64,269-271` — when `splitMode == equally` the persisted `splitDistribution` is **null** ("the parent splits equally across ALL event.participantIds"). `expense_provider.dart:369` confirms the calculator treats `equally => <String,Decimal>{}`. So global/equally (the default) persists no distribution → must read `event.participantIds`. shares/exact/percent persist a non-empty distribution whose keys ARE the owers. custom+equally persists no distribution but DOES persist `customSplitParticipants`. personal ⇒ only the payer.

**Payer inclusion:** the payer is financially in the expense; under open-edit (#248) one member can log an expense paid by another, so notify the payer when `payer !== createdBy`. For global scope the payer is already in `participantIds`; the `unique()` dedups.

## Reads — trigger runs as **Admin** (bypasses `firestore.rules`) → **NO rules change, NO routing change**

1. `eventParticipantIds(gid, eid)` — `getFirestore().doc('groups/{gid}/events/{eid}').get()`, read `participantIds` (string list); `try/catch → []`. Called ONLY in the participantIds-fallback branch.
2. `resolveActorName(gid, createdBy)` — mirror `expenseAuditLogger.resolveActorName:101-123`: query `groups/{gid}/members where userId == createdBy`, return first non-empty `displayName` else `null`. **Match by `userId` FIELD, never doc id** — the creator's member doc is keyed by a random uuid with `userId:uid` (#294), so `.doc(uid)` misses it.
3. `resolveGroupName(gid)` — copy `settlementNotifier.ts:21-32`.
4. `fcm_tokens/{uid}` per target — inside `sendToUids` (existing; prunes dead tokens, never throws).

## Copy — `strings.ts` additions (server-side, per-recipient locale)

```
expenseTitle(locale, groupName) = groupLabel(locale, groupName)            // identical to settlementTitle
expenseBody(locale, actor, amountText, description):
  label = description.trim()                                               // user free-text, any language
  en: `${actor} added an expense` + (label ? ` · ${label}` : '') + ` (${amountText}).`
  ar: `أضاف ${actor} مصروفًا` + (label ? ` · ${label}` : '') + ` بقيمة ${amountText}.`
actorFallback(locale) = locale==='ar' ? 'شخص ما' : 'Someone'              // localized; used when name null
```

Description is appended after a `·` separator (not grammatically embedded) so a free-text label in any language stays correct in both locales. `settlementNotifier.ts:65` hardcodes an English `'Someone'` — that is a **pre-existing inconsistency left untouched** here (one PR, one concern); this notifier uses the localized `actorFallback`.

## `index.ts`

`export { expenseNotifier } from './triggers/expenseNotifier';` — **re-export form** (a bare `export const fn = onCall(…)` in index.ts is invisible to both deploy-check extractors per CLAUDE.md).

## Idempotency / retries

`onDocumentCreated` fires once per document create. FCM triggers are at-least-once, so a rare platform retry could re-send. `settlementNotifier` (the shipped precedent) carries **no** dedup store — a transient duplicate buzz is acceptable, and the issue explicitly decided AGAINST a `notifications/{uid}` write collection (the only place a dedup marker could live without write-amplification). This unit matches that precedent; true at-least-once dedup is a shared gap with `settlementNotifier`, out of scope.

## Tests — `functions/test/triggers/expenseNotifier.test.ts` (mirror `settlementNotifier.test.ts`), RED first

Seed `fcm_tokens`, the `groups/{gid}` doc, the `groups/{gid}/events/{eid}` doc (for participantIds), and `groups/{gid}/members` (for actor name). Mock `getMessaging().sendEach`. **`clearAll` must recursively clear the `events`/`members` subcollections** (Gate R1 [P3]) — `settlementNotifier.test.ts:54-60` only clears top-level collections, which would leak event/member docs between cases.

1. **equally/global** (no `splitDistribution`) → notifies `event.participantIds` minus creator (proves the event-doc read).
2. **shares/exact/percent** (`splitDistribution` present) → notifies distribution keys minus creator; payer (not a key) included when `payer != createdBy`.
3. **custom + equally** (`customSplitParticipants`, no distribution) → notifies those minus creator.
4. **personal** scope, `payer == createdBy` → no send; `payer != createdBy` → payer only.
5. **isDeleted create** → no send (soft-delete axis — principle 7).
6. **actor name** resolved from `members` by `userId` field → body contains the name; unresolved → body contains localized `Someone`/`شخص ما`.
7. **no token** for a target → that target skipped.
8. **payload** `{type:'expense', groupId, eventId}`.
9. **currency axis (principle 7, orthogonal to identity):** a JPY expense (`amountFils` scale 1) and a non-OMR expense format with the expense's OWN `currency`, not the group's — `expenseBody` contains the right `amountText` (e.g. JPY `1000` → `"1000"`).
10. **zero-share participant (Gate R1 [P2]):** a shares split `{uidA:3, uidB:0}` must NOT notify uidB (owes nothing) — only uidA (+ payer/minus creator).

## Verification principles — explicit pass

1. **Callsite classification:** the trigger is READ-ONLY w.r.t. the expense doc (INBOUND/notify-only); it never mutates money. Its only writes are the existing fire-and-forget FCM send + dead-token prune inside `sendToUids`.
2. **Every concrete claim verified against code** — paths:lines cited above (settlementNotifier, expense_editor_body, split_scope_selector, ledger_screen, expenseAuditLogger, expense_model, index.ts).
3. **Read-path per write-path:** no write path introduced; N/A.
4. **Fields enumerated from `expense_model.dart`**, not memory.
5. **Data contracts spelled out:** exact `data` keys `{type,groupId,eventId}`; `CopyBuilder = (locale)=>{title,body}`; recipient set algorithm exact.
6. **Arithmetic decomposition:** no aggregate; `formatAmount` (reused) mirrors `MoneySerializer` scale incl. JPY=1.
7. **Adversarial orthogonal axis:** identity fix exercised against MONEY/currency (JPY test, expense-own-currency), SOFT-DELETE (create-as-deleted skip), and OPEN-EDIT identity (#248 — actor = createdBy at create).

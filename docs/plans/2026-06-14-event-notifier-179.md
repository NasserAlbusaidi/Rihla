# Event-created push notifier — #179 last sender

**Created:** 2026-06-14
**Issue:** #179 (transactional push notifications, FCM "buzz", no inbox)
**Gate:** REQUIRED — touches `functions/**` (a new Cloud Functions trigger).
**Scope:** the **fourth and final** v1 sender from the #179 senders table. The other
three are already on `main`: member-join (inline in `joinGroupByInviteCode`),
settlement (`settlementNotifier.ts`, #53), expense-created (`expenseNotifier.ts`,
#503 / `d747735b`). This adds **Event created**.

## What #179 asks for (verbatim from the senders table)

| Trigger | Buzzes (always **minus the actor**) | Source |
|---|---|---|
| Event created | `event.participantIds` ∖ creator | `onCreate groups/{gid}/events/{eid}` |

Each sender: resolve recipients → read their `fcm_tokens` → multicast. Idempotent
on the Firestore event ID (= fires on **create only**, never on updates). Prune
tokens returning `UNREGISTERED`/`INVALID_ARGUMENT`. No client display code.

## The implementation — a near-exact mirror of `settlementNotifier`/`expenseNotifier`

New file `functions/src/triggers/eventNotifier.ts`:

```ts
export const eventNotifier = onDocumentCreated(
  'groups/{gid}/events/{eid}',
  (event) => notifyEventCreated(event.params.gid, event.params.eid, event.data),
);
```

`notifyEventCreated(gid, eid, snap)`:
1. `if (!snap) return;` then `const data = snap.data();`
2. `if (data.isDeleted === true) return;` — never buzz a deleted-on-create event (mirror).
3. `createdBy = asString(data.createdBy)` (the actor).
4. `participants = Array.isArray(data.participantIds) ? data.participantIds.filter(string) : []`.
5. `targets = [...new Set(participants.filter(uid => uid.length > 0 && uid !== createdBy))]`.
6. `if (targets.length === 0) return;` — a single-participant (creator-only) event buzzes nobody.
7. `actorName = await resolveActorName(gid, createdBy)` — **match by the `userId` FIELD**,
   not the doc id (the creator's member doc is keyed by a random uuid, #294). Copied
   verbatim from `expenseNotifier.resolveActorName`.
8. `groupName = await resolveGroupName(gid)` (copied verbatim).
9. `eventName = asString(data.name)`.
10. `await sendToUids(targets, (locale) => ({ title: eventTitle(locale, groupName), body: eventBody(locale, actorName, eventName) }), { type: 'event', groupId: gid, eventId: eid });`

New strings in `functions/src/notifications/strings.ts` (mirror the `expenseBody`
free-text-append convention — user free-text after a ` · ` separator, never
grammatically embedded, dropped when empty — the #483 RTL-safe pattern):

```ts
export function eventTitle(locale: Locale, groupName: string): string {
  return groupLabel(locale, groupName);
}
export function eventBody(locale: Locale, actorName: string, eventName: string): string {
  const actor = actorLabel(locale, actorName);
  const label = eventName.trim();
  const tail = label.length > 0 ? ` · ${label}` : '';
  return locale === 'ar'
    ? `أنشأ ${actor} حدثًا جديدًا${tail}.`
    : `${actor} created a new event${tail}.`;
}
```

Register in `functions/src/index.ts` as a **`export { … } from` re-export** (a bare
`export const` in index.ts is invisible to `tool/list_expected_functions.sh` and
would escape the deploy-drift check — CLAUDE.md trap):

```ts
export { eventNotifier } from './triggers/eventNotifier';
```

`tool/list_expected_functions.sh` extracts re-exports **dynamically**, so
`eventNotifier` joins the expected-deploy set automatically;
`release_workflow_gate_test.dart` asserts the two extractors agree (not an exact
set), so a single-line re-export passes (verified).

**No `firestore.rules` change** — the trigger runs under the Admin SDK (bypasses
rules) and only **reads** event/member/token docs; it never writes a financial doc.
**No client change** — the OS renders the `notification` payload; `data.type='event'`
only matters for the deferred v2 tap-route, and `notification_service._routeFromData`
already early-returns on any type ∉ {settlement, member_join} (so an `event` tap just
opens the app, exactly like the shipped `expense` type). `[ ] No new client display code` ✓.

## Verification principles (run against live `f6c1f6d3`)

1. **Callsite classification** — INBOUND only. The trigger READS the event doc +
   members + fcm_tokens and SENDS FCM; it writes **nothing** to a financial/domain
   doc (only `sendToUids` may *prune* a dead `fcm_tokens/{uid}`, same as the siblings).
   No OUTBOUND money/schema write.
2. **Concrete claims vs code:** `Event` model (`event_model.dart:55-93`) carries
   `createdBy:String`, `participantIds:List<String>`, `name:String`, `isDeleted:bool`;
   the create path `event_service.dart:104-121` writes them via `.set(toFirestoreMap())`
   at `groups/{gid}/events/{eid}`. `createdBy` is the **auth uid** (`create_event_screen.dart:141`
   passes `createdBy: uid`, non-null-guarded at `:120`). `participantIds` are member uids:
   rules gate them via `:367 participantIds.hasOnly(groupMembers())` where `groupMembers()`
   = `groupData.memberIds` (auth uids); the literal `auth.uid in participantIds` create
   check is at `:402`. Either way they are auth uids → map directly to `fcm_tokens/{uid}`,
   the same fact `expenseNotifier` already relies on.
3. **Read-path per write-path:** there is no write-path (read+send only). Recipients
   read `fcm_tokens/{uid}` → `getMessaging().sendEach`. No reader of a new field.
4. **Fields from the type:** enumerated from `event_model.dart` — only `createdBy`,
   `participantIds`, `name`, `isDeleted` are consumed; all present on the create doc.
5. **Data contract:** payload `{ type:'event', groupId:gid, eventId:eid }` (all string
   values — FCM requirement). Copy builder `(locale)=>({title,body})`.
6. **Arithmetic:** n/a — no money math; no amount in the event buzz.
7. **Adversarial / orthogonal axes:**
   - *Identity:* actor excluded via `uid !== createdBy`; actor name resolved by the
     `userId` FIELD (#294 creator-uuid-keying), not doc id — so the creator's own name
     resolves and a third-party-created event still names the right actor.
   - *Spurious server creates:* grep confirms **no** function `.set()`s an event doc
     (recovery migrates via `update`, deleteGroup deletes); only the user client creates
     one → no recovery/cascade false-buzz.
   - *Subcollection overlap:* `groups/{gid}/events/{eid}` matches the event doc at exact
     depth; `.../expenses/{id}` and `.../settlements/{id}` are deeper paths → no
     double-fire with `expenseNotifier`/`settlementNotifier`.
   - *Edit re-fire:* `onDocumentCreated` (NOT `...Written`) — an open-edit (#248), a
     soft-delete, or a recovery uid-migration `update()` never re-fires it.

## Idempotency note (parity, deliberate)

The two shipped sibling notifiers (`settlementNotifier`, `expenseNotifier`) do **not**
keep a dedup store; they satisfy "idempotent on event ID" by using `onDocumentCreated`
(one fire per create; never on updates) and accept the rare at-least-once retry
double-buzz as a benign cost (a duplicate tray notification, no data effect). This
notifier mirrors that exactly — introducing a dedup ledger for events alone would be
inconsistent and over-scoped. "Idempotent" here = create-only, edit-immune.

## Files touched

- `functions/src/triggers/eventNotifier.ts` — NEW (the trigger).
- `functions/src/notifications/strings.ts` — add `eventTitle` / `eventBody`.
- `functions/src/index.ts` — add the `export { eventNotifier } from …` re-export.
- `functions/test/triggers/eventNotifier.test.ts` — NEW (Jest emulator, mirrors
  `expenseNotifier.test.ts`).

## Acceptance boxes this PR closes (from #179)

- [x] Event-created buzzes `event.participantIds` ∖ creator, actor excluded.
- [x] No double-send on edits — `onDocumentCreated`, create-only (parity idempotency).
- [x] Stale tokens pruned on send failure — via shared `sendToUids`.
- [x] No new client display code — functions-only.
- [ ] **Verified on a real Android device** — human device QA (#40-class); the loop
  cannot tick this. → `Refs #179`, issue stays OPEN re-scoped to this lone box.
- [x] iOS explicitly out of scope.

With all 4 senders now wired, #179 is feature-complete pending the device-QA box.

## Test plan (Jest, emulator — `npm run test:emulator`)

`functions/test/triggers/eventNotifier.test.ts`, mirroring `expenseNotifier.test.ts`:
1. notifies all `participantIds` minus creator; title = group name, body contains actor
   name + event name; `data == { type:'event', groupId, eventId }`.
2. creator excluded even when present in `participantIds`.
3. single-participant (creator-only) event → `sendEach` not called.
4. `isDeleted:true` on create → not notified.
5. unresolved actor → localized "Someone"/"شخص ما" per recipient locale (en/ar).
6. target with no `fcm_tokens` doc → skipped (no send).
7. empty `name` → body has no trailing ` · ` fragment (drops cleanly).

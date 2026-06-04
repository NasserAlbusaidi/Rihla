# #53 — Build the real FCM sender + consumer

**Issue:** P2 — FCM token subsystem stores push-token PII with no sender/consumer.
**Decision (2026-06-04):** Build the real sender (option B), giving the stored token PII a legitimate purpose instead of ripping it out.

## Locked decisions

| Axis | Decision |
|---|---|
| Triggers | **Settlement recorded** + **Member joined** (NOT expense-added) |
| Localization | **Server-localized**; store `locale` on `fcm_tokens/{uid}`; en/ar string table on the server |
| Display | **flutter_local_notifications** + Android channel; FCM `notification`+`data` payload |
| Platform | **Android-first.** iOS push needs APNs cert + entitlement (no iOS CI) → explicit follow-up; client code must be crash-safe on iOS, just inert |

## Ground truth (verified against code, not memory)

- **Member docs are keyed by uid.** `joinGroupByInviteCode.ts:269` `members.doc(uid)` with `{id: uid, userId: uid}`. `group.memberIds[]` is an array of uids.
- **Settlement parties are uids.** `group_settle_up_screen.dart:402-403` passes `payerParticipantId: fromUserId, recipientParticipantId: toUserId`; `settlement_service.dart:93-94` persists them verbatim; `createdBy` = actor uid (`:104`). Confirmed against the balance provider treating them as uid keys (`group_balance_provider.dart:231-246`).
- **Settlement paths:** event-level `groups/{gid}/events/{eid}/settlements/{id}` (`eventSubcollection(...,'settlements')`), group-level `groups/{gid}/settlements/{id}`. Both write maps carry the fields the notifier reads: `payerParticipantId`, `recipientParticipantId`, `payerName`, `recipientName`, `amountFils`, `currency`, `createdBy`, `isDeleted`. NOTE: `scope`/`groupId` exist **only on the group-level write map** (`group_settlement_service.dart`); the event-level map (`settlement_service.dart:90-105`) omits them. The notifier does not read `scope`/`groupId` from the doc (it derives gid/eid from the trigger path), so the asymmetry is irrelevant to the sender.
- **Shadow/unclaimed members** have a member doc keyed by a non-uid id and no `fcm_tokens/{id}` doc → looked-up token is absent → recipient is silently skipped. No special-casing needed.
- **Token doc today** (`notification_service.dart:124-129`): `{user_id, token, platform, updated_at}`, owner-only r/w (`firestore.rules:164-167`). Deleted on account-delete (`deleteAccount.ts:690`) and anon-cleanup (`cleanupAnonUidArtifacts.ts:442`).
- **Connectivity probe** reads `fcm_tokens/{uid}` (`connectivity_provider.dart:46-63`). **Unchanged by this work** — the doc keeps existing (we now also use it), so the probe coupling that blocked removal is moot. No probe change.
- **Router:** `routerProvider` (`app_router.dart:139`) is a `Provider<GoRouter>`; `NotificationService` holds `_ref`, so tap-routing = `_ref.read(routerProvider).go(path)`.
- **Locale:** `AppSettings.languageCode` ('en' default; 'ar'), `settings_provider.dart`. No separate `localeCode`.
- **Existing trigger convention:** `writeRateMonitor.ts` — `onDocumentCreated`, `import '../admin'`, env-seam for thresholds, fire-after-commit, never mutate the financial doc.

## Recipient model

- **Settlement:** notify `{payerParticipantId, recipientParticipantId} \ {createdBy}` (the counterparty; both if creator is a third party — rare). Dedup, drop empties. Look up `fcm_tokens/{uid}` per target; skip missing.
- **Member-join:** notify `existingMemberIds \ {joinerUid}`, captured from the pre-join `memberIds` snapshot inside the join transaction. **Gated on an actual join** — see G1.

## Data payload + tap-route contract (BOTH notification types)

All FCM `data` values are strings (FCM requirement). Tap handler `_routeFromData(Map)` reads `type` then routes:

| `type` | `data` keys | tap route |
|---|---|---|
| `settlement` | `{type:'settlement', groupId, eventId?}` | `/group/${groupId}` |
| `member_join` | `{type:'member_join', groupId}` | `/group/${groupId}` |

Unknown `type` or missing `groupId` → no-op (no nav). Both route to the group landing (`/group/:gid`), which has the `PopScope`→`/home` cold-entry back-guard (`group_detail_screen.dart:52-60`) — safe as the sole stack page on a terminated-state tap. `eventId` is carried on settlement payloads for future event-deep-link use but does not change v1 routing (group landing only).

## Server architecture

### New: `functions/src/notifications/strings.ts`
Pure, no I/O. `type Locale = 'en' | 'ar'`. `normalizeLocale(raw): Locale` (default 'en'; map anything starting `ar` → 'ar'). Builders:
- `settlementTitle(locale, groupName)` / `settlementBody(locale, actorName, amountText)`
- `memberJoinTitle(locale, groupName)` / `memberJoinBody(locale, joinerName)`

### New: `functions/src/notifications/formatAmount.ts` — **MONEY SURFACE**
`formatAmount(amountFils: number, currency: string): string`. Mirrors `MoneySerializer` scale table **exactly** (`money_serializer.dart:8-19`): OMR/KWD/BHD → 3dp (÷1000), USD/EUR/GBP/SAR/AED/QAR → 2dp (÷100), JPY → 0dp (÷1). **Lookup is case-insensitive — `currency.toUpperCase()` before the table read**, mirroring `MoneySerializer._scale` (`money_serializer.dart:55-57`); a doc with `currency:'usd'` must scale ÷100, not fall through to the unknown path. Unknown currency (after upper-casing) → fall back to OMR scale (mirrors the client read-fence). Table-driven Jest tests: clean (each currency), **lowercase input (`'usd'`, `'omr'`)**, boundary (0, sub-unit, large), unknown-currency fallback. Display-only (never feeds balance math) but wrong scale = visibly wrong money → tested as money code.

### New: `functions/src/notifications/fcmSender.ts`
Modular admin API: `import { getMessaging, Message } from 'firebase-admin/messaging'` (matches `writeRateMonitor.ts` modular style — no namespaced `admin.messaging()`).
`sendToUids(uids, build, data)` where `build(locale) => {title, body}`:
1. Dedup uids, drop empty/falsy.
2. `Promise.all` read `fcm_tokens/{uid}`; collect `{uid, token, locale}` for docs with a non-empty string `token`.
3. Build one `Message` per token: `{token, notification: build(normalizeLocale(locale)), data, android: {priority: 'high'}}`. `data` values must all be strings.
4. `getMessaging().sendEach(messages)` (per-message, so one bad token doesn't fail the batch).
5. Prune: for responses with `error.code` in `{messaging/registration-token-not-registered, messaging/invalid-registration-token, messaging/invalid-argument}`, delete that `fcm_tokens/{uid}`. Best-effort; never throw out of the sender.
6. No-op fast path when `uids` empty or no tokens found.

### New: `functions/src/triggers/settlementNotifier.ts`
Two `onDocumentCreated`:
- `eventSettlementNotifier` — `groups/{gid}/events/{eid}/settlements/{id}`
- `groupSettlementNotifier` — `groups/{gid}/settlements/{id}`
Both → `notifySettlement(gid, eid|null, data)`:
- Bail if `!event.data` (undefined-snapshot guard, mirroring `writeRateMonitor.ts:93` `if (!snap) return`), `data.isDeleted === true`, or `amountFils` not a number.
- targets = dedup([payerParticipantId, recipientParticipantId]) minus createdBy, minus empties.
- actorName = `createdBy===payerParticipantId ? payerName : createdBy===recipientParticipantId ? recipientName : 'Someone'` — the third-party-recorder case (createdBy is neither party) must NOT mislabel the actor as the recipient; falls to 'Someone'. Then `?? 'Someone'` for null names.
- groupName = read `groups/{gid}.name` (best-effort; fallback to localized "your group").
- amountText = formatAmount(amountFils, currency).
- `sendToUids(targets, l => ({title: settlementTitle(l, groupName), body: settlementBody(l, actorName, amountText)}), {type:'settlement', groupId: gid, ...(eid?{eventId:eid}:{})})`.

### Modified: `functions/src/callables/joinGroupByInviteCode.ts`
- **G1 — gate the notify on an ACTUAL join (the join tx is idempotent).** The tx skips `arrayUnion` when `memberIds.includes(uid)` (`:304`) and skips the member-doc `set` when `memberSnap.exists` (`:312`), yet still returns success on a no-op re-join. A second tap of an invite link (or any committed-join client retry) would otherwise re-notify every member of a join that didn't happen. Capture `let didJoin = false` in the outer scope and set `didJoin = !memberSnap.exists` **inside the tx** (the same condition that gates the member-doc create — `:312`). Notify only when `didJoin` is true. (Outer-var write inside the tx is last-run-wins on Firestore retry — standard; the value reflects the committed run.) **Two-gate note:** the tx has two independent gates — `arrayUnion` on `!memberIds.includes(uid)` (`:305`) and the member-doc `set` on `!memberSnap.exists` (`:312`). They agree in every normal flow. We deliberately key `didJoin` to `!memberSnap.exists`; in the pathological split states the result is at worst an **under-notify** (the safe default — never spam a join that may not be new), never a false notification.
- Inside the tx, also capture `existingMemberIds = memberIds` (pre-arrayUnion snapshot) and `groupName = groupData.name` into outer `let`s.
- After `joinAttempts` delete + log, **iff `didJoin`**, fire-and-forget `notifyMemberJoin(gid, joinerUid=uid, joinerName=displayName, groupName, existingMemberIds)` in a `try/catch` that only `logger.warn`s. **Must never throw** — a notification failure must not fail a committed join. App Check unchanged.
- `notifyMemberJoin` recipients = `existingMemberIds \ {uid}`; `data = {type:'member_join', groupId: gid}`; copy = `memberJoinTitle/Body`.
- Return shape **unchanged** (`{groupId}`); only adds a gated side-effect.

### Modified: `functions/src/index.ts`
Export `eventSettlementNotifier`, `groupSettlementNotifier`.

### Unchanged
`deleteAccount.ts` / `cleanupAnonUidArtifacts.ts` already delete the whole `fcm_tokens/{uid}` doc — the added `locale` field rides along. No change. `firestore.rules` `fcm_tokens` block stays owner-only r/w with no field allow-list → adding `locale` needs no rule change (the rule does not enumerate fields).

## Client architecture

### `notification_service.dart`
- Add `'locale'` to both writes (`_saveToken:124`, `_onTokenRefresh:142`): value from a `String Function()? localeResolver` ctor override, default `() => _ref.read(settingsProvider).languageCode`.
- `_onForegroundMessage` (currently `{}`): show a local notification via the channel from `message.notification` (+ `message.data` as payload). Guard: only if `message.notification != null`.
- `_onMessageTap` (currently `{}`): `_routeFromData(message.data)`.
- New `_routeFromData(Map)`: per the contract table above — `type=='settlement'` **or** `type=='member_join'` with a non-empty `groupId` → `/group/${groupId}`; unknown type / missing groupId → no-op. Routes via `_ref.read(routerProvider).go(...)`.
- Terminated-state initial message + `onMessageOpenedApp` wiring lives where the service is initialized (bootstrap), feeding `_routeFromData`.

### `flutter_local_notifications`
- New dep in `pubspec.yaml`.
- One Android channel (id e.g. `rihla_activity`, importance high). Init the plugin + create channel in `initialize()` (Android only; iOS init is inert/no-crash).
- Local-notification tap callback → `_routeFromData(jsonDecode(payload))`.

### Background handler
- Top-level `@pragma('vm:entry-point') Future<void> firebaseMessagingBackgroundHandler(RemoteMessage)` registered via `FirebaseMessaging.onBackgroundMessage` in `main()`. Because we send a `notification` payload, Android auto-displays it when backgrounded/terminated; the handler is a near no-op (must call `Firebase.initializeApp` if it does any Firestore — it does not). Tap on the OS notification → `onMessageOpenedApp`/`getInitialMessage`.

### Android manifest (`android/app/src/main/AndroidManifest.xml`)
- `<meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="rihla_activity"/>`.
- `POST_NOTIFICATIONS` permission (Android 13+) if not already contributed by the plugin.

## Verification (7 principles)

1. **Callsite classification — token write:** `_saveToken`/`_onTokenRefresh` are OUTBOUND (feed the `fcm_tokens` doc the server reads). Adding `locale` is an additive write field; server read tolerates its absence (legacy docs) via `normalizeLocale` default. Connectivity probe is INBOUND-only on the same doc (reachability, ignores fields) — unaffected.
2. **Concrete claims vs code:** all paths/fields above grepped this session (members.doc(uid), settlement field names, settlement collection paths, routerProvider, languageCode, group.name). Re-grep at implementation time.
3. **One read-path per write-path:** new write = `locale` on `fcm_tokens`. Read-path = `fcmSender.sendToUids` (`normalizeLocale(doc.locale)`). Named. Connectivity probe also reads the doc but only for existence.
4. **Fields from the type:** settlement fields enumerated from `settlement_service.dart` write map + `Settlement.fromFirestore`, not memory.
5. **Data contracts:** FCM `data` map = `{type:'settlement', groupId, eventId?}` (all string values — FCM requires string values). Tap reads the same keys. `build(locale)` callback signature: `(Locale) => {title: string, body: string}`. Join callable return stays `{groupId}`.
6. **Arithmetic decomposition:** N/A to balances. The only money op is `formatAmount` display (fils → decimal string); scale table mirrors MoneySerializer exactly, table-tested. It does NOT decompose or sum.
7. **Adversarial pass (orthogonal axis — identity + idempotency):** a settlement where `createdBy` is a third party (neither payer nor recipient) → targets = both parties (correct); actorName falls to 'Someone' (not mis-attributed). payer==recipient → dedup → ≤1 target, no double-send. **Re-join (idempotent tx no-op) → `didJoin==false` → NO notification (G1).** First-member/empty group → `existingMemberIds \ {joiner}` = ∅ → no-op. Former/tombstone member as a settlement party → has a uid, may still have a token → notified (acceptable; party to the money).

## Test plan (TDD)

**Server (Jest + emulator, Java 21):**
- `formatAmount.test.ts` — table-driven: each currency scale, 0, boundary, unknown→OMR.
- `strings.test.ts` — en/ar non-empty, `normalizeLocale` mapping.
- `fcmSender.test.ts` — sends per token; skips missing-token uids; prunes on not-registered; never throws on send error; empty-uids no-op. (Mock `getMessaging().sendEach`.)
- `settlementNotifier.test.ts` — targets = parties minus actor; deleted settlement skipped; event vs group payload (`eventId` present/absent); missing token recipient skipped.
- `joinGroupByInviteCode.test.ts` — extend: first-time join notifies pre-join members minus joiner with `{type:'member_join', groupId}`; **re-join (already a member) sends NO notification (G1)**; notify failure does NOT fail the join (return still `{groupId}`); existing tests stay green.

**Client (flutter_test):**
- `notification_service_test.dart` — extend: token write includes `locale` from resolver; `_routeFromData` calls `routerProvider.go('/group/<gid>')` for both `type:settlement` and `type:member_join`; unknown type / missing groupId → no nav; foreground message with null notification → no local-notify call. (Inject a fake local-notifications plugin + a test router/observer.)
- `firestore.rules` — no change → no new rules test (existing `fcm_tokens` owner-only tests still cover it).

**Verify gates:** `flutter analyze` clean; `flutter test`; `cd functions && npm test`; color-lint unaffected.

## Phasing (each leaves tree green)

1. Server pure units: `formatAmount` + `strings` (+ tests). 
2. Server `fcmSender` (+ tests).
3. Server `settlementNotifier` triggers + index export (+ tests).
4. Server join-callable notify hook (+ tests).
5. Client: `locale` on token write (+ test).
6. Client: flutter_local_notifications dep + channel + foreground display.
7. Client: tap routing (`_routeFromData`) + bootstrap initial-message/onMessageOpenedApp wiring (+ tests).
8. Android manifest meta-data + permission; background handler in main().
9. Full verify; docs (`docs/CLOUD-FUNCTIONS.md` += 2 triggers; CLAUDE.md note if a bear trap surfaced).

## Risks / open

- **iOS push is inert** until APNs cert + entitlement + `firebase_messaging` iOS setup. Code stays crash-safe; tokens still stored. Follow-up issue.
- **Money-format scale drift** — the one money landmine; locked by table tests mirroring MoneySerializer.
- **Notification copy** leaks a display name + amount to other group members — but they are already group members who can read the settlement in-app. No new disclosure.
- **Join-tx retry** re-runs the outer-var capture; last commit wins → correct pre-join member snapshot.
</content>
</invoke>

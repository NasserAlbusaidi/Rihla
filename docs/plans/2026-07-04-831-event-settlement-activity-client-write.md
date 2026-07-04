# #831 Event-Settlement Activity — Client-Write Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** An event-scoped settlement recorded from the event ledger appears as one `event_settlement` row in the group activity feed (group timeline, cross-group History, home RECENTLY, search) — corrections and decomposed settle-up slices stay invisible, exactly like `group_settlement` today.

**Architecture:** Client-side `logGroupEvent` at the event settle-up write site, mirroring the existing `group_settlement` pattern in `group_settle_up_screen.dart` byte-for-byte where possible. NO server trigger, NO schema change, NO new Cloud Function. The only backend surface is one string added to the client-type allow-list in `security/firestore.rules` (Gate-category; requires a rules deploy after merge).

**Tech Stack:** Flutter/Riverpod, FakeFirebaseFirestore, Firestore rules emulator (Jest, Java 21).

---

## Why client-write, not server fan-in (Decision record)

A prior attempt (branch `codex/831-event-settlement-activity`, 3 failed Gate rounds) chose a server trigger on settlement creates. That mechanism cannot honor the existing #283 contract — corrections must NOT surface as fresh payments (`group_settle_up_screen.dart:958-960`) — because the settlement doc's only correction discriminator is user-forgeable localized note text. Safe server classification requires new schema (`correctionOfSettlementId`, now #889, corrections track #283/#753).

The client write site KNOWS record-vs-correction at the moment of writing, so suppression is a boolean, not a classifier. Accepted trade-offs (all parity with today's `group_settlement`, not regressions):

- **Durability:** fire-and-forget; the Firestore SDK queues it offline and replays, but a process-kill before replay loses the activity row (money row unaffected).
- **Forgeability:** any group member can forge an `event_settlement` row, same trust level as `group_settlement` (#814 value-domain floor still applies).
- **Rate accounting:** client-written → the `writeRateMonitor` T3 counts it as a real client write. The `expense_*` skip list is for SERVER-written types only — **no monitor change** (`group_settlement` precedent: allow-listed AND counted).

## Data contract — the new activity row

Written by `GroupActivityService.logGroupEvent` (fire-and-forget, uuid id, ISO-string timestamp — `group_activity_service.dart:111`):

| Field | Value |
|---|---|
| `type` | `'event_settlement'` |
| `actorId` | `currentUid` (already non-null in `_recordSettlement`) |
| `actorName` | `settingsProvider.deviceName` if non-empty else `fromName`, in try/catch falling back to `fromName` (mirror `group_settle_up_screen.dart:797-803`) |
| `description` | `'settled ${AppFormatters.formatCurrency(amount, currency)} with $counterpartyName'` where `counterpartyName = currentUid == toUserId ? fromName : toName` (#282 mirror; fallback-only string, never displayed for known types) |
| `metadata` | exactly the keys below |
| `timestamp` | written by the service |

Metadata (8 keys, cap is 16; every named key already typed by `validActivityMetadata` at `security/firestore.rules:1066-1081`; `eventId` rides opaque by design):

```dart
{
  'amountFils': MoneySerializer.toSubunits(amount, currency), // int — modern #808 shape, NOT legacy amount-string
  'currency': currency,
  'fromUserId': fromUserId,
  'toUserId': toUserId,
  'fromName': fromName,
  'toName': toName,
  'eventId': widget.eventId,
  if (eventName != null && eventName.isNotEmpty) 'eventName': eventName,
}
```

Suppression contracts (structural, no classifier):

1. **Correction** (`onCorrect`, `settle_up_screen.dart:366-377`) passes `logActivity: false` — mirror of the #283 comment in the group screen.
2. **Decomposed group settle-up slices** never pass through `settle_up_screen.dart` at all (`group_settle_up_screen._recordDecomposedSettlement` writes via `addSettlement` directly and logs its ONE aggregate `group_settlement` row) — no code needed, pinned by test in Task 6.

Read paths for the new row (one per write path, named):

- `localizedGroupActivityText` → reuses `_settlementText` direction phrases (`activity_display.dart:61-79`). **Decision:** same person→person vocabulary as `group_settlement` — zero new l10n keys; the money moved between people either way, and the event context is one tap away via the row target. `eventName` is still written for search and future phrasing.
- `glyphForGroupActivityType` → `ActivityGlyph.settlement`.
- `activityAmount` → served by the `amountFils`+`currency` branch (`activity_display.dart:152-178`), no change.
- `activityRowTarget` → `/group/{gid}/event/{eid}/ledger/settle-up` (route exists: `app_router.dart:62`); missing/forged `eventId` degrades to `/group/{gid}` via `_navMetadataString`.
- `activityMatchesQuery` → no change (localized text, from/to names, formatted amount already in the haystacks).

## Out of scope

- The per-event audit feed (`events/{eid}/activity_logs`) — SERVER-only since #248 PR2; covering it needs the server fan-in this plan deliberately avoids. Residual gap, noted on #831 at close.
- Correction labeling/visibility in feeds — #889 (corrections track #283/#753).
- Backfilling historical event settlements.
- Any change to money math, settlement writes, oracle, aggregate doc, or `writeRateMonitor`.
- Atomicity/durability upgrades for activity writes (parity with `group_settlement`).

---

### Task 1: Rules — accept `event_settlement` from a group member

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts:2857-2869`
- Modify: `security/firestore.rules:1104-1109` (type allow-list inside `validGroupActivityCreate`)

**Step 1: Extend the accept loop (RED)**

In the test at line 2857, add `'event_settlement'` to the accepted-types array (keep the deny loop at 2869 untouched — `expense_*`, `member_left`, `totally_made_up` stay denied):

```ts
test('#808/#831 each client-written group activity type is accepted (event_created/event_deleted/group_settlement/member_joined/event_settlement)', async () => {
  // existing body, loop over:
  for (const type of ['event_created', 'event_deleted', 'group_settlement', 'member_joined', 'event_settlement']) {
```

Add one metadata-shape test next to the existing #814 group_settlement metadata tests (~line 2903):

```ts
test('#831 event_settlement accepts the direction+event metadata shape', async () => {
  const member = memberDb();
  await assertSucceeds(member.doc('groups/g1/activity/ga-831-shape').set(
    validGroupActivity({
      id: 'ga-831-shape',
      type: 'event_settlement',
      metadata: {
        amountFils: 10500, currency: 'OMR',
        fromUserId: 'member-uid', toUserId: 'owner-uid',
        fromName: 'Member', toName: 'Owner',
        eventId: 'e1', eventName: 'Trip',
      },
    }),
  ));
});
```

(Adapt the fixture call to the file's actual `validGroupActivity` helper signature — read it before writing.)

**Step 2: Run to verify RED**

```bash
cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "each client-written group activity type is accepted"
```
Expected: FAIL — `event_settlement` rejected by the current 4-type list.

**Step 3: Rules edit (minimal)**

`security/firestore.rules` — extend the list and the comment:

```
            // #808 PR1: allow-list of CLIENT-written types. member_left is
            // written only by the leaveGroup/removeMember callables and
            // expense_* only by the expenseAuditLogger fan-in (both Admin
            // SDK, bypassing rules) — a client claiming them is a forgery.
            // The writeRateMonitor's expense_* skip is only safe because of
            // this list; extend BOTH together. #831: event_settlement is
            // CLIENT-written (event settle-up record path) — allow-listed
            // here and deliberately NOT in the monitor skip (a real client
            // write is counted, like group_settlement).
            && request.resource.data.type in [
              'event_created',
              'event_deleted',
              'event_settlement',
              'group_settlement',
              'member_joined'
            ]
```

**Step 4: Run to verify GREEN** (same command; then the full rules suite)

```bash
cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts
```
Expected: all pass.

**Step 5: Commit**

```bash
git add security/firestore.rules functions/test/firestore-rules-publish-readiness.test.ts
git commit -m "feat(rules): allow client-written event_settlement activity type (Refs #831)"
```

### Task 2: Display arms (glyph + localized text)

**Files:**
- Test: `test/features/activity/activity_display_test.dart` (find the existing `localizedGroupActivityText`/glyph test groups; create the case block alongside the `group_settlement` ones)
- Modify: `lib/features/activity/utils/activity_display.dart:12-22` and `:85-119`

**Step 1: Failing tests** — `event_settlement` renders the direction phrases (paid/received/between + legacy fallback) and the settlement glyph. Mirror the existing `group_settlement` test cases with `type: 'event_settlement'`.

**Step 2: RED run**
```bash
flutter test test/features/activity/activity_display_test.dart
```
Expected: FAIL — falls through to `log.description` / `ActivityGlyph.generic`.

**Step 3: Implement** — one arm in each switch:

```dart
  'event_settlement' => ActivityGlyph.settlement,
```
```dart
    'event_settlement' => _settlementText(l10n, log),
```

**Step 4: GREEN run** (same command). **Step 5: Commit** `feat(activity): render event_settlement rows with the settlement vocabulary (Refs #831)`.

### Task 3: Row target (deep link)

**Files:**
- Test: `test/features/activity/activity_nav_test.dart` (alongside the existing `group_settlement`/`expense_added` cases)
- Modify: `lib/features/activity/utils/activity_nav.dart:29-55`

**Step 1: Failing tests** — with `eventId` in metadata → `/group/g1/event/e1/ledger/settle-up`; missing/empty/non-string `eventId` → `/group/g1`.

**Step 2: RED run**
```bash
flutter test test/features/activity/activity_nav_test.dart
```

**Step 3: Implement**

```dart
    case 'event_settlement':
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId/ledger/settle-up';
```

**Step 4: GREEN run.** **Step 5: Commit** `feat(activity): event_settlement rows deep-link to the event settle-up (Refs #831)`.

### Task 4: The write site — record logs ONE `event_settlement` row

**Files:**
- Test: `test/features/ledger/settle_up_screen_test.dart` (existing harness records a settlement through the screen; add an activity-collection assertion)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (`_recordSettlement` at :727, its two callers)

**Step 1: Failing test** — after recording via the screen, `groups/{gid}/activity` contains exactly one doc with `type == 'event_settlement'`, `actorId == currentUid`, and the exact 8-key metadata contract (assert `amountFils` is the int subunits of the recorded amount, `eventId == widget.eventId`, direction keys match the tile).

**Step 2: RED run**
```bash
flutter test test/features/ledger/settle_up_screen_test.dart
```
Expected: FAIL — zero activity docs (this is the #831 bug, reproduced).

**Step 3: Implement.** `_recordSettlement` gains two params:

```dart
    bool logActivity = true,
    String? eventName,
```

After the success bookkeeping (after the `ledgerRevisionNotifier.state++` / connectivity notes, before the snackbar), mirror the group pattern:

```dart
      if (logActivity) {
        // #831: one activity row per recorded event settlement. Mirrors the
        // group_settlement client write; corrections pass logActivity: false
        // (#283: a reversal must not surface as a fresh payment).
        String actorName;
        try {
          actorName = ref.read(settingsProvider).deviceName.isNotEmpty
              ? ref.read(settingsProvider).deviceName
              : fromName;
        } catch (_) {
          actorName = fromName;
        }
        final counterpartyName = currentUid == toUserId ? fromName : toName;
        ref.read(groupActivityServiceProvider).logGroupEvent(
          groupId: widget.groupId,
          type: 'event_settlement',
          actorId: currentUid,
          actorName: actorName,
          description:
              'settled ${AppFormatters.formatCurrency(amount, currency)} with $counterpartyName',
          metadata: {
            'amountFils': MoneySerializer.toSubunits(amount, currency),
            'currency': currency,
            'fromUserId': fromUserId,
            'toUserId': toUserId,
            'fromName': fromName,
            'toName': toName,
            'eventId': widget.eventId,
            if (eventName != null && eventName.isNotEmpty) 'eventName': eventName,
          },
        );
      }
```

Thread `eventName: event.name` from the record caller (the step-runner around :656 already holds `eventName` for the WhatsApp nudge). Log placement is INSIDE the try success path so a failed money write never logs; queued (offline) still logs — the SDK replays both, matching group behavior.

**Step 4: GREEN run** (same command). **Step 5: Commit** `fix(ledger): event settle-up records an event_settlement activity row (Refs #831)`.

### Task 5: Correction suppression (the #283 mirror)

**Files:**
- Test: `test/features/ledger/settle_up_screen_test.dart` (or the file that exercises `onCorrect` — check `settle_up_revalidation_test.dart` / history tests for the existing correction harness)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart:366-377`

**Step 1: Failing test** — drive the correct affordance on a recorded settlement; assert the offsetting settlement doc IS written and the activity collection gains NO new doc.

**Step 2: RED run** — expected FAIL: after Task 4, `onCorrect` still defaults `logActivity: true`, so a second activity row appears. (Fails for exactly the right reason.)

**Step 3: Implement** — at the `onCorrect` callsite add:

```dart
                    // #283/#831: corrections record the offsetting reverse but
                    // must NOT emit an event_settlement activity entry — the
                    // type-rendered feed would show a reversal as a fresh
                    // payment (mirror of the group_settlement suppression).
                    logActivity: false,
```

**Step 4: GREEN run.** **Step 5: Commit** `fix(ledger): correction path suppresses the event_settlement activity row (Refs #831)`.

### Task 6: Pin the decomposed settle-up invariant (regression guard, expected green immediately)

**Files:**
- Test: `test/features/groups/settle_up_logical_history_test.dart`

**Step 1:** Add an assertion to the existing decomposed settle-up test: after a decomposed group settle-up, `groups/{gid}/activity` holds exactly ONE row and its type is `group_settlement` — zero `event_settlement` rows for the slices. State in the test comment that slices bypass `settle_up_screen.dart` structurally.

**Step 2:** Run — expected PASS immediately (guard, not TDD):
```bash
flutter test test/features/groups/settle_up_logical_history_test.dart
```

**Step 3: Commit** `test(groups): decomposed settle-up slices emit no event_settlement rows (Refs #831)`.

### Task 7: Full verification

```bash
flutter analyze                        # clean
bash tool/check_theme_purity.sh        # no display code added, but new widgets = trap; run anyway
flutter test test/features/activity/ test/features/ledger/ test/features/groups/
cd functions && npm run test:emulator  # full rules suite
```

### Task 8: Docs + PR

- Update `docs/SECURITY-RULES.md` activity section: client type list is now 5 entries; `event_settlement` client-written from the event settle-up record path; corrections/decomposed slices deliberately unlogged.
- PR body: `Closes #831` + `Spec: docs/plans/2026-07-04-831-event-settlement-activity-client-write.md` + **RED evidence** (paste Task 4 Step 2 failing output) + note **rules deploy required** (joins the pending #882/#875 deploy queue — flag for `deploy-ceremony`).
- Note the residual per-event-feed gap on #831 in a closing comment (server-only surface, deferred with #889).

---

## Embedded Verification Pass (7 principles, run 2026-07-04 against `origin/main` @ 906ae982)

1. **Callsite classification.** The new write is OUTBOUND (activity doc). Readers of `groups/{gid}/activity` rows: `group_activity_screen.dart`, `cross_group_activity_pager.dart`/History tab, home RECENTLY rows, `activityMatchesQuery` search — ALL INBOUND display-only. Nothing reads activity rows into a money write path (the #366 aggregate is settlement/expense-triggered, not activity-triggered).
2. **Concrete claims vs code.** Allow-list at `security/firestore.rules:1104-1109` (verified by read); `validActivityMetadata` types all 5 named string keys + `amountFils` int + `currency` allow-list (:1066-1081); monitor skip is `type.startsWith('expense_')` only (`writeRateMonitor.ts:135-137`); route `/group/:gid/event/:eid/ledger/settle-up` exists (`app_router.dart:62`); `logGroupEvent` field set verified (`group_activity_service.dart:111-134`); accept/deny rules tests at `firestore-rules-publish-readiness.test.ts:2857/2869`.
3. **One read-path per write-path.** Named above: display text (`localizedGroupActivityText`), glyph, amount (`activityAmount` fils branch), nav (`activityRowTarget`), search — each gets a task/test.
4. **Fields from the type.** `GroupActivityLog`: id/type/actorId/actorName/description/metadata/timestamp (model read, `group_activity_log_model.dart:12-33`) — the write supplies all seven via `logGroupEvent`.
5. **Exact contracts.** Metadata keys + types tabulated above; 8 keys ≤ 16 cap; `eventId` opaque by design (matches `activity_nav.dart` guard comment: rules type 11 named keys, `eventId`/`expenseId` stay opaque).
6. **Arithmetic decomposition.** No money math changes. `amountFils = MoneySerializer.toSubunits(amount, currency)` — the settlement `amount` is already currency-quantized by the settle-up flow (same value written to the settlement doc), so subunit conversion is exact.
7. **Orthogonal-axis worked example (corrections × decomposition).** Record OMR 3.000 event settlement A→B → 1 `event_settlement` row. Correct it → offsetting B→A settlement doc, 0 new activity rows (Task 5). Group settle-up decomposing into 2 event slices + residual → 2 event settlement docs + 1 group settlement doc, but activity = exactly 1 `group_settlement` row (Task 6). Closed event: settlements stay writable after close (epic #202 contract — `eventAcceptsExpenseWrites` replaced `eventAllowsClientWrites` for EXPENSE paths only), and `validGroupActivityCreate` gates on `groupAllowsClientWrites`, not event state → the activity row on a closed-event settlement is accepted. Consistent.

**Deploy note:** rules-only backend delta. After merge, `tool/pending_deploy.sh` will list it alongside the already-pending #882/#875 — one ceremony covers all three.

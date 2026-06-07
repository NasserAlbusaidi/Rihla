# #248 PR 4/5 — Open expense editing (any event participant)

**Branch:** `feat/248-pr4-open-expense-editing` · **Refs #248** (NOT `Closes` — PR5 affordance still owed)
**Gate:** MANDATORY (touches `firestore.rules` + a money/ownership invariant). Fresh-context Opus, no-P1.
**Deploy:** rules → client (deploy-first; old clients keep working — `lastEditedBy` pin is present-only).

---

## 1. What & why

Drop the creator-only gate on expense **edit + soft-delete** so **any event participant** can edit/delete any non-deleted expense. Group creator is a participant, so retains full rights. Hardcoded `open` policy; the rule is structured so a future `ledgerEditPolicy` read wraps the single who-can-edit branch (#248 deferred fast-follow), per issue Implementation rule #8.

**Why now is safe (log-before-widen, issue Implementation rule #2):** PR2's `expenseAuditLogger` trigger is **live in prod** — verified `backend-deployed` tag = `b53433d` (contains `export { expenseAuditLogger }`) and `firebase functions:list --project rihla-safar` shows `expenseAuditLogger` (v2, firestore.document.written, us-central1, nodejs22). So every edit a non-creator now makes is already attributed + logged + rendered (PR3 #340). The silent-rewrite window the feature exists to prevent does not open.

**Out of scope (do NOT bundle):** settlements (#282 client-block / #283 offset — parallel track); the configurable `related` policy (deferred); the creator-vs-payer editor affordance (PR5). Keep the diff to the open-edit gate + its mirror + docs.

## 2. Precondition checklist (all verified before spec)
- [x] PR1 (`lastEditedBy`) merged `a9ef95a`, deployed (rules).
- [x] PR2 (`expenseAuditLogger` + `validActivityCreate` server-lock) merged `b53433d`, **live in prod** (tag + functions:list).
- [x] PR3 (feed before/after) merged `bfd538d`.

## 3. The rules change — `security/firestore.rules`

### 3a. `validExpenseUpdate()` (currently lines 620–660)
**Single deletion:** remove line 624 `&& requesterIsRecordCreator()`.

After:
```
function validExpenseUpdate() {
  return module == 'expenses'
    && isEventParticipant(groupId, eventId)        // ← the single who-can-edit branch (OPEN policy)
    && eventAllowsClientWrites(groupId, eventId)
    && request.resource.data.createdBy == resource.data.createdBy   // createdBy still IMMUTABLE
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly([... unchanged ...])
    && validExpenseBase(request.resource.data, affectsExpenseAllocation())
    && (!...hasAny(['splitDistribution']) || splitValuesNonNegative(request.resource.data))  // #192/#194
    && (!...hasAny(['lastEditedBy']) || request.resource.data.lastEditedBy == request.auth.uid)  // unforgeable editor
    && expenseFreeTextDiffOk()
    && ( (no isDeleted/deletedAt change) || validSoftDelete() );    // soft-delete append-only, false→true only
}
```

Everything except the deleted line is **byte-identical**. The change is purely "who," not "what."

**Invariants preserved (re-confirm in Gate):**
- `createdBy` immutable — line 625 `request.resource.data.createdBy == resource.data.createdBy` stays.
- `lastEditedBy == request.auth.uid` (diff-gated) — line 651-652 stays → a non-creator editor still **cannot forge** the blame; they stamp themselves.
- `splitValuesNonNegative` (#192/#194) — stays.
- `validSoftDelete` false→true only (no resurrection) — stays; append-only.
- `affectedKeys().hasOnly([...])` allowlist (no rogue fields) — stays.

### 3a-bis. lastEditedBy pin: diff-gated → MANDATORY (automerge-Gate refute finding)

**The refuter caught a [P1] the spec/Gate missed.** PR1 made the pin **diff-gated**: `!diff.hasAny(['lastEditedBy']) || lastEditedBy == auth.uid`. So an editor who **omits** `lastEditedBy` skips the pin. The `expenseAuditLogger` trigger attributes via `lastEditedBy || createdBy` (`expenseAuditLogger.ts:160`), so an omitted field blames the **creator** — not the editor. Inert before PR4 (only the creator could edit → `createdBy` *was* the editor); **PR4 makes it exploitable** by any participant → the "tamper-proof" log can be silently defeated/mis-attributed exactly when non-creators start editing. This breaks PR4's own *log-before-widen* safety property.

**Fix:** make the pin **present-and-equal** — `request.resource.data.lastEditedBy == request.auth.uid` on **every** expense update (drops the diff-gate). The merged doc must end with the caller as `lastEditedBy`, so an edit cannot be unattributed. Reverses PR1's diff-gating; the PR1 merge-preservation footgun (an update that doesn't re-stamp inheriting a stale value) **no longer applies** because the only client update/soft-delete callers (`edit_expense_screen.dart:106/159`) always re-stamp `lastEditedBy` to the caller; only pre-PR1 clients omit it (no real users → safe, per the deploy-freely rule). Trigger left as-is (its `|| createdBy` fallback now only fires for create — `createdBy==auth.uid`, correct — and Admin/legacy writes).

**Test ripple:** every existing expense-update *success* test must now stamp `lastEditedBy` (7 calls across 6 tests: custom-splits, creator-update, creator-soft-delete, allow-soft-delete, #191 archival ×2, #192/#194 legacy soft-deletes); every *denial* test that omitted it gets the caller's own `lastEditedBy` so the denial **isolates its intended guard** (createdBy-immutability, ghost-participant, stale-payer, #192, #194) rather than tripping the pin. New RED tests: update-without-lastEditedBy denied; non-creator omit denied (the hole); non-creator soft-delete omit denied. Flip PR1's "old-client update WITHOUT lastEditedBy still allowed" → now denied.

### 3b. B1 ownership comment block (currently lines 147–156)
Rewrite the `requesterIsRecordCreator` doc comment so it no longer claims "only the creator can later change or remove it" for expenses. New text states: **expenses** are open-edit by any event participant (audit-logged via the `expenseAuditLogger` trigger, editor pinned by `lastEditedBy`); the `requesterIsRecordCreator` helper is now **unreferenced by any live `allow` clause** (its only callers — `validEventSettlementUpdate`, `validGroupSettlementUpdate` — sit behind hard `allow update: if false` blocks) and is retained for the settlement-corrections track (#283). Note the future `ledgerEditPolicy` `open|related` seam. Do NOT claim it "governs settlements" — settlement updates are denied outright today.

### 3c. What must NOT change
- `validExpenseCreate` — unchanged (create was already any-participant; uses `isEventParticipant` + `createdBy == auth.uid`, never `requesterIsRecordCreator`).
- `validSoftDelete`, `affectsExpenseAllocation`, `validExpenseBase`, `splitValuesNonNegative`, `isEventParticipant` — unchanged.
- `allow update: if validExpenseUpdate();` (line 724) — unchanged.
- **`requesterIsRecordCreator` becomes retained-but-DEAD after this PR** (Gate R1 correction): removing the :624 call leaves it referenced only by `validEventSettlementUpdate` (:702) and `validGroupSettlementUpdate` (:879) — **both dead**, because their match blocks hard-deny (`match /events/.../settlements` `allow update: if false` :734; `match /groups/.../settlements` `allow update: if false` :901; neither calls the fn). It compiles fine (Firestore does not reject unreferenced functions) and is harmless to leave. **Do NOT delete it / the two dead functions in this PR** — that is dead-code cleanup that does not belong bundled into a money/rules feature PR (one-PR-one-thing); kept as scaffolding for the settlement-corrections track (#283). Optional follow-up: a standalone rules dead-code sweep. Update the :147-156 comment to say "retained for the settlement track, currently unreferenced," NOT "creator-only governs settlements."

## 4. The client change — `lib/features/ledger/screens/edit_expense_screen.dart` (lines 56–67)

Replace the `isCreator` gate with a participant gate (mirrors the rule). **Optimistic fallback** on non-data event states (chosen 2026-06-07): rules are the real backstop, never block a real participant over a transient event-stream hiccup.

Inside the existing `data:` branch (after `expense` is resolved):
```dart
final currentUid = ref.watch(currentUserIdProvider);
final eventAsync = ref.watch(eventDetailProvider((groupId: groupId, eventId: eventId)));
// #248 PR4: OPEN edit — any event participant may edit/delete. Rules enforce
// (validExpenseUpdate + lastEditedBy pin); this gate is UX only. Optimistic:
// if the event hasn't resolved we show the editor and let rules reject a true
// non-participant on save — a stream hiccup must not block a real participant.
final event = eventAsync.valueOrNull;
final canEdit = currentUid == null            // unauth: let downstream handle (matches prior null-uid pass)
    ? true
    : event == null                            // loading / error / deleted-or-missing → optimistic allow
        ? true
        : event.participantIds.contains(currentUid);
if (!canEdit) {
  return _ErrorScaffold(
    title: context.l10n.editorViewOnlyTitle,
    message: context.l10n.editorViewOnlyMessage,
  );
}
```
- `eventDetailProvider` returns `Event?` (StreamProvider.family keyed `({groupId, eventId})`); `.valueOrNull` collapses loading→null, error→null, and a genuinely null/deleted event→null — all three take the optimistic path.
- Remove the now-stale `isCreator` / empty-`createdBy` legacy comment (lines 57-58).

**Note (pre-existing, NOT a PR4 regression — Gate R1 confirmed inert):** rules already permit editing an *already-soft-deleted* expense (the "no isDeleted change" branch :654-657 holds for a deleted doc), and `expenseAuditLogger` early-returns on `wasDeleted` (`expenseAuditLogger.ts:79`) → such an edit is **silent + unattributed**. PR4 widens this tombstone-edit reachability from creator to any-participant. It stays **inert for money**: the expense streams filter `isDeleted == false` (`expense_service.dart:36/56/81`), so a tombstone's `amountFils` is never read into a balance and the client never surfaces deleted expenses for editing. No fix here (tightening tombstone-edit is out of this PR's one concern); **logged as a follow-up candidate** (block updates when `resource.data.isDeleted == true` except resurrection-which-is-already-denied). Do not expand PR4 scope to cover it.

## 5. l10n — `lib/l10n/app_en.arb` + `app_ar.arb`
The view-only reason changed from "you didn't create it" to "you're not a participant." Retext **message only** (keys `editorViewOnlyTitle`/`editorViewOnlyMessage` unchanged → `generated_l10n_surface_test` stays green):
- EN `editorViewOnlyMessage`: `"Only people in this event can edit expenses."`
- AR `editorViewOnlyMessage`: `"يمكن فقط للمشاركين في هذه الفعالية تعديل المصاريف."`
- Keep `editorViewOnlyTitle` = "View only" / "عرض فقط".
- Run `flutter gen-l10n` (or build) to regenerate.

## 6. Tests — RED first (issue Implementation rule #5)

### 6a. Rules emulator — `functions/test/firestore-rules-publish-readiness.test.ts`
Actors: `g1.memberIds=['owner','member']`, `e1.participantIds=['owner','member']`, `eve`=outsider (not member, not participant). `seedExpense()` → `exp1` createdBy `owner`.

**FLIP (were the creator-only pins — now RED until rules change):**
1. L1101 `expense non-creator cannot update peer record` → **`participant non-creator CAN update peer record`**: `member` updates `exp1` `{amountFils:12500, lastEditedBy:'member'}` → `assertSucceeds`.
2. L1110 `expense non-creator cannot soft-delete peer record` → **CAN soft-delete**: `member` `{isDeleted:true, deletedAt:..., lastEditedBy:'member'}` → `assertSucceeds`.
3. L1214 `#248 non-creator still cannot update ... PR1` → **`#248 PR4 participant non-creator CAN update with own lastEditedBy`** (`member` `{amountFils:12500, lastEditedBy:'member'}` → `assertSucceeds`).

**ADD (new guards — must be GREEN after change):**
4. `#248 PR4 participant non-creator FORGING lastEditedBy is rejected`: `member` `{amountFils:12500, lastEditedBy:'owner'}` → `assertFails` (pin :651 holds for non-creators).
5. `#248 PR4 participant non-creator cannot mutate createdBy`: `member` `{createdBy:'member', lastEditedBy:'member'}` → `assertFails` (immutability holds).
6. `#248 PR4 non-MEMBER outsider cannot update expense`: `eve` (not in `g1.memberIds`) `{amountFils:12500, lastEditedBy:'eve'}` → `assertFails` (blocked at read+`isEventParticipant`).
7. `#248 PR4 participant non-creator update re-sending negative splitDistribution is denied`: `member` update with a negative split → `assertFails` (#192 holds across the wider WHO).
8. **(Gate R1 — the boundary that matters)** `#248 PR4 group-member who is NOT an event participant cannot update expense`: seed a second event `e2` via `seedEvent('e2', { participantIds: ['owner'], createdBy:'owner', ... })` and an expense `expE2` in it (createdBy `owner`); `member` (IS in `g1.memberIds` → passes `isGroupMember`/read, but NOT in `e2.participantIds`) updates `expE2` `{amountFils:12500, lastEditedBy:'member'}` → `assertFails`. This proves the gate is `isEventParticipant` (`:144`, checks `participantIds`) — NOT `isGroupMember`. Test 6 (outsider) does not exercise this because `eve` is blocked earlier. Confirm `seedEvent`'s exact override shape against the helper (`firestore-rules-publish-readiness.test.ts:139`) when writing; mirror the `validExpense` keys for `expE2`.

**KEEP GREEN (regression pins):** L1092 creator can still update; L1136 createdBy immutable; L1542 #192; all settlement tests L1261+ (event + group settlement updates still denied/creator-gated — proves no settlement drift).

### 6b. Edit widget — `test/features/ledger/edit_expense_screen_test.dart`
`_event.participantIds=['uid-yasmin','uid-layla']`. `_pumpEditExpenseScreen` must now also override `eventDetailProvider((groupId:..., eventId:...)).overrideWith((ref)=>Stream.value(_event))` (the screen newly watches it).

1. **FLIP L69-78** (`currentUid:'uid-layla'`, expense `createdBy:'uid-yasmin'`): `uid-layla` is a participant → now sees the **editor** (`find.byKey(LedgerKeys.editExpenseSheet)` / "Edit expense"), NOT "View only".
2. **ADD**: a non-participant uid (`currentUid:'uid-zara'`, not in `_event.participantIds`) → still sees View-only. Assert BOTH `find.text('View only')` (title) AND the **new** message `find.text('Only people in this event can edit expenses.')` (the retexted `editorViewOnlyMessage` from §5) — with the `eventDetailProvider` override present so the gate resolves to a real `Event` (not the optimistic null path).
3. Existing creator (`uid-yasmin`) editor tests stay green.

### 6c. Run
`cd functions && npm test` (Jest + emulator, Java 21) — RED on flips before rules change, GREEN after. `flutter test test/features/ledger/edit_expense_screen_test.dart` — RED before client change, GREEN after. Then `flutter analyze` clean + full `flutter test` + full `functions` suite.

## 7. Docs — `CLAUDE.md`
Rewrite the **B1 invariant** (Key Invariants section): expenses are now **open-edit** — any event participant may create/edit/soft-delete; `createdBy` immutable; editor identity pinned by `lastEditedBy == auth.uid` (unforgeable); every change server-audit-logged (`expenseAuditLogger`). Creator-only edit **no longer applies to expenses** (still governs group settlements). Note the deferred `ledgerEditPolicy` `open|related` toggle. Keep the soft-delete/append-only + #192 lines.

## 8. Deploy & merge (after Gate + green)
- `/automerge` (Gate-category → fresh-context diff review + refuter before enabling auto-merge).
- After merge: `deploy-ceremony` skill (`pending_deploy.sh` → deploy rules → prod-state verify → advance `backend-deployed` tag → DEPLOY-LEDGER). Rules-only deploy (no new function).
- PR body: `Refs #248`, `Spec:` line → this file, paste RED-before/GREEN-after for the flipped tests.

## 9. Acceptance (this PR's slice of the epic)
- [ ] Any event participant edits/soft-deletes any non-deleted expense; non-participant rejected by rules (test 6).
- [ ] Creator retains edit (L1092 green).
- [ ] `lastEditedBy` pin holds for non-creators — forgery rejected (test 4).
- [ ] `createdBy` immutable on peer edits (test 5); #192 holds (test 7); soft-delete append-only (flip 2 + no-resurrection pins).
- [ ] Settlements untouched (L1261+ green; `validExpenseUpdate` is `module=='expenses'`-gated and both settlement blocks hard-deny update). `requesterIsRecordCreator` left retained-but-dead (NOT deleted; rationale §3c).
- [ ] Client mirror: participant sees editor, non-participant sees View-only; optimistic on event-load failure.
- [ ] CLAUDE.md B1 rewritten with the behavior change.
- [ ] Backend deployed before any client release exposing this (deploy-first).

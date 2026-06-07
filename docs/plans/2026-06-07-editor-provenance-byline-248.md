# #248 PR 5/5 — editor creator-vs-payer provenance byline

**Date:** 2026-06-07
**Issue:** #248 (EPIC) — final step. This PR carries `Closes #248`.
**Type:** client-only, display-only. **Gate-EXEMPT** (no money math, no `firestore.rules`, no Cloud Functions, no routing, no schema/field-name change — it only READS existing `createdBy`/`lastEditedBy` for display; INBOUND/no write path).

## Goal

Now that **any event participant** can edit/delete any expense (PR4, live in prod), the editor must surface **provenance** — who **added** the expense (and who last **edited** it), distinct from who **paid** (already shown in the "Paid by" card). This is the epic's last acceptance half: *"editor surfaces creator vs payer."*

## Decision (locked with user, 2026-06-07)

**Compact byline under the title** — a single muted line placed directly under the description field, above the Category strip. **Edit mode only.** Lightest touch, no new card.

```
        OMR 12.000
        ─────────
   Dinner with the crew

   Added by Gemini · edited by Codex      ← new byline
   ───────────────────────────────
   Category  [Food] [Taxi] ...
```

- "**Added by {creator}**" always (when a creator is stamped).
- "**· edited by {editor}**" appended only when `lastEditedBy` is non-empty **and** `lastEditedBy != createdBy` (a self-edit by the creator adds no new actor → no "edited by").
- Hidden entirely for legacy expenses with **no** `createdBy` (`''`).
- Hidden in **add** mode (no expense yet).

## Verified facts (code, not memory — 2026-06-07)

1. **All three ids share the uid space.** `MemberNameResolver.disambiguateEventParticipants(event)` iterates `event.participantIds` as `uid` and looks up `event.participantNames[uid]`; `_findMember` matches `member.userId == uid`. `payerParticipantId` is selected from `event.participantIds` (`_PayerPickerSheet` pops an id from `participantIds`). `Expense.createdBy`/`lastEditedBy` are auth uids (model docstring; `addExpense(createdBy: currentUid)`, `updateExpense(lastEditedBy: currentUid)`). → name resolution is uniform via `event.participantNames` + disambiguation, **same as the payer**.
2. **Reuse PR3's resolution chain.** `expense_audit_detail.dart::_name` does `participantNames[uid]` → name, else `activitySomeone` ("Someone"). `_PaidByCard` does `displayNames[id] ?? participantNames[id] ?? fallback`. PR5 uses the identical chain: `disambiguateEventParticipants(event)[uid] ?? event.participantNames[uid] ?? l10n.activitySomeone`.
3. **The editor already has both inputs in scope.** `ExpenseEditorBody.build` computes `event = eventDetailProvider(...).valueOrNull` (needed for name resolution) and holds `widget.initial` (the expense). Byline gated on `_isEdit && event != null`; when the event stream hasn't resolved the byline is simply absent (appears on resolve) — never blocks the form.
4. **No existing test breaks.** All editor tests use **exact** `find.text('Yasmin')` / `find.text('Omar')` matchers; the byline embeds the name in `"Added by Yasmin Khan"`, so exact matchers don't collide (verified `expense_editor_body_test.dart`, `expense_editor_body_same_name_test.dart`, `edit_expense_screen_test.dart`). No edit-mode golden exists (`grep` of `test/goldens` for editor = none). Add-mode tests + the add golden are unaffected (byline is edit-only). The PR4 test `'a participant who is not the creator sees the editor'` is exactly PR5's scenario — Layla editing Yasmin's expense will now read "Added by Yasmin Khan"; its assertions (`'View only' findsNothing`, sheet key present) are untouched.

## 7 verification principles (run inline — Gate-exempt but reported)

1. **Callsite classification:** the byline is **INBOUND** (display only) — it reads `createdBy`/`lastEditedBy` and never feeds a write. No OUTBOUND/BOTH path touched. The save/delete write maps in `edit_expense_screen.dart` are unchanged.
2. **Concrete claims vs code:** every path/field above was grepped/read this session (model fields, resolver, ARB keys, test matchers). `activitySomeone` exists (en:1035 "Someone", ar:436 "شخص ما").
3. **Read-path per write-path:** no write-path added. The only read is display of two pre-existing fields.
4. **Fields enumerated from the type:** `Expense.createdBy` (String, default `''`), `Expense.lastEditedBy` (String, default `''`) — read from `expense_model.dart`.
5. **Data contract spelled out:** `resolveExpenseProvenance({createdBy, lastEditedBy, resolveName})` → `ExpenseProvenance{creatorName, editorName?}` or `null`. `resolveName: String Function(String uid)`. editorName non-null ⇔ `lastEditedBy.isNotEmpty && lastEditedBy != createdBy`.
6. **Arithmetic decomposition:** N/A — no money aggregation; amounts are not summed or sliced here.
7. **Adversarial pass (orthogonal axis = identity):** the fix is on the *display* axis; the adversarial case is on *identity* — (a) creator left the event (uid absent from `participantIds` → falls to raw `participantNames[uid]` then "Someone"), (b) two same-named participants (disambiguator appends ` (#last4)` so creator/editor stay distinct), (c) legacy expense with `createdBy == ''` (byline hidden), (d) `lastEditedBy == createdBy` (self-edit → "edited by" suppressed). All four are pinned by tests.

## Files

| File | Change |
|---|---|
| `lib/features/ledger/utils/expense_provenance.dart` | NEW — pure `resolveExpenseProvenance` + `ExpenseProvenance` value type (no Flutter deps; takes a `resolveName` closure). |
| `lib/features/ledger/widgets/expense_editor_body.dart` | Add `_ExpenseProvenanceByline` widget; mount under `_DescriptionField`, gated `_isEdit && event != null`. |
| `lib/l10n/app_en.arb` / `app_ar.arb` | NEW keys `editorProvenanceAdded({name})`, `editorProvenanceAddedEdited({creator},{editor})`. Run `flutter gen-l10n`. |
| `test/features/ledger/expense_provenance_test.dart` | NEW — pure-logic table tests. |
| `test/features/ledger/expense_editor_body_test.dart` | ADD byline widget tests (added-only / added+edited / hidden-legacy / add-mode-absent). |

## TDD

- **RED first:** `expense_provenance_test.dart` against the not-yet-written util (compile-RED), then the widget tests.
- Pure-logic cases: empty `createdBy` → null; `lastEditedBy==createdBy` → editorName null; distinct non-empty `lastEditedBy` → both; unknown uid → "Someone" via the closure; empty `lastEditedBy` → editorName null.
- Widget cases (edit mode): renders "Added by {creator}" only; renders "… · edited by {editor}" when a third party last edited; **absent** for `createdBy==''`; **absent** in add mode.
- Green gate: `flutter analyze` clean + full `flutter test` green.

## Refs #248 (epic stays OPEN until #342)

PR5 delivers the editor affordance (reachable from the ledger) — the second half of acceptance criterion 6. But the audit **feed** that PR2/PR3 populate stays **user-unreachable** until **#342** ships an entry point (the route `AppRoutes.eventActivity` has zero in-`lib/` callers). Rather than close the epic with the audit log invisible end-to-end, PR5 carries **`Refs #248`** and #248 stays open, **re-scoped to the one unmet box: feed visibility via #342** (maintainer decision, 2026-06-07). The epic closes when #342 lands an in-app entry point.

`/automerge` will classify this EXEMPT → native auto-merge on green `readiness`.

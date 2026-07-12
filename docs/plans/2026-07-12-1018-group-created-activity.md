# #1018 — log group creation into the activity feed (server trigger)

Spec of record: issue #1018 body (design pivot adversarially reviewed 2026-07-07;
4 verifiers + Opus adversary). This plan records the fresh re-verification of its
claims against `main` @ 974267f2 (2026-07-12) and the build decomposition.

## Re-verified claims (this session, live greps)

| Claim | Verified |
|---|---|
| No trigger scopes bare `groups/{gid}` create | ✅ `grep onDocumentCreated functions/src` — only subcollection triggers (settlements, activity, events, expenses) |
| Server fan-in precedent + doc shape | ✅ `expenseAuditLogger.ts:258-275` writes `groups/{gid}/activity/{event.id}` — fields `id,type,actorId,actorName,description,metadata,timestamp(ISO string)` |
| `validGroupActivityCreate` client allow-list excludes `group_created` | ✅ `security/firestore.rules:1186-1190` — `['event_created','event_deleted','member_joined']`; zero rules change needed |
| Monitor-skip coupling | ✅ `writeRateMonitor.ts:151` skips `expense_*` + `SKIPPED_ACTIVITY_TYPES` only; spec says NO `group_created` skip entry — the Admin write is legitimately counted |
| Client fallback for unknown types | ✅ `activity_display.dart` `_ => log.description` (text) and `_ => ActivityGlyph.generic` (glyph) |
| Nav needs no change | ✅ `activity_nav.dart` `activityRowTarget` default → `/group/$groupId` (group detail — correct target) |
| Filter strip safe | ✅ `group_activity_screen.dart:366` `_matches` — unknown types appear under "All" only; acceptable for a genesis row, mirrors unknown-type default |
| `group.createdAt` is serverTimestamp | ✅ `group_provider.dart:224` `FieldValue.serverTimestamp()` |
| `actorName` required by model | ✅ `group_activity_log_model.dart` — required, `?? 'Unknown'` on read; trigger must resolve creator name |
| `resolveActorName` convention | ✅ deliberately MIRRORED per trigger file (expenseAuditLogger/expenseNotifier/eventNotifier each carry a copy, matching members by `userId` FIELD not doc id — mixed keying #294/#524) |

## Build decomposition (worktree `1018-group-created-activity`, branch `feat/1018-group-created-activity`)

1. **Server** — new `functions/src/triggers/groupCreatedLogger.ts`:
   `onDocumentCreated('groups/{gid}')` → Admin-SDK `.set` on
   `groups/{gid}/activity/{event.id}`:
   - `id = event.id` (idempotent across at-least-once retries, same as expenseAuditLogger D7)
   - `type = 'group_created'`, `actorId = group.createdBy` (missing/non-string → warn + skip)
   - `actorName` via mirrored `resolveActorName` (userId-field match)
   - `description` = verb phrase WITHOUT actor name (#808 lesson): `created the group`
   - `metadata = {}` (cross-group History joins groupName from `userGroupsProvider`, not metadata)
   - `timestamp` = `group.createdAt.toDate().toISOString()`; fallback `event.time` if absent/mistyped
   - `export { groupCreatedLogger } from './triggers/groupCreatedLogger'` in `index.ts`
     (single-line `export {} from` re-export — visible to `tool/list_expected_functions.sh`)
   - Emulator test (RED first) in `functions/test/triggers/groupCreatedLogger.test.ts`
   - Negative rules test: member client write of `type:'group_created'` denied
     (`firestore-rules-publish-readiness.test.ts`), allow-list untouched
2. **Client** — read path in the same PR:
   - `'group_created'` case in `localizedGroupActivityText` + `glyphForGroupActivityType`
   - ARB keys in BOTH `app_en.arb` and `app_ar.arb` (AR matches sibling register);
     regenerate + include generated l10n (#245 trap)
   - Glyph: reuse an existing `ActivityGlyph` value unless one obviously fits better
   - Widget/unit tests for the new case + unknown-type fallback untouched
3. **Lead** — integrate, `flutter analyze`, targeted suites + functions emulator suite
   (serialized — #1157 port fix not yet on main), branch-diff review, PR `Closes #1018`
   (also `Refs #997` context), `/automerge` (functions/** ⇒ Gate-category review + refuter).

## Explicit non-goals (from spec)
- No `firestore.rules` edit, no founding-batch write, no `writeRateMonitor` skip entry,
  no `event_created` row for the #245 seeded event, no metadata payload.

Gate: not a mandatory pre-implementation category (no rules surface; trigger is display
fan-out, not auth/validation) — per the spec's own Gate note the `/automerge`
fresh-context review + refuter is the checkpoint.

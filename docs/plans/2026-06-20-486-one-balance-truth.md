# #486 — One balance truth (group detail): stop printing your net twice + dedupe "New event"

**Branch:** `feat/486-one-balance-truth` (off `main`)
**Scope:** group-detail screen only. Ledger/settle-up over-restatement = noted follow-ups.
**Gate:** display-only (no money-math/rules/routing/schema). Technically exempt; running fresh-context Gate on this spec anyway (issue author flagged it).

## Decisions (locked with user 2026-06-20)

- **Hero CTAs unchanged** — keep `[+ New event] [Settle up]`. (User picked "keep New event in hero".)
- **Dedupe New event** — remove the Events **section-header** action (`actionLabel`/`onActionTap`), keeping the hero CTA as the lone entry. Empty-state "Create event" CTA stays (contextual, not a duplicate alongside the others).
- **Hero naming deferred** — keep the tri-state caption ("they owe you / you owe / all settled"). People roster carries the per-person names.
- **Roster** — `_MembersCard` lists OTHER members as today (name + role + signed per-currency net); the current user's row collapses to a muted **"You" + "shown above"** (no figure, non-tappable), rendered **last**.
- **Rename MEMBERS → PEOPLE** — both §A2 + #382 mockups mandate it; signals "roster, not a second balance statement".

## Forward-compatibility with the locked-but-deferred #382 overhaul

§A2 (single-currency) IS #382's "1 currency = unchanged" base case. Keep the per-person amount as the existing **per-currency list** (`List<({currency, net})>`, length 1 today) so #382 extends rows to N chips without a rewrite. Do NOT collapse to a scalar. Branch off `main` (no #242 dependency).

## Files

- `lib/features/groups/screens/group_detail_screen.dart`
  - Remove `actionLabel`/`onActionTap` from the Events `SectionHeader` (~:226-233).
  - Rename Members `SectionHeader` title → `groupPeople` (~:251); key `membersAndBalancesSection` unchanged.
  - `_MembersCard.build`: split `members` into `others` (pid ≠ currentUid) + optional `self`; render others via `_MemberRow` (unchanged), then `_SelfRow` last.
  - New `_SelfRow` widget: `RAvatar(name)` + `Text(groupRoleYou)` + trailing muted `Text(groupBalanceShownAbove)`. No `onTap`, no RAmount.
- `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb`
  - `groupPeople` = "People" / "الأشخاص"
  - `groupBalanceShownAbove` = "shown above" / (natural AR)
- Tests (update obsolete asserts; add regressions).

## Invariants preserved

- Per-currency lists for other-member rows (no cross-currency sum).
- `membersHasError` / `forceLoading` early-return error+skeleton path untouched.
- Empty-map-still-lists-everyone (landmine #6): roster of others + self-row still render with no balances.
- Identity match by userId field (existing `participantId == currentUid`).
- `Directionality.ltr` on RAmount (other rows unchanged).

## TDD — RED first (Gate-revised)

`_SelfRow` = a `_MemberRow` variant: same avatar + name + "(You)" role + `Flexible`/baseline layout (no overflow), but trailing figure → muted `groupBalanceShownAbove`, **non-tappable**, **carries `GroupKeys.selfMemberRow`**, no RAmount.

New regressions (all RED on current code — magnitude-independent, do NOT rely on the identical-15.000 fixture):
1. **No double-print:** `find.byKey(GroupKeys.selfMemberRow)` findsOneWidget (RED: key is new) + `find.descendant(of: selfMemberRow, matching: find.byType(RAmount))` findsNothing (no figure in self-row) + `find.text('shown above')` findsOneWidget. Hero still shows the net (`_textContaining('15.000')` findsWidgets + 'they owe you').
2. **Single "New event":** `find.text('New event')` findsOneWidget (hero only; section-header action gone).
3. **Rename:** `find.text('PEOPLE')` findsOneWidget; `find.text('MEMBERS')` findsNothing.
4. **Roster intact:** `find.descendant(of: bobRow(), matching: find.byType(RAmount))` findsWidgets (other members keep their net).

Existing asserts to update — **full inventory (Gate P1-B), verified by grep:**
- `group_detail_screen_test.dart`: `:408` `'MEMBERS'`→`'PEOPLE'`; `:619`,`:637` `'New event' findsWidgets`→`findsOneWidget`. Multi-ccy block `:865-1006` — **VERIFIED SAFE, no change** (hero figures are unscoped `findsWidgets`, survive; `bobRow()` is not the current user). `'Alice'`/`'Bob'` asserts (`:410-411,445-446`) — **unchanged** (self-row keeps the name).
- `group_screens_test.dart`: `:274` `'MEMBERS'`→`'PEOPLE'`; `:360` `'New event' findsWidgets`→`findsOneWidget`. `'Alice'`/`'Bob'`/`'—'` (`:275-276,316-318,335-337`) — unchanged.
- `group_detail_events_test.dart`: `:262`,`:330` `'New event' findsWidgets`→`findsOneWidget`; `:261,274` eventsSection unchanged.
- `group_detail_navigation_test.dart`: `:161-169` — **clarity rework, not RED→GREEN** (it taps `.first` = hero, already passes): rename to "hero New event CTA routes to create-event", tap the lone `'New event'`, assert routes; add positive `find.text('New event') findsOneWidget` (events header has no action).
- New key: `GroupKeys.selfMemberRow` in `lib/features/groups/keys/group_keys.dart`.

Edges (correct-by-construction, stated per Gate P3): `currentUid == null` or current user absent from `memberNames` → no self-row, all render as others, no crash. Identity matched by the `userId` field (memberNames keys = `m.userId`; existing `participantId == currentUid`).

## Verify

`flutter analyze` clean; `flutter test test/features/groups/ test/features/group_detail_screen_test.dart`; color-lint clean.

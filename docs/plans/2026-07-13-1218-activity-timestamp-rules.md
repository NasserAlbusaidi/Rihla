# Spec A — #1218: harden activity-row `timestamp` (+ description cap) in `validGroupActivityCreate`

Issue: #1218 (P2, security). Branch: `fix/1218-activity-timestamp-rules`. Commit body carries `Closes #1218`.
Spec file ships in the PR as `docs/plans/2026-07-13-1218-activity-timestamp-rules.md`.

## Problem (verified 2026-07-13 against main @2ce0891c)

`security/firestore.rules` `validGroupActivityCreate` (~L1163–1196) validates the feed sort key with only
`request.resource.data.timestamp is string` (L1195) and `description` with only `is string` (L1192, no
length cap). Every feed query orders by this client string at the QUERY layer
(`lib/features/groups/services/group_activity_service.dart:48-50`, `.orderBy('timestamp', descending:
true).limit(5|50)`), and `decodeDocsSkippingMalformed` runs only AFTER the limited window is chosen. Two
attacks by any single member:

- (a) **Feed DoS**: 5 rows with `timestamp: "zzzzz"` occupy the entire home RECENTLY window; malformed-skip
  then renders `[]` for every member.
- (b) **Feed hijack**: valid far-future ISO (`9999-12-31T23:59:59.999Z`) parses fine and pins forged rows
  above all real activity forever.

## Fix — rules (the only enforcement surface)

In `validGroupActivityCreate`, replace `timestamp is string` with ONE anchored `matches()`:

**CRITICAL — anchoring (Gate round-1 P1, both reviewers):** Firestore rules `string.matches()` is a
PARTIAL/SUBSTRING match, NOT full-match. Unanchored, `"zzz2026-07-13T12:00:00.000Z"` contains a matching
substring, is ALLOWED, and still sorts as `"zzz…"` above every real ISO row — the exact DoS/hijack this
spec closes. Every existing positive `matches()` in `security/firestore.rules` anchors with `^…$`
(L29, L43, L56-58, L776) — follow that convention. The regex below is prescriptive, not builder's choice.

The check is TWO expressions (Gate round-2 redesign — FUTURE-ONLY bound):

```
&& request.resource.data.timestamp.matches(
     '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\\.[0-9]{3}([0-9]{3})?Z$')
&& request.resource.data.timestamp < string(request.time.year() + 2)
```

- **No lower/past bound — deliberate.** Both attacks require a timestamp that sorts to the TOP: every
  reader is newest-first (`watchRecentActivity` :48-50 descending, `fetchActivityPage(Raw)` descending,
  `activityUnreadProvider` reduces to MAX). A past-dated forgery sorts to the bottom and is harmless. A
  lower bound would be the ONLY source of a false-deny for a slow-clock device (Firebase auth validates
  tokens against SERVER time, so a >1yr-SLOW clock still authenticates) — and a denied activity row
  atomically fails the co-batched event create/delete (#1140). Past = unbounded, on purpose; say so in
  the rules comment.
- **Future bound via lexicographic compare**: the anchored shape guarantees a leading 4-digit year, so
  `timestamp < string(request.time.year() + 2)` allows years ≤ now+1 (`"2027-…" < "2028"` true;
  `"2028-…" < "2028"` false). now+1 absorbs fast clock skew, the New-Year boundary, and
  offline-queued-batch commit lag (`request.time` is COMMIT time).
- **Component ranges** (month 01-12, day 01-31, hh 00-23, mm/ss 00-59) close the `"<y+1>-99-99T99:99:…"`
  lexicographic out-pin (which would otherwise sort above every legit row until the year rolls) and cost
  no false-deny — Dart only ever emits valid components.

Shape source of truth: the sole client writer (`GroupActivityService.buildActivityDoc`,
`group_activity_service.dart:165`, `timestampUtc.toIso8601String()`) — Dart UTC ISO with milliseconds
ALWAYS present (`.mmm`) and microseconds appended only when non-zero (`.mmmuuu`), trailing `Z`.

**Accepted residual (document VERBATIM in rules comment + PR body):** a forger can still pin a row at up
to `<year+1>-12-31T23:59:59.999999Z` (~1–2 years out) — it TOP-PINS the feed AND falsely lights the home
unread dot (`activityUnreadProvider` reduces to MAX timestamp); both un-pin/clear when real time catches
up. Bounded and self-healing vs today's forever-pin.

**New hard-failure direction (document in PR body + buildActivityDoc comment):** a device clock >1 year
FAST now has its activity rows denied → **event create/delete fails atomically** (the #1140 co-batch);
`member_joined` via fire-and-forget `logGroupEvent` merely loses a cosmetic row (errors swallowed) —
scope the comment to event create/delete, NOT "all activity writes". Tiny population (NTP), but it
converts a cosmetic mis-sort into a hard failure — stated, not hidden. Update `buildActivityDoc`'s
"always passes validGroupActivityCreate" doc comment (:147-148) to "passes … provided the device clock
is less than ~1 year fast (rules future-bound, #1218)".

And cap description: `description is string && description.size() <= 280` (UTF-16 units — matches
`validFreeText`'s cap; client descriptions are short verb phrases, #808 — legit max is ~50 chars
[l10n phrase + 32-cap event name]; 280 is kept anyway as the established validFreeText mirror rather
than inventing a new bound — record that trade-off in the rules comment). **Size-only, deliberately NOT
mirroring `validFreeText`'s control-char rejection**: descriptions are composed from l10n phrases + event
names, and a control-char false-deny would atomically kill the co-batched event create (#1140) — the
display read path is already type-guarded + #928 malformed-skip. State this in the rules comment.

**Explicit NON-goals (do not build):**
- **NO actorName pinning to the caller's member doc.** Two reasons, both verified: (i) a member freely
  updates their own member-doc `displayName` (propagateDisplayName path), so a pin buys ~nothing against a
  deliberate forger; (ii) member-doc keying is MIXED (legacy uuid-keyed docs) and activity rows are
  CO-BATCHED with event create/delete (#1140) — any false deny on the activity row atomically fails the
  whole event-create batch. `isValidDisplayName(actorName)` stays as-is. Record this reasoning in the rules
  comment.
- NO per-member rate cap (per-IP is banned by #197; per-actor rows are already bounded by the type
  allow-list and App Check is the real per-actor control). If a reviewer wants one, it's a follow-up issue.
- NO change to the type allow-list, `validActivityMetadata`, or the writeRateMonitor skip list.
- NO client-side query/deser changes (the malformed-skip #928 semantics stay).

## Fix — client (conformance guard, not enforcement)

`buildActivityDoc` (`group_activity_service.dart:149-167`): normalize defensively —
`timestampUtc.toUtc().toIso8601String()` — so a caller passing a LOCAL DateTime can never emit a Z-less
string that the new rules reject (which would atomically kill the co-batched event create). Grep ALL
callers of `buildActivityDoc`/`logGroupEvent` and confirm each already passes UTC (round-2 review
verified all three current callers do); fix any that don't. Rewrite the :147-148 doc comment as
described in the Fix section — the "always passes" claim is now conditional on the device clock being
<~1yr fast, and the comment must say so instead of overclaiming.

## Tests (RED first — rules emulator suite)

Location: alongside the existing rules tests (find via `functions/test/firestore-rules-*.test.ts`; follow
the existing harness/fixtures). Run via `cd functions && npm run test:emulator -- <file>` (NEVER bare jest,
#1157).

RED (fail on current main, pass after):
1. Member forges activity row with `timestamp: "zzzzz"` → DENIED.
2. Member forges `timestamp: "9999-12-31T23:59:59.999Z"` → DENIED (future bound).
3. Member forges a Z-less local ISO (`2026-07-13T12:00:00.000`) → DENIED.
4. `description` of 281 chars → DENIED.
5. **Anchor tripwires (the true attack vector — these distinguish the anchored fix from a broken
   substring match):** junk-PREFIXED valid current-year ISO (`"zzz<currentYear>-01-01T00:00:00.000Z"`)
   → DENIED, and junk-SUFFIXED (`"<currentYear>-01-01T00:00:00.000Zzzz"`) → DENIED.
6. **Component-range tripwire:** `"<currentYear+1>-99-99T99:99:99.999Z"` → DENIED (would otherwise
   lexicographically out-pin every legit row).
All year literals in EVERY fixture (RED and GREEN, including the Z-less case above and the hand-crafted
6-digit-fraction GREEN case — JS `toISOString()` only emits 3 digits, so #8 must be string-interpolated
`${new Date().getFullYear()}-01-01T00:00:00.123456Z`) derived dynamically from the wall clock, never
hardcoded — the emulator's `request.time` is real time and hardcoded years time-rot.

GREEN (must pass before AND after — the no-false-deny guard):
7. Legit row with 3-digit-fraction UTC ISO of "now" → ALLOWED.
8. Legit row with 6-digit-fraction UTC ISO (`.123456Z`) → ALLOWED.
9. Future boundary: `now.year + 1` dated row → ALLOWED (dynamic year).
10. **No-past-bound pin**: a far-past row (e.g. `2020-01-01T00:00:00.000Z`) → ALLOWED — pins the
    deliberate unbounded-past decision (slow clocks must never kill the event batch).
11. **The real co-batched shape**: one batch = event-create doc + its activity row (mirror the client's
    #1140 batch exactly) → ALLOWED. This is the false-deny tripwire.
12. 280-char description → ALLOWED.
13. Full `firestore-rules-publish-readiness` suite green (catches the 1000-expression ceiling
    empirically) — including its existing `validGroupActivity` fixtures (they use
    `new Date().toISOString()` → `.mmmZ`, which passes the new regex).

## Landmines

- **1000-expression ceiling**: the activity CREATE path is separate from the event-update hot path, but
  keep additions cheap anyway — two `matches()` + one `size()` on request data only, no new `get()`s.
- Rules `string.size()` counts UTF-16 code units — do NOT "fix" toward code points (#527 refuted).
- `matches()` is SUBSTRING-match — the regex MUST keep its `^`/`$` anchors (see Fix section); regex
  backslashes need escaping in the rules source.
- Server-authored rows (recordSettlement, leaveGroup/removeMember `member_left`, #1018 genesis) use the
  Admin SDK and bypass rules — untouched by this change; do not "align" them.
- Existing already-forged docs are unaffected (create-only rules); no migration.

## Acceptance

- [ ] All RED tests (1–6, incl. anchor + component-range tripwires) written first, observed failing
      (paste output in PR body), then green.
- [ ] GREEN suite 7–13 pass; readiness suite green; no other rules behavior changed (diff is
      validGroupActivityCreate + comment only).
- [ ] `buildActivityDoc` normalizes to UTC; caller sweep documented in PR body.
- [ ] `flutter analyze` clean; affected Flutter tests green (`test/features/groups/`,
      `test/features/activity/` if they exercise activity writes).
- [ ] PR body: `Closes #1218` (and in the squash commit body), RED evidence pasted, note "rules NOT
      deployed — pending deploy ceremony".

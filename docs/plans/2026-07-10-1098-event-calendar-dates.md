# #1098 — Event Dates as Timezone-Independent Calendar Dates (UTC-Anchored Carriers)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** the calendar date a user picks for an event's start/end must render as that same calendar date on every device in every timezone.

**Architecture:** `startDate`/`endDate` become **UTC-anchored calendar-date carriers** end-to-end: at capture, the picker's wall-clock y/m/d is anchored to `DateTime.utc(y, m, d, 12)` (a shared `anchorCalendarDate` helper); at persistence, both write sites re-anchor defensively (idempotent); at read, `Event.fromDoc` re-anchors from the stored instant's UTC components. Because a `DateTime`'s `.year/.month/.day` (and `DateFormat`, `toIso8601String`, `DateUtils.dateOnly`) read the instance's OWN components with no implicit conversion, every existing formatter/reader becomes timezone-independent WITHOUT being touched. Field type stays `DateTime?`, Firestore type stays `Timestamp`, rules' `is timestamp` shape checks stay byte-identical — no schema migration, no rules deploy.

**Tech stack:** Flutter/Dart. New helper in `lib/core/utils/calendar_date.dart` + targeted edits at 2 write sites, 2 picker sites, 1 read site.

**Issue:** #1098 (P2). Scout-mapped + author-verified 2026-07-10 against main @ 262cfc65. Gate round 1: 1 P1 resolved (day-count consumers ceil raw instant diffs — noon anchor would regress "in N days" rendering; fixed systemically in Task 3b) + 2 P2 (existing test assertions, full consumer sweep) + P3s folded. Gate round 2: 1 P1 resolved (the SAME subtitle method's ONGOING classifier stays raw-instant — both branches now convert) + P2s (test INPUT anchoring, `createdAt`-fallback carve-out, correct file path, clamp preserved) folded.

---

## Bug mechanics (verified file:line)

- Pickers return device-local wall-clock midnight: `create_event_screen.dart:238-245` stores raw; `event_info_section.dart:67-84` additionally calls `.toUtc()` (:77,:79) — a no-op on the persisted instant and ACTIVELY HARMFUL to any y/m/d-based fix (it shifts the calendar components before anchoring could read them); it must be removed.
- Two independent write sites bake the local offset into the stored instant: `event_model.dart:201-202` (`toFirestoreMap` → `Timestamp.fromDate`) on the create path, and `event_service.dart:290,293` (`updateEvent`'s direct partial map — does NOT route through `toFirestoreMap`) on the edit path. The offset is then unrecoverable.
- Read pivot: `Event.fromDoc` (`event_model.dart:166-167`) → `dateOrNull` (`firestore_parse.dart:7-11`) → `toDate()` which returns a LOCAL-flagged DateTime in the READER's offset. Every downstream y/m/d extraction (`localized_dates.dart:14-53` → event cards/recap; `trip_receipt_format.dart:73-82` → CSV/PDF; `event_command_center.dart:428` → `liveTripDay`) inherits the reader-local shift: a date picked in Muscat renders one day off in New York.
- No money-math consumer reads these fields (scout grep, Gate-confirmed). Precision (round-2 P3): the event list sort compares `createdAt` — `startDate` is only a null-first discriminator (`event_service.dart:52-59`), so noon-vs-midnight cannot reorder mixed legacy/new docs.
- `Event.isPast` (`event_model.dart:261-263`) does raw-instant arithmetic on `endDate` but has ZERO lib call sites (UI-dead; only its own tests, which build naive dates directly) — cite in the Task-4 sweep as "dead, no action; a future caller must use `calendarDayDiff`" (round-2 P3).

## Core invariant (spell it out in the helper's doc comment)

**An event calendar date is carried ONLY as a UTC-flagged `DateTime` at UTC noon of the picked y/m/d.** Producers anchor at capture; boundaries re-anchor defensively; readers rebuild the anchor from stored UTC components. Anchoring is IDEMPOTENT for its two sanctioned inputs: a naive/local picker value (components = picked wall-clock date — correct) and an already-anchored UTC value (components read in UTC — same date). It is WRONG for a `.toUtc()`-converted local value (components already shifted) — which is why the `event_info_section` conversions are removed, not built upon.

Why noon, given UTC-in/UTC-out already makes our readers TZ-independent: defense in depth. If a FUTURE reader accidentally extracts components after `.toLocal()`, noon-anchoring bounds the error to zero for every offset in [-12, +12] (all real offsets except +13/+14 edge zones), instead of half the world being off-by-one from a midnight anchor.

**Corrected in Gate round 1: noon is NOT harmless for consumers that do INSTANT ARITHMETIC against `now`.** Three live sites day-count/window on raw instants (`add_expense_target_sheet.dart:90-92` ceils `start.difference(now).inHours/24` for "Upcoming · in N days"; `active_journeys_provider.dart:88-97` `_isActive` and `:124-133` `_priority` window the home journey strip + FAB fast-path target). Under the noon anchor a UTC+4 tomorrow event would read "in 2 days" until 16:00 local — a rendered regression for the primary market. These consumers were ALREADY timezone-fragile today (local-midnight instants compared to reader-local `now` shift cross-device); the correct semantics for them is CALENDAR-day comparison, which Task 3b installs. Day-counting on raw event-date instants is henceforth forbidden — use the calendar helpers.

## Deliberate decisions (do not re-litigate)

1. **No schema change.** A y/m/d string field would touch `**/models/**` serialization, `firestore.rules` type checks (`:458-459`, `:498-499` — and the event-update path already sits near the ~1000-expression ceiling, #723), and every reader's type assumption, while STILL needing dual-type legacy parsing. Strictly dominated by the anchor approach.
2. **Legacy docs: accept the shifted display, document it.** Existing docs hold local-midnight instants whose original offset is unrecoverable — every read interpretation is wrong for someone (UTC extraction breaks the one previously-correct case: the creator viewing in their own original offset). No read branch can fix this; the field is display-only; there are no real users yet. New writes are correct forever; old docs may render one day off for some viewers. Do NOT build a legacy-preserving read branch.
3. **`dateOrNull` stays untouched.** It serves genuinely-instant fields (`createdAt` etc.) where local conversion is CORRECT (#1036/#1097 territory). Event dates get their own reader; do not globalize calendar semantics into the shared parser.
4. **Formatters stay untouched** — that is the point of the carrier invariant. The regression tests prove it holds through `formatShortMonthDay`/`formatDateRangeShort`, `receiptDate`, and `liveTripDay` rather than editing them.
5. **`liveTripDay` (#789) keeps its own internal UTC re-anchor** — it becomes redundant-but-harmless for event dates and still guards its `DateTime.now()` third input. Leave it.
6. **`event_model.dart` is a `models/**` file** → this PR is automerge Gate-category by path (in addition to being Gate-specced here). Expected; do not try to relocate the model edit to dodge classification.

---

### Task 1: The helper + its unit tests (RED first)

**Files:**
- Create: `lib/core/utils/calendar_date.dart`
- Create: `test/unit/calendar_date_test.dart`

**Step 1: tests first** (they fail to compile — the helper doesn't exist; the omission-RED shape #1116/#1090 used):
1. naive local `DateTime(2026, 7, 10)` → `2026-07-10T12:00:00.000Z` (`isUtc`, hour 12)
2. idempotence: `anchorCalendarDate(anchorCalendarDate(x)) == anchorCalendarDate(x)`
3. component fidelity: for a naive `DateTime(2026, 12, 31, 23, 59)` the anchor is Dec 31 UTC noon (time-of-day discarded, date kept)
4. round-trip through Firestore types: `Timestamp.fromDate(anchor).toDate().toUtc()` has the same y/m/d

**Step 2: implement**

```dart
/// Event calendar dates are carried ONLY as UTC-noon-anchored DateTimes —
/// see the invariant in docs/plans/2026-07-10-1098-event-calendar-dates.md.
/// Reads y/m/d off the instance's own components: correct for naive picker
/// output and idempotent for already-anchored values; NEVER feed it a
/// .toUtc()-converted local instant (components already shifted).
DateTime anchorCalendarDate(DateTime picked) =>
    DateTime.utc(picked.year, picked.month, picked.day, 12);

/// Whole-calendar-day difference `b - a` by components (each side anchored to
/// its own UTC midnight first), immune to time-of-day, DST, and the carrier's
/// noon anchor. THE way to day-count an event date against `now` — raw
/// instant arithmetic (`difference().inHours / 24`) regresses under the
/// noon-anchored carrier (Gate r1 P1) and was already tz-fragile before it.
int calendarDayDiff(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
```

Unit tests for `calendarDayDiff` alongside the anchor tests: same day → 0 (any times-of-day); anchored-noon tomorrow vs local-now morning → 1; across a month boundary; negative direction.

**Step 3:** unit file green. **Commit** `feat(core): UTC-noon calendar-date anchor helper` (body `Refs #1098`).

### Task 2: Cross-device regression tests for the event pipeline (RED)

**Files:**
- Modify: `test/features/events/models/event_model_test.dart` (or a new `test/unit/event_calendar_date_1098_test.dart`)

Write FIRST, watch fail (behavioral RED — today's pipeline produces local-flagged reads):
1. **Write-side**: build an `Event` with `startDate: anchorCalendarDate(DateTime(2026, 7, 10))`, run `toFirestoreMap()`, assert the stored `Timestamp` instant is exactly `2026-07-10T12:00:00Z` — machine-timezone-INDEPENDENT assertion (compare `millisecondsSinceEpoch` against `DateTime.utc(2026,7,10,12)`). (RED today only via Task 3's defensive re-anchor if the input is naive — make the primary RED the read-side case below.)
2. **Read-side (the core RED)**: `Event.fromDoc` on a doc whose `startDate` is `Timestamp.fromDate(DateTime.utc(2026, 7, 10, 12))` → assert `event.startDate!.isUtc` is true AND `.day == 10` — fails today (`dateOrNull` returns local-flagged; on any machine west of UTC the day reads 9... on UTC+x machines day may still read 10, so ALSO assert `isUtc` — that assertion is machine-independent RED).
3. **Formatter pass-through**: `formatShortMonthDay` / `receiptDate` / `liveTripDay` on the UTC-anchored value yield July-10-consistent output regardless of machine TZ.
4. **Legacy doc**: a local-midnight-instant `Timestamp` parses without throw to a non-null UTC-flagged date (value = whatever UTC says — pin non-null + isUtc, NOT a specific day; decision 2).

Run: capture RED output verbatim (assertion 2's `isUtc == false` is the deterministic failure on every machine).

### Task 3: Write + read sites

**Files:**
- Modify: `lib/features/events/models/event_model.dart` — `toFirestoreMap` (:201-202): `Timestamp.fromDate(anchorCalendarDate(startDate!))`; `fromDoc`: replace `dateOrNull(...)` at BOTH :166 (startDate) AND :167 (endDate) with a local private `_calendarDateOrNull` (round-3 P3 — one converted and one not renders an inconsistent range), null-guarded explicitly (round-3 P2 — the malformed-input tests at `test/unit/event_model_test.dart:159,186,274-275` exercise the null path):

```dart
DateTime? _calendarDateOrNull(Object? raw) {
  final parsed = dateOrNull(raw);
  if (parsed == null) return null; // #532 total-parse: malformed → null, never throw
  // The read-side .toUtc() is LOAD-BEARING: it normalizes the stored instant
  // to UTC components (correct for anchored docs, accepted-shift for legacy).
  // It is NOT the forbidden capture-time conversion — do not "simplify" away.
  return anchorCalendarDate(parsed.toUtc());
}
```
- Modify: `lib/features/events/services/event_service.dart` — `updateEvent` (:290,:293): wrap both in `anchorCalendarDate(...)`.
- Modify: `lib/features/events/screens/create_event_screen.dart` (:238-255 — BOTH `_pickStartDate` AND `_pickEndDate`, round-1 P3): anchor at capture (`_startDate = anchorCalendarDate(picked)`).
- Modify: `lib/features/events/widgets/event_info_section.dart` (:67-84): anchor at capture AND DELETE the `.toUtc()` calls (:77,:79) — they shift components pre-anchor.

Note `_calendarDateOrNull` extracting from `parsed.toUtc()`: for new (noon-anchored) docs the UTC components equal the picked date by construction; `anchorCalendarDate` then reads those UTC components correctly because the input is UTC-flagged. **This read-side `.toUtc()` is LOAD-BEARING** — mark it with a one-line comment so it isn't "simplified" away (it is the safe stored-instant normalization, NOT the forbidden capture-time conversion; round-1 P3).

**Update the existing test this flips — INPUT AND assertion (round-1 P2, round-2 P2):** in `test/features/events/models/event_model_test.dart`, the fromDoc test's INPUT at `:95-96` is a LOCAL-midnight `Timestamp.fromDate(DateTime(2026,4,1))` — leaving it local-midnight makes the test machine-TZ-DEPENDENT under the accepted-shift read (RED on a GMT+4 machine, green on UTC CI). Change the INPUT to `Timestamp.fromDate(DateTime.utc(2026,4,1,12))` / `...(2026,4,5,12)` AND the assertions at `:111-112` to `DateTime.utc(2026,4,1,12)` / `DateTime.utc(2026,4,5,12)` + `isUtc` asserts. Same for any round-trip assertion pinning naive instants (:223-286 region). Exact anchored values — do not loosen to day-only matching.

Task 2 tests green. `flutter test test/features/events/ test/unit/`. **Commit** `fix(events): carry event dates as UTC-anchored calendar dates` (body `Refs #1098`).

### Task 3b: Calendar-day semantics at the instant-arithmetic consumers (round-1 P1/P2, round-2 P1)

**Files:**
- Modify: `lib/features/home/widgets/add_expense_target_sheet.dart` (round-2 correction: it lives under `home/widgets/`, NOT `ledger/`) — `_subtitleFor` has TWO raw-instant reads and BOTH convert (round-2 P1 — converting only the day-count line leaves an ongoing event rendering "in 1 day" until 16:00 local in UTC+4):
  - the ONGOING classifier (:84-88, `now.isAfter(start−1s) && now.isBefore(end+1d)`) → `calendarDayDiff(now, start) <= 0 && calendarDayDiff(now, end) >= 0` (inclusive calendar-day window);
  - the "Upcoming · in N days" line (:91) → `calendarDayDiff(now, start).clamp(1, 365)` — PRESERVE the existing `.clamp(1, 365)` (lower bound keeps a same-day edge from rendering "in 0 days"; upper cap keeps far-future events sane; round-2 P2/P3).
- Modify: `lib/features/home/providers/active_journeys_provider.dart` — `_isActive` (the WHOLE function, :88-108 — including the start-only branch at :102-104 `start.difference(now).abs() <= _upcomingWindow`, round-3 P2; the no-date `return true` needs no change) and `_priority` (:124-133): every START/END comparison moves to `calendarDayDiff` / component dates, keeping the fuzzy window sizes in calendar days. Ongoing = today within [start.date, end.date] **INCLUSIVE** — note (round-3 P3): `_priority`'s CURRENT check is exclusive (`isAfter(start) && isBefore(end)`), so this deliberately flips a single-day event from rank 1000 (recently-ended) to rank 0 (ongoing) — intended, consistent with `_isActive`, and better; do not "preserve" the exclusive bound. **Carve-out (round-2 P2): the `createdAt` fallback at `:133` STAYS instant-based** — a TRUE instant, not a calendar carrier.
- In `_subtitleFor`, also convert the branch-2 guard `start.isAfter(now)` (:90) to `calendarDayDiff(now, start) >= 1` so the whole method speaks calendar days (round-3 P3 — harmless raw-instant residual otherwise).

**Tests first (RED against the anchored carrier):** with an anchored `startDate` = tomorrow's calendar date and a real `DateTime.now()`, the sheet renders "in 1 day" (pre-fix: 2 whenever local time-of-day is before the noon-UTC instant's local rendering); journey-strip classification: an event whose anchored start/end span today is `ongoing` regardless of local hour. Construct dates RELATIVE to `DateTime.now()` (anchor `now`'s own calendar date) so assertions are machine-TZ-independent.

These three sites were already tz-fragile pre-#1098 (local-midnight instants vs reader-local now) — this task is a correctness fix riding the same invariant, not scope creep; it is REQUIRED for the anchor to land without rendering regressions.

**Commit** `fix(events): day-count and journey windows compare calendar days` (body `Refs #1098`).

### Task 4: Full verification + ship

- [ ] Full `flutter test`; `flutter analyze` clean; `bash tool/check_theme_purity.sh`.
- [ ] Grep sweep, report in PR: EVERY reader of `event.startDate|endDate` — the round-1-verified full set: `localized_dates` consumers (`event_details_card`, `event_info_section`, `recap_share_card`), `trip_receipt_format`/`trip_receipt_csv`/`trip_receipt_pdf`, `event_command_center`/`liveTripDay`, the `event_provider` sort comparator, `active_journeys_provider` (Task 3b), `add_expense_target_sheet` (Task 3b), `where_card.dart:23`, `group_settle_up_screen.dart:167`, `event_recap_provider`, `journey_ticket_card`, `group_detail_screen.dart:923`. Confirm none calls `.toLocal()` on the field and none does raw-instant day arithmetic outside the Task-3b fixes; cite each.
- [ ] PR: title `fix(events): event dates no longer shift across timezones (#1098)`; body: summary, `Closes #1098` in FINAL commit body, `Spec: docs/plans/2026-07-10-1098-event-calendar-dates.md`, Test plan, RED evidence, decisions (legacy-shift accepted; noon = defense-in-depth; `dateOrNull` untouched).
- [ ] `/automerge <PR>` — Gate-category (`**/models/**`); fresh review + refuter.

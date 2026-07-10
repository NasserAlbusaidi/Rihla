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

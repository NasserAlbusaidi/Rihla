import '../../../l10n/generated/app_localizations.dart';
import '../models/event_model.dart';

/// #789: "Day N of M" for a LIVE, multi-day event — `null` otherwise.
///
/// [currentDay] counts from 1 on [start]; [totalDays] is the inclusive span.
/// Comparison is date-only, anchored at UTC midnight so time-of-day and DST
/// transitions never shift the count. Returns `null` when either date is
/// missing, [now] falls outside `[start, end]`, or the event spans a single day
/// (a one-day "Day 1 of 1" badge carries no information).
({int currentDay, int totalDays})? liveTripDay(
  DateTime? start,
  DateTime? end,
  DateTime now,
) {
  if (start == null || end == null) return null;
  final s = DateTime.utc(start.year, start.month, start.day);
  final e = DateTime.utc(end.year, end.month, end.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  if (today.isBefore(s) || today.isAfter(e)) return null;
  final totalDays = e.difference(s).inDays + 1;
  if (totalDays < 2) return null;
  return (currentDay: today.difference(s).inDays + 1, totalDays: totalDays);
}

extension EventTypeDisplay on EventType {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    EventType.trip => l10n.eventTypeTripLabel,
    EventType.camping => l10n.eventTypeCampingLabel,
    EventType.travel => l10n.eventTypeTravelLabel,
    EventType.nightDayOut => l10n.eventTypeNightDayOutLabel,
    EventType.custom => l10n.eventTypeCustomLabel,
  };

  String localizedDescription(AppLocalizations l10n) => switch (this) {
    EventType.trip => l10n.eventTypeTripDescription,
    EventType.camping => l10n.eventTypeCampingDescription,
    EventType.travel => l10n.eventTypeTravelDescription,
    EventType.nightDayOut => l10n.eventTypeNightDayOutDescription,
    EventType.custom => l10n.eventTypeCustomDescription,
  };

  String localizedShortLabel(AppLocalizations l10n) => switch (this) {
    EventType.trip => l10n.eventTypeTripShort,
    EventType.camping => l10n.eventTypeCampingShort,
    EventType.travel => l10n.eventTypeTravelShort,
    EventType.nightDayOut => l10n.eventTypeNightDayOutShort,
    EventType.custom => l10n.eventTypeCustomShort,
  };
}

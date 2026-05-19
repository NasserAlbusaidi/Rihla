import '../../../l10n/generated/app_localizations.dart';
import '../models/event_model.dart';

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

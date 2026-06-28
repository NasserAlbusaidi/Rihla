import '../../../l10n/generated/app_localizations.dart';
import '../models/event_model.dart';

/// Per-event-type ledger copy (#689 Slice 3) — the recap noun and the empty
/// state speak the event's own language while the money math stays identical.
///
/// Sibling to `categoryOrderForType` (the per-type category ordering): the
/// event type is persisted on every event and now tunes copy + ordering, never
/// money rules. Trip and Travel share a noun (both are journeys), matching how
/// `categoryOrderForType` groups them.

/// The recap "total" label for [type] — same total, the event's own noun
/// ("Trip total" / "Camping total" / "Outing total" / "Event total"). Title
/// case; the ledger hero caption uppercases it for its mono styling (Arabic has
/// no case, so the uppercasing is English-only).
String eventTypeTotalLabel(EventType type, AppLocalizations l10n) =>
    switch (type) {
      EventType.camping => l10n.eventTotalLabelCamping,
      EventType.nightDayOut => l10n.eventTotalLabelOuting,
      EventType.custom => l10n.eventTotalLabelEvent,
      EventType.trip || EventType.travel => l10n.eventTripTotal,
    };

/// The ledger empty-state first-expense body for [type], with [currency]
/// interpolated — the empty page reframed in the event's language. Trip and
/// Travel reuse the original trip-worded copy.
String eventTypeFirstExpenseBody(
  EventType type,
  AppLocalizations l10n,
  String currency,
) => switch (type) {
  EventType.camping => l10n.ledgerEmptyFirstExpenseCamping(currency),
  EventType.nightDayOut => l10n.ledgerEmptyFirstExpenseOuting(currency),
  EventType.custom => l10n.ledgerEmptyFirstExpenseEvent(currency),
  EventType.trip ||
  EventType.travel => l10n.ledgerEmptyStateFirstExpenseBody(currency),
};

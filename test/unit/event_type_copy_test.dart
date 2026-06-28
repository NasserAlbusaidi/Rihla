import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/utils/event_type_copy.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #689 Slice 3 — the per-type recap noun + empty-state copy (the two boxes
/// PR #690 left as `Refs #689 — partial`). The event type already tunes the
/// category order (`categoryOrderForType`); these helpers make the recap label
/// and the ledger empty-state speak the event's own language.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations en;
  late AppLocalizations ar;
  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  group('eventTypeTotalLabel (per-type recap noun)', () {
    test('every event type yields a non-empty label in EN and AR', () {
      for (final type in EventType.values) {
        expect(eventTypeTotalLabel(type, en), isNotEmpty);
        expect(eventTypeTotalLabel(type, ar), isNotEmpty);
      }
    });

    test('trip and travel share the journey label (EN + AR)', () {
      expect(
        eventTypeTotalLabel(EventType.travel, en),
        eventTypeTotalLabel(EventType.trip, en),
      );
      expect(
        eventTypeTotalLabel(EventType.travel, ar),
        eventTypeTotalLabel(EventType.trip, ar),
      );
    });

    test('camping / outing / custom each differ from the trip label (EN)', () {
      final trip = eventTypeTotalLabel(EventType.trip, en);
      expect(eventTypeTotalLabel(EventType.camping, en), isNot(trip));
      expect(eventTypeTotalLabel(EventType.nightDayOut, en), isNot(trip));
      expect(eventTypeTotalLabel(EventType.custom, en), isNot(trip));
    });

    test('the trip label reuses the existing eventTripTotal key', () {
      expect(eventTypeTotalLabel(EventType.trip, en), en.eventTripTotal);
      expect(eventTypeTotalLabel(EventType.trip, ar), ar.eventTripTotal);
    });
  });

  group('eventTypeFirstExpenseBody (per-type empty-state copy)', () {
    test('every event type interpolates the currency (EN + AR)', () {
      for (final type in EventType.values) {
        expect(eventTypeFirstExpenseBody(type, en, 'OMR'), contains('OMR'));
        expect(eventTypeFirstExpenseBody(type, ar, 'OMR'), contains('OMR'));
      }
    });

    test('camping / outing / custom each differ from the trip body (EN)', () {
      final trip = eventTypeFirstExpenseBody(EventType.trip, en, 'OMR');
      expect(eventTypeFirstExpenseBody(EventType.camping, en, 'OMR'), isNot(trip));
      expect(
        eventTypeFirstExpenseBody(EventType.nightDayOut, en, 'OMR'),
        isNot(trip),
      );
      expect(eventTypeFirstExpenseBody(EventType.custom, en, 'OMR'), isNot(trip));
    });

    test('the trip body reuses the existing ledgerEmptyStateFirstExpenseBody key', () {
      expect(
        eventTypeFirstExpenseBody(EventType.trip, en, 'OMR'),
        en.ledgerEmptyStateFirstExpenseBody('OMR'),
      );
    });
  });
}

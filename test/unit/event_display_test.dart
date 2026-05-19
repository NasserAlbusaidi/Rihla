import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/utils/event_display.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('EventTypeDisplay', () {
    test('returns English labels and descriptions for all event types', () {
      final l10n = AppLocalizationsEn();

      expect(EventType.trip.localizedLabel(l10n), 'Trip');
      expect(EventType.camping.localizedLabel(l10n), 'Camping');
      expect(EventType.travel.localizedLabel(l10n), 'Travel');
      expect(EventType.nightDayOut.localizedLabel(l10n), 'Night/Day Out');
      expect(EventType.custom.localizedLabel(l10n), 'Custom');

      for (final type in EventType.values) {
        expect(type.localizedDescription(l10n), isNotEmpty);
        expect(type.localizedShortLabel(l10n), isNotEmpty);
      }
    });

    test('returns Arabic labels for all event types', () {
      final l10n = AppLocalizationsAr();

      expect(EventType.trip.localizedLabel(l10n), 'رحلة');
      expect(EventType.camping.localizedLabel(l10n), 'تخييم');
      expect(EventType.travel.localizedLabel(l10n), 'سفر');
      expect(EventType.nightDayOut.localizedLabel(l10n), 'خروج ليلي/نهاري');
      expect(EventType.custom.localizedLabel(l10n), 'مخصص');

      for (final type in EventType.values) {
        expect(type.localizedDescription(l10n), isNotEmpty);
        expect(type.localizedShortLabel(l10n), isNotEmpty);
      }
    });
  });
}

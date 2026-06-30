import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/settle_notify.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('settleNotifyMessage', () {
    test('event scope names the event AND the group', () {
      final msg = settleNotifyMessage(
        l10n: l10n,
        recipientName: 'Mariam',
        amountDisplay: 'OMR 18.500',
        eventName: 'Beach House',
        groupName: 'Summer Trip',
      );

      expect(
        msg,
        "Hey Mariam, I've sent you OMR 18.500 for Beach House in Summer Trip.",
      );
    });

    test('group scope (null event) names only the group, never an event', () {
      final msg = settleNotifyMessage(
        l10n: l10n,
        recipientName: 'Mariam',
        amountDisplay: 'OMR 18.500',
        eventName: null,
        groupName: 'Summer Trip',
      );

      expect(msg, "Hey Mariam, I've sent you OMR 18.500 for Summer Trip.");
      expect(msg, isNot(contains('in '))); // no "{event} in {group}" tail
    });

    test('empty event name falls back to group scope', () {
      final msg = settleNotifyMessage(
        l10n: l10n,
        recipientName: 'Sara',
        amountDisplay: 'USD 6.25',
        eventName: '',
        groupName: 'Road Trip',
      );

      expect(msg, "Hey Sara, I've sent you USD 6.25 for Road Trip.");
    });

    test('amount string is placed verbatim (JPY×1, no decimals)', () {
      final msg = settleNotifyMessage(
        l10n: l10n,
        recipientName: 'Yuki',
        amountDisplay: 'JPY 1,200',
        eventName: 'Dinner',
        groupName: 'Tokyo',
      );

      expect(msg, contains('JPY 1,200'));
    });
  });
}

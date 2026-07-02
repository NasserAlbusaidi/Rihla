import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/activity/models/activity_log_model.dart';
import 'package:safar/features/activity/utils/activity_display.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

ActivityLog _eventLog({
  required String category,
  required String eventType,
  String logText = 'legacy text',
}) => ActivityLog(
  id: 'event-log',
  tripId: 'event-1',
  category: category,
  eventType: eventType,
  logText: logText,
  createdAt: DateTime(2026, 1, 1),
);

GroupActivityLog _groupLog({
  required String type,
  String description = 'legacy group text',
  Map<String, dynamic> metadata = const {},
}) => GroupActivityLog(
  id: 'group-log',
  type: type,
  actorId: 'uid-1',
  actorName: 'Alice',
  description: description,
  metadata: metadata,
  timestamp: DateTime(2026, 1, 1),
);

void main() {
  group('activity display helpers', () {
    test('localizes known event activity types in English and Arabic', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      final log = _eventLog(category: 'MONEY', eventType: 'CREATE');

      expect(localizedEventActivityText(en, log), 'added a money entry');
      expect(localizedEventActivityText(ar, log), 'أضاف قيدًا ماليًا');
    });

    test('localizes every known event activity branch', () {
      final en = AppLocalizationsEn();

      final cases = <({String category, String eventType, String expected})>[
        (
          category: 'money',
          eventType: 'update',
          expected: en.activityEventMoneyUpdated,
        ),
        (
          category: 'MONEY',
          eventType: 'DELETE',
          expected: en.activityEventMoneyDeleted,
        ),
        (
          category: 'GEAR',
          eventType: 'CREATE',
          expected: en.activityEventGearCreated,
        ),
        (
          category: 'GEAR',
          eventType: 'UPDATE',
          expected: en.activityEventGearUpdated,
        ),
        (
          category: 'GEAR',
          eventType: 'DELETE',
          expected: en.activityEventGearDeleted,
        ),
        (
          category: 'DOCS',
          eventType: 'CREATE',
          expected: en.activityEventDocsCreated,
        ),
        (
          category: 'DOCS',
          eventType: 'UPDATE',
          expected: en.activityEventDocsUpdated,
        ),
        (
          category: 'DOCS',
          eventType: 'DELETE',
          expected: en.activityEventDocsDeleted,
        ),
      ];

      for (final testCase in cases) {
        expect(
          localizedEventActivityText(
            en,
            _eventLog(
              category: testCase.category,
              eventType: testCase.eventType,
            ),
          ),
          testCase.expected,
        );
      }
    });

    test('preserves legacy event fallback text for unknown rows', () {
      final en = AppLocalizationsEn();
      final log = _eventLog(
        category: 'LEGACY',
        eventType: 'ODD',
        logText: 'custom persisted activity',
      );

      expect(localizedEventActivityText(en, log), 'custom persisted activity');
    });

    test('localizes known group activity types with metadata', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      final log = _groupLog(
        type: 'event_created',
        metadata: const {'eventName': 'Beach Trip'},
      );

      expect(localizedGroupActivityText(en, log), 'created Beach Trip');
      expect(localizedGroupActivityText(ar, log), 'أنشأ Beach Trip');
    });

    test('localizes group activity generic and settlement branches', () {
      final en = AppLocalizationsEn();

      expect(
        localizedGroupActivityText(en, _groupLog(type: 'group_settlement')),
        en.activityGroupSettlementDescription,
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'event_created')),
        en.activityGroupEventCreatedGeneric,
      );
      expect(
        localizedGroupActivityText(
          en,
          _groupLog(
            type: 'event_deleted',
            metadata: const {'eventName': 'Old Plan'},
          ),
        ),
        en.activityGroupEventDeleted('Old Plan'),
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'event_deleted')),
        en.activityGroupEventDeletedGeneric,
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'member_joined')),
        en.activityGroupMemberJoined,
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'member_left')),
        en.activityGroupMemberLeft,
      );
      expect(
        localizedGroupActivityText(
          en,
          _groupLog(
            type: 'member_left',
            description: 'legacy removal text',
            metadata: const {'memberAction': 'removed'},
          ),
        ),
        'legacy removal text',
      );
    });

    test('localizes member removal without misattributing the actor', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      final log = _groupLog(
        type: 'member_left',
        description: 'Bob was removed from the group',
        metadata: const {'memberAction': 'removed', 'memberName': 'Bob'},
      );

      expect(localizedGroupActivityText(en, log), 'removed Bob from the group');
      expect(localizedGroupActivityText(ar, log), 'أزال Bob من المجموعة');
    });

    test('preserves legacy group fallback text for unknown rows', () {
      final ar = AppLocalizationsAr();
      final log = _groupLog(
        type: 'legacy_type',
        description: 'legacy persisted group text',
      );

      expect(
        localizedGroupActivityText(ar, log),
        'legacy persisted group text',
      );
    });

    // #808 PR1 — the server fans expense_* entries into the group feed with a
    // readable server-written description; until PR2 adds localized rendering
    // for these types, the description fallback IS the interim contract. Pin
    // it so a PR2-era refactor can't silently blank pre-PR2 entries.
    test('expense_* fan-in types render via the description fallback (#808 PR1)', () {
      final en = AppLocalizationsEn();
      for (final type in [
        'expense_added',
        'expense_edited',
        'expense_deleted',
      ]) {
        final log = _groupLog(
          type: type,
          description: 'added Dinner (10.500 OMR)',
          metadata: const {
            'expenseId': 'exp1',
            'eventId': 'e1',
            'eventName': 'Muscat trip',
            'amountFils': 10500,
            'currency': 'OMR',
          },
        );
        expect(
          localizedGroupActivityText(en, log),
          'added Dinner (10.500 OMR)',
        );
      }
    });
  });

  group('activityAmountCurrency (#382 PR-4)', () {
    test('prefers a supported metadata currency over the fallback', () {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: const {'amount': '7.75', 'currency': 'USD'},
      );
      expect(activityAmountCurrency(log, 'OMR'), 'USD');
    });

    test('falls back when the key is absent (legacy rows)', () {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: const {'amount': '7.750'},
      );
      expect(activityAmountCurrency(log, 'OMR'), 'OMR');
    });

    test('falls back on unsupported or non-string values '
        '(client-forgeable map)', () {
      for (final junk in [Object(), 'NOPE', '', 3, 'omr']) {
        final log = _groupLog(
          type: 'group_settlement',
          metadata: {'amount': '1', 'currency': junk},
        );
        expect(activityAmountCurrency(log, 'AED'), 'AED', reason: '$junk');
      }
    });
  });
}

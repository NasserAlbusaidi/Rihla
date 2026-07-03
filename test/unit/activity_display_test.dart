import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/services/money_serializer.dart';
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

({GroupActivityLog log, String groupName, String groupId, String currency})
_entry(GroupActivityLog log, {String groupName = 'Trip A', String currency = 'OMR'}) =>
    (log: log, groupName: groupName, groupId: 'g1', currency: currency);

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

    // #808 PR2: the server fan-in (expenseAuditLogger) writes expense_added/
    // expense_edited/expense_deleted with an English verb-phrase description and
    // metadata.eventName. The client localizes by type (D-PR2-1 — GENERIC, no
    // expense label; the label is not in metadata). eventName present → "in
    // {eventName}"; empty/missing → the Generic variant.
    test('localizes expense_* group activity types with an event name', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();

      final added = _groupLog(
        type: 'expense_added',
        description: 'added Dinner (10.500 OMR)',
        metadata: const {'eventName': 'Beach Trip'},
      );
      final edited = _groupLog(
        type: 'expense_edited',
        metadata: const {'eventName': 'Beach Trip'},
      );
      final deleted = _groupLog(
        type: 'expense_deleted',
        metadata: const {'eventName': 'Beach Trip'},
      );

      expect(
        localizedGroupActivityText(en, added),
        en.activityGroupExpenseAdded('Beach Trip'),
      );
      expect(
        localizedGroupActivityText(en, edited),
        en.activityGroupExpenseEdited('Beach Trip'),
      );
      expect(
        localizedGroupActivityText(en, deleted),
        en.activityGroupExpenseDeleted('Beach Trip'),
      );
      expect(
        localizedGroupActivityText(ar, added),
        ar.activityGroupExpenseAdded('Beach Trip'),
      );
    });

    test('localizes expense_* generic variants when eventName is empty/absent',
        () {
      final en = AppLocalizationsEn();

      // metadata.eventName may be '' (the fan-in writes '' when the event has
      // no name) or absent entirely — both take the Generic variant.
      expect(
        localizedGroupActivityText(
          en,
          _groupLog(type: 'expense_added', metadata: const {'eventName': ''}),
        ),
        en.activityGroupExpenseAddedGeneric,
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'expense_edited')),
        en.activityGroupExpenseEditedGeneric,
      );
      expect(
        localizedGroupActivityText(en, _groupLog(type: 'expense_deleted')),
        en.activityGroupExpenseDeletedGeneric,
      );
    });
  });

  group('activityAmount (#808 PR2)', () {
    test('fils + supported currency → fromSubunits, never the legacy scale', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 10500, 'currency': 'OMR'},
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt, isNotNull);
      // 10500 fils = OMR 10.500 — NOT 10,500.
      expect(amt!.value, MoneySerializer.fromSubunits(10500, 'OMR'));
      expect(amt.value, Decimal.parse('10.5'));
      expect(amt.currency, 'OMR');
    });

    test('fils on a 2dp currency converts by that currency scale', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 999, 'currency': 'USD'},
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('9.99'));
      expect(amt.currency, 'USD');
    });

    test('fils as a Firestore-deserialized DOUBLE still converts '
        '(expense_audit_diff.dart:37 is-num precedent)', () {
      // Firestore number deserialization can yield Dart double for the SAME
      // amountFils field — the shipped sibling reader (ExpenseAuditSnap.tryParse)
      // guards `is num` + `.toInt()`, and its test seeds 8000.0.
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 8000.0, 'currency': 'OMR'},
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt, isNotNull);
      expect(amt!.value, Decimal.parse('8'));
      expect(amt.currency, 'OMR');
    });

    test('non-whole double fils truncates like the sibling reader (.toInt())',
        () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 8000.7, 'currency': 'OMR'},
      );
      // 8000.7.toInt() == 8000 fils == OMR 8.000 — mirrors ExpenseAuditSnap.
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('8'));
      expect(amt.currency, 'OMR');
    });

    test('double fils with missing/unsupported currency still → null', () {
      expect(
        activityAmount(
          _groupLog(
            type: 'expense_added',
            metadata: const {'amountFils': 8000.0},
          ),
          'OMR',
        ),
        isNull,
      );
      expect(
        activityAmount(
          _groupLog(
            type: 'expense_added',
            metadata: const {'amountFils': 8000.0, 'currency': 'XXX'},
          ),
          'OMR',
        ),
        isNull,
      );
    });

    test('double fils wins over a stray legacy amount (precedence unchanged)',
        () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {
          'amountFils': 8000.0,
          'currency': 'OMR',
          'amount': '999',
        },
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('8')); // fils, not '999'
    });

    test('non-finite fils never throws — NaN/±infinity → null '
        '(group_settlement metadata is client-forgeable; .toInt() throws)', () {
      // group_settlement activity docs are CLIENT-writable and firestore.rules
      // guards metadata only as `is map`, so any member can forge these.
      for (final junk in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final log = _groupLog(
          type: 'group_settlement',
          metadata: {'amountFils': junk, 'currency': 'OMR'},
        );
        expect(activityAmount(log, 'OMR'), isNull, reason: '$junk');
      }
    });

    test('non-finite fils + legacy amount → legacy path wins '
        '(exact pre-fix fall-through semantics)', () {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: const {
          'amountFils': double.nan,
          'currency': 'OMR',
          'amount': '9.500',
        },
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt, isNotNull);
      expect(amt!.value, Decimal.parse('9.5'));
      expect(amt.currency, 'OMR');
    });

    test('fils present but currency MISSING → null (never guess the scale)', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 10500},
      );
      expect(activityAmount(log, 'OMR'), isNull);
    });

    test('fils present but currency UNSUPPORTED → null', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 10500, 'currency': 'XXX'},
      );
      expect(activityAmount(log, 'OMR'), isNull);
    });

    test('fils present with a stray legacy amount still → null on bad currency '
        '(amountFils never flows through the decimal-units path)', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {'amountFils': 10500, 'amount': '5'},
      );
      expect(activityAmount(log, 'OMR'), isNull);
    });

    test('legacy string amount → parsed, currency from metadata/fallback', () {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: const {'amount': '12.5'},
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('12.5'));
      expect(amt.currency, 'OMR');

      final stamped = _groupLog(
        type: 'group_settlement',
        metadata: const {'amount': '20.25', 'currency': 'USD'},
      );
      final amt2 = activityAmount(stamped, 'OMR');
      expect(amt2!.value, Decimal.parse('20.25'));
      expect(amt2.currency, 'USD');
    });

    test('legacy num amount → parsed', () {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: const {'amount': 7.75},
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('7.75'));
      expect(amt.currency, 'OMR');
    });

    test('both keys present → fils wins (currency from metadata)', () {
      final log = _groupLog(
        type: 'expense_added',
        metadata: const {
          'amountFils': 10500,
          'currency': 'OMR',
          'amount': '999',
        },
      );
      final amt = activityAmount(log, 'OMR');
      expect(amt!.value, Decimal.parse('10.5')); // fils, not '999'
      expect(amt.currency, 'OMR');
    });

    test('neither key → null', () {
      final log = _groupLog(type: 'member_joined');
      expect(activityAmount(log, 'OMR'), isNull);
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

  group('activityMatchesQuery (#808 PR3)', () {
    final en = AppLocalizationsEn();
    final ar = AppLocalizationsAr();

    test('an empty or whitespace-only query matches every entry', () {
      final entry = _entry(_groupLog(type: 'member_joined'));
      expect(activityMatchesQuery(entry, '', en), isTrue);
      expect(activityMatchesQuery(entry, '   ', en), isTrue);
    });

    test('matches the actor name, case-insensitively', () {
      final entry = _entry(_groupLog(type: 'member_joined')); // actorName 'Alice'
      expect(activityMatchesQuery(entry, 'ali', en), isTrue);
      expect(activityMatchesQuery(entry, 'ALICE', en), isTrue);
      expect(activityMatchesQuery(entry, 'bob', en), isFalse);
    });

    test('matches the group name', () {
      final entry = _entry(
        _groupLog(type: 'member_joined'),
        groupName: 'Beach Squad',
      );
      expect(activityMatchesQuery(entry, 'squad', en), isTrue);
    });

    test('matches metadata.eventName', () {
      final entry = _entry(
        _groupLog(
          type: 'expense_added',
          metadata: const {'eventName': 'Snorkel Day'},
        ),
      );
      expect(activityMatchesQuery(entry, 'snorkel', en), isTrue);
    });

    test('matches the localized display text (English)', () {
      final entry = _entry(_groupLog(type: 'group_settlement'));
      expect(activityMatchesQuery(entry, 'settlement', en), isTrue);
    });

    test('matches the localized display text (Arabic)', () {
      final joined = _entry(_groupLog(type: 'member_joined'));
      expect(activityMatchesQuery(joined, 'المجموعة', ar), isTrue);
      final settle = _entry(_groupLog(type: 'group_settlement'));
      expect(activityMatchesQuery(settle, 'تسوية', ar), isTrue);
    });

    test('matches the raw description even when the localized text is generic '
        '(D-PR2-1: the fan-in label lives only in the description)', () {
      // eventName present → localized = "added an expense in Beach Trip"; the
      // "Dinner" label survives only in the English fan-in description.
      final entry = _entry(
        _groupLog(
          type: 'expense_added',
          description: 'added Dinner (10.500 OMR)',
          metadata: const {'eventName': 'Beach Trip'},
        ),
      );
      expect(
        localizedGroupActivityText(en, entry.log).contains('Dinner'),
        isFalse,
      );
      expect(activityMatchesQuery(entry, 'dinner', en), isTrue);
    });

    test('matches the formatted amount string when an amount is shown', () {
      final entry = _entry(
        _groupLog(
          type: 'expense_added',
          description: 'added an expense', // no digits of its own
          metadata: const {
            'amountFils': 10500,
            'currency': 'OMR',
            'eventName': '',
          },
        ),
      );
      // Displayed as "OMR 10.500".
      expect(activityMatchesQuery(entry, '10.5', en), isTrue);
      expect(activityMatchesQuery(entry, '10.500', en), isTrue);
      expect(activityMatchesQuery(entry, 'omr', en), isTrue);
    });

    test('does not match an amount that is not shown (fils without a trusted '
        'currency → activityAmount null)', () {
      final entry = _entry(
        _groupLog(
          type: 'expense_added',
          description: 'added an expense', // no digits
          metadata: const {'amountFils': 10500}, // no currency → null amount
        ),
      );
      expect(activityAmount(entry.log, entry.currency), isNull);
      expect(activityMatchesQuery(entry, '10500', en), isFalse);
    });

    test('no crash and no match on an empty-metadata entry with a miss', () {
      final entry = _entry(_groupLog(type: 'member_joined'));
      expect(activityMatchesQuery(entry, 'zzzzz', en), isFalse);
    });
  });
}

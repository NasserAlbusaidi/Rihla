import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _groupId = 'grp-1217';

/// #1217: 26 ASCII characters + one astral emoji (a 2-UTF-16-unit surrogate
/// pair, "🎉" U+1F389) + 3 more ASCII characters = 31 UTF-16 CODE UNITS but
/// only 30 GRAPHEMES (visible characters). `_buildEventLabel`'s old
/// `rawName.length > 30` check counted UTF-16 units, so this legal 30-visible
/// -character name tripped the truncation and `substring(0, 27)` cut BETWEEN
/// the emoji's high and low surrogate (index 26/27), leaving the label
/// ending in an unpaired high surrogate (renders as U+FFFD).
const _asciiPrefix = 'AAAAAAAAAAAAAAAAAAAAAAAAAA'; // 26 'A's
const _emoji = '🎉'; // U+1F389, 2 UTF-16 code units, 1 grapheme
const _asciiSuffix = 'BCD'; // 3 more code units/graphemes
const _eventName =
    '$_asciiPrefix$_emoji$_asciiSuffix'; // 31 units / 30 graphemes

final _event = Event(
  id: 'evt-emoji',
  name: _eventName,
  type: EventType.custom,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 7, 12),
  createdAt: DateTime(2026, 7, 12),
);

Group _group() => Group(
  id: _groupId,
  name: 'Emoji Crew',
  inviteCode: 'EMO123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

UserBalance _bal(String id, String name, String net) => UserBalance(
  participantId: id,
  displayName: name,
  totalPaid: Decimal.zero,
  totalOwed: Decimal.zero,
  netBalance: Decimal.parse(net),
);

/// Bob owes Alice 5.000 OMR, all earned in the single emoji-named event.
GroupBalances _balances() => (
  balances: <String, List<UserBalance>>{
    'OMR': [
      _bal('uid-alice', 'Alice', '5.000'),
      _bal('uid-bob', 'Bob', '-5.000'),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('5.000')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-alice': {
      'evt-emoji': {'OMR': Decimal.parse('5.000')},
    },
    'uid-bob': {
      'evt-emoji': {'OMR': Decimal.parse('-5.000')},
    },
  },
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

Widget _wrap() {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
      groupBalancesProvider(
        _groupId,
      ).overrideWith((_) => AsyncValue.data(_balances())),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value([_event])),
      currentUserIdProvider.overrideWithValue('uid-bob'),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupSettleUpScreen(groupId: _groupId),
      ),
    ),
  );
}

void main() {
  testWidgets(
    '#1217: a 30-grapheme (31 UTF-16 unit) event name carrying an astral '
    'emoji renders FULLY INTACT — grapheme-aware truncation must not split '
    "the emoji's surrogate pair, and 30 visible characters is at the "
    '"roughly 30 visible, ellipsis when longer" threshold so no truncation '
    'is expected at all',
    (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      // The full name (including the intact emoji, no ellipsis) must render
      // verbatim. A UTF-16-unit-blind truncation would instead cut the
      // surrogate pair, producing a string that does NOT match this exact
      // text (it would carry a lone surrogate + "..." instead).
      expect(find.textContaining(_eventName), findsOneWidget);
      expect(find.textContaining('$_eventName...'), findsNothing);
    },
  );

  testWidgets(
    '#1217: a name long enough to STILL require truncation after the fix '
    '(37 graphemes) truncates cleanly at the grapheme boundary right after '
    'the emoji — never a lone surrogate, never a UTF-16 crash — proving the '
    'fix is grapheme-boundary-aware, not merely "never truncate names with '
    'an emoji"',
    (tester) async {
      // Same 26-ASCII-then-emoji prefix as the no-truncation case above, but
      // with 10 trailing chars pushing the grapheme count to 37 (> 30) so
      // truncation is REQUIRED even under grapheme counting. The old
      // UTF-16-unit cut (`substring(0, 27)`) lands mid-surrogate-pair here
      // too (26 ASCII units + the emoji's high surrogate = unit 27) —
      // `_NativeParagraphBuilder.addText` throws `ArgumentError: string is
      // not well-formed UTF-16` before the fix. The grapheme-safe cut takes
      // the first 27 graphemes (26 ASCII + the whole emoji) intact.
      final longName = '$_asciiPrefix$_emoji${'C' * 10}'; // 37 graphemes
      final longEvent = Event(
        id: 'evt-emoji-long',
        name: longName,
        type: EventType.custom,
        groupId: _groupId,
        createdBy: 'uid-alice',
        participantIds: const ['uid-alice', 'uid-bob'],
        participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
        modules: const EventModules(),
        startDate: DateTime(2026, 7, 12),
        createdAt: DateTime(2026, 7, 12),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupDetailProvider(
              _groupId,
            ).overrideWith((_) => Stream.value(_group())),
            groupBalancesProvider(_groupId).overrideWith(
              (_) => AsyncValue.data((
                balances: <String, List<UserBalance>>{
                  'OMR': [
                    _bal('uid-alice', 'Alice', '5.000'),
                    _bal('uid-bob', 'Bob', '-5.000'),
                  ],
                },
                totalSpent: <String, Decimal>{'OMR': Decimal.parse('5.000')},
                eventCount: 1,
                perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
                  'uid-alice': {
                    'evt-emoji-long': {'OMR': Decimal.parse('5.000')},
                  },
                  'uid-bob': {
                    'evt-emoji-long': {'OMR': Decimal.parse('-5.000')},
                  },
                },
                memberNames: <String, String>{
                  'uid-alice': 'Alice',
                  'uid-bob': 'Bob',
                },
                memberRawNames: <String, String>{
                  'uid-alice': 'Alice',
                  'uid-bob': 'Bob',
                },
              )),
            ),
            groupSettlementsProvider(
              _groupId,
            ).overrideWith((_) => Stream.value(const <Settlement>[])),
            groupEventsProvider(
              _groupId,
            ).overrideWith((_) => Stream.value([longEvent])),
            currentUserIdProvider.overrideWithValue('uid-bob'),
          ],
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const GroupSettleUpScreen(groupId: _groupId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      // The grapheme-safe cut keeps the WHOLE emoji (as the 27th grapheme)
      // and appends "..." right after it — the name portion is exactly the
      // 26-ASCII-plus-emoji prefix, never a partial/corrupted emoji.
      // #1216b: the event name is FSI/PDI-isolated, so the label starts with
      // the FSI (U+2068) then the grapheme-safe truncated name.
      final labelFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').startsWith('\u{2068}$_asciiPrefix$_emoji'),
      );
      expect(labelFinder, findsOneWidget);
      final labelText = tester.widget<Text>(labelFinder).data!;
      expect(labelText, startsWith('\u{2068}$_asciiPrefix$_emoji...'));
      // Must NEVER contain the Unicode replacement character (U+FFFD) that a
      // split surrogate pair renders as.
      expect(labelText.contains('�'), isFalse);
      // Every UTF-16 code unit pairs correctly (no lone surrogate anywhere).
      for (var i = 0; i < labelText.length; i++) {
        final unit = labelText.codeUnitAt(i);
        final isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
        final isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
        if (isHighSurrogate) {
          expect(
            i + 1 < labelText.length &&
                labelText.codeUnitAt(i + 1) >= 0xDC00 &&
                labelText.codeUnitAt(i + 1) <= 0xDFFF,
            isTrue,
            reason: 'unpaired high surrogate at index $i in "$labelText"',
          );
        } else if (isLowSurrogate) {
          expect(
            i > 0 &&
                labelText.codeUnitAt(i - 1) >= 0xD800 &&
                labelText.codeUnitAt(i - 1) <= 0xDBFF,
            isTrue,
            reason: 'unpaired low surrogate at index $i in "$labelText"',
          );
        }
      }
    },
  );
}

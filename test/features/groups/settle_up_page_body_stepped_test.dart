import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TDD RED — #382 PR-5 Task 10: stepped-settle affordance (D2).
///
/// The repo's first 2-bucket page-body fixture. A counterparty pair that owes
/// across ≥2 currency buckets must surface ONE stepped card that, when tapped,
/// emits the per-bucket steps GCC-first via [onRecordStepped]. Single-bucket
/// pairs and pure third-party pairs surface no card; a null [onRecordStepped]
/// suppresses all cards.
Widget _host(Widget body, {required SharedPreferences prefs}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: body),
      ),
    ),
  );
}

/// Two buckets: me↔X owes in BOTH (USD + OMR), me↔Y owes only in OMR.
/// Buckets are pre-sorted GCC-first by the caller, so OMR precedes USD.
List<SettleBucket> _twoBucketFixture() {
  return [
    (
      currency: 'OMR',
      optimalSettlements: [
        {
          'fromUserId': 'me',
          'toUserId': 'uid-x',
          'fromUserName': 'Me',
          'toUserName': 'Xavier',
          'amount': Decimal.parse('1.400'),
        },
        {
          'fromUserId': 'me',
          'toUserId': 'uid-y',
          'fromUserName': 'Me',
          'toUserName': 'Yara',
          'amount': Decimal.parse('2.000'),
        },
      ],
      balances: [
        UserBalance(
          participantId: 'uid-x',
          displayName: 'Xavier',
          totalPaid: Decimal.parse('1.400'),
          totalOwed: Decimal.zero,
          netBalance: Decimal.parse('1.400'),
        ),
        UserBalance(
          participantId: 'uid-y',
          displayName: 'Yara',
          totalPaid: Decimal.parse('2.000'),
          totalOwed: Decimal.zero,
          netBalance: Decimal.parse('2.000'),
        ),
      ],
    ),
    (
      currency: 'USD',
      optimalSettlements: [
        {
          'fromUserId': 'me',
          'toUserId': 'uid-x',
          'fromUserName': 'Me',
          'toUserName': 'Xavier',
          'amount': Decimal.parse('41.00'),
        },
      ],
      balances: [
        UserBalance(
          participantId: 'uid-x',
          displayName: 'Xavier',
          totalPaid: Decimal.parse('41.00'),
          totalOwed: Decimal.zero,
          netBalance: Decimal.parse('41.00'),
        ),
      ],
    ),
  ];
}

const _rawNames = {
  'me': 'Me',
  'uid-x': 'Xavier',
  'uid-y': 'Yara',
};

void main() {
  group('steppedSettlePairs (pure)', () {
    test('groups a multi-bucket counterparty into GCC-first steps', () {
      final pairs = steppedSettlePairs(
        buckets: _twoBucketFixture(),
        currentUid: 'me',
        rawNames: _rawNames,
      );

      expect(pairs, hasLength(1));
      final pair = pairs.single;
      expect(pair.otherUid, 'uid-x');
      expect(pair.otherName, 'Xavier');
      expect(pair.steps, hasLength(2));
      // GCC-first: OMR step precedes USD step.
      expect(pair.steps[0].currency, 'OMR');
      expect(pair.steps[0].suggestedAmount, Decimal.parse('1.400'));
      expect(pair.steps[0].toUserId, 'uid-x');
      expect(pair.steps[0].fromUserId, 'me');
      expect(pair.steps[1].currency, 'USD');
      expect(pair.steps[1].suggestedAmount, Decimal.parse('41.00'));
    });

    test('single-bucket counterparty is excluded (< 2 buckets)', () {
      final pairs = steppedSettlePairs(
        buckets: _twoBucketFixture(),
        currentUid: 'me',
        rawNames: _rawNames,
      );
      expect(pairs.any((p) => p.otherUid == 'uid-y'), isFalse);
    });

    test('pure third-party pair (no me) yields no group', () {
      final pairs = steppedSettlePairs(
        buckets: [
          (
            currency: 'OMR',
            optimalSettlements: [
              {
                'fromUserId': 'uid-a',
                'toUserId': 'uid-b',
                'fromUserName': 'A',
                'toUserName': 'B',
                'amount': Decimal.parse('5.000'),
              },
            ],
            balances: const <UserBalance>[],
          ),
          (
            currency: 'USD',
            optimalSettlements: [
              {
                'fromUserId': 'uid-a',
                'toUserId': 'uid-b',
                'fromUserName': 'A',
                'toUserName': 'B',
                'amount': Decimal.parse('7.00'),
              },
            ],
            balances: const <UserBalance>[],
          ),
        ],
        currentUid: 'me',
        rawNames: const {'uid-a': 'A', 'uid-b': 'B'},
      );
      expect(pairs, isEmpty);
    });

    test('null currentUid yields no groups', () {
      final pairs = steppedSettlePairs(
        buckets: _twoBucketFixture(),
        currentUid: null,
        rawNames: _rawNames,
      );
      expect(pairs, isEmpty);
    });

    test('rawName falls back to stripped display name when absent', () {
      final pairs = steppedSettlePairs(
        buckets: _twoBucketFixture(),
        currentUid: 'me',
        rawNames: const {'me': 'Me'}, // uid-x/uid-y absent
      );
      final pair = pairs.single;
      expect(pair.steps[0].toRawName, 'Xavier');
      expect(pair.steps[0].fromRawName, 'Me');
    });
  });

  group('SettleUpPageBody stepped card', () {
    testWidgets('renders exactly one stepped card and emits GCC-first steps', (
      tester,
    ) async {
      List<SettleStepRequest>? captured;
      final tileKeys = <int, GlobalKey>{};
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        _host(
          SettleUpPageBody(
            scope: SettleScope.group,
            subjectName: 'Test Crew',
            buckets: _twoBucketFixture(),
            rawNames: _rawNames,
            settlementsAsync: const AsyncValue.data(<Settlement>[]),
            currentUid: 'me',
            tileKeys: tileKeys,
            onRecord: ({
              required settlement,
              required fromRawName,
              required toRawName,
              required fromUserId,
              required toUserId,
              required suggestedAmount,
              required String currency,
            }) {},
            onRecordStepped: (steps) => captured = steps,
          ),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('settle-stepped-uid-x'));
      expect(card, findsOneWidget);
      expect(find.byKey(const ValueKey('settle-stepped-uid-y')), findsNothing);

      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.map((s) => s.currency).toList(), ['OMR', 'USD']);
      expect(captured![0].suggestedAmount, Decimal.parse('1.400'));
      expect(captured![1].suggestedAmount, Decimal.parse('41.00'));
    });

    testWidgets('no stepped cards when onRecordStepped is null', (tester) async {
      final tileKeys = <int, GlobalKey>{};
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        _host(
          SettleUpPageBody(
            scope: SettleScope.group,
            subjectName: 'Test Crew',
            buckets: _twoBucketFixture(),
            rawNames: _rawNames,
            settlementsAsync: const AsyncValue.data(<Settlement>[]),
            currentUid: 'me',
            tileKeys: tileKeys,
            onRecord: ({
              required settlement,
              required fromRawName,
              required toRawName,
              required fromUserId,
              required toUserId,
              required suggestedAmount,
              required String currency,
            }) {},
          ),
          prefs: prefs,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settle-stepped-uid-x')), findsNothing);
    });
  });
}

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/features/ledger/widgets/split_scope_selector.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #1149 surfaces (a)+(c): picker filtering to the ACTIVE set (departed +
/// ghosts out of NEW-expense candidates, retention of an in-flight/legacy
/// selection), the roster-trap warning + pre-submit block, and the R6
/// frozen-expense mirror (banner, delete disabled, metadata edits open).
const _yasmin = 'uid-yasmin';
const _layla = 'uid-layla';
const _gone = 'uid-gone';
const _ghost = 'deleted-g1';

final _event = Event(
  id: 'event-1',
  name: 'Marrakech',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: _yasmin,
  participantIds: const [_yasmin, _layla, _gone, _ghost],
  participantNames: const {
    _yasmin: 'Yasmin Khan',
    _layla: 'Layla Hassan',
    _gone: 'Gone Person',
    _ghost: 'Deleted member',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 3, 20),
);

Group _group() => Group(
  id: 'group-1',
  name: 'Trip',
  inviteCode: 'ABC123',
  createdBy: _yasmin,
  // Departed uid-gone is in NEITHER list; ghost is in memberIds only.
  memberIds: const [_yasmin, _layla, _ghost],
  activeMemberIds: const [_yasmin, _layla],
  currency: 'OMR',
  createdAt: DateTime(2026),
);

GroupMember _member(String uid, String name, {bool isTombstone = false}) =>
    GroupMember(
      id: uid,
      groupId: 'group-1',
      userId: uid,
      displayName: name,
      role: uid == _yasmin ? 'CREATOR' : 'MEMBER',
      isTombstone: isTombstone,
      joinedAt: DateTime(2026),
    );

final _categories = [
  ExpenseCategory(
    id: 'food',
    tripId: 'event-1',
    name: 'Food',
    icon: 'food',
    color: '#C2693B',
    createdAt: DateTime(2026, 1, 1),
  ),
];

Expense _expense({
  String payer = _yasmin,
  ExpenseScope scope = ExpenseScope.global,
  SplitMode splitMode = SplitMode.equally,
  Map<String, Decimal>? splitDistribution,
}) => Expense(
  id: 'expense-1',
  tripId: 'event-1',
  payerParticipantId: payer,
  amount: Decimal.parse('12.000'),
  scope: scope,
  createdAt: DateTime(2026, 3, 21),
  createdBy: _yasmin,
  splitMode: splitMode,
  splitDistribution: splitDistribution,
);

void main() {
  late List<ExpenseEditorPayload> submitted;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    submitted = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    Expense? initial,
    Event? event,
    Future<void> Function()? onDelete,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue(_yasmin),
          eventDetailProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((ref) => Stream.value(event ?? _event)),
          groupDetailProvider(
            'group-1',
          ).overrideWith((ref) => Stream.value(_group())),
          groupMembersProvider('group-1').overrideWith(
            (ref) => Stream.value([
              _member(_yasmin, 'Yasmin Khan'),
              _member(_layla, 'Layla Hassan'),
              _member(_ghost, 'Deleted member', isTombstone: true),
            ]),
          ),
          tripCategoriesProvider(
            'event-1',
          ).overrideWith((ref) => Stream.value(_categories)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseEditorBody(
              groupId: 'group-1',
              eventId: 'event-1',
              mode: initial == null
                  ? ExpenseEditorMode.add
                  : ExpenseEditorMode.edit,
              currency: 'OMR',
              initial: initial,
              onSubmit: (payload) async => submitted.add(payload),
              onDelete: onDelete,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final l10nEn = AppLocalizationsEn();

  group('payer picker (a)', () {
    testWidgets('offers only active members: departed and ghost filtered', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      expect(find.text('Layla Hassan'), findsWidgets);
      expect(find.text('Gone Person'), findsNothing);
      expect(find.text('Deleted member'), findsNothing);
    });

    testWidgets('retains a legacy ghost payer as selectable (edit mode)', (
      tester,
    ) async {
      await pump(tester, initial: _expense(payer: _ghost));

      await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      // Retention rule: the CURRENT selection stays visible even though a
      // ghost is never offered as a fresh candidate.
      expect(find.text('Deleted member'), findsWidgets);
      expect(find.text('Gone Person'), findsNothing);
    });
  });

  group('custom participant selector (a)', () {
    testWidgets('filters to eligible ids, retains selected ineligible ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: CustomParticipantSelector(
                  event: _event,
                  customSplitParticipants: const {_ghost},
                  eligibleIds: const {_yasmin, _layla},
                  onCustomSplitChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yasmin Khan'), findsOneWidget);
      expect(find.text('Layla Hassan'), findsOneWidget);
      // Selected ghost retained; departed gone entirely.
      expect(find.text('Deleted member'), findsOneWidget);
      expect(find.text('Gone Person'), findsNothing);
    });
  });

  group('roster-trap warning + pre-submit block (a)', () {
    testWidgets(
      'add-mode equal split on a departed/ghost roster warns and blocks save',
      (tester) async {
        await pump(tester);

        expect(
          find.text(l10nEn.editorPartiesNotCurrentWarning),
          findsOneWidget,
        );

        await tester.enterText(find.byType(TextField).first, '10');
        // #204 category mandatory at creation.
        await tester.ensureVisible(find.text('Food'));
      await tester.tap(find.text('Food'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add'));
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        expect(submitted, isEmpty);
        // Blocked with the same explanation (snackbar + banner both present).
        expect(
          find.text(l10nEn.editorPartiesNotCurrentWarning),
          findsWidgets,
        );
      },
    );

    testWidgets('switching to Just me clears the warning and saves', (
      tester,
    ) async {
      await pump(tester);

      await tester.ensureVisible(find.text('Just me'));
      await tester.tap(find.text('Just me'));
      await tester.pumpAndSettle();

      expect(find.text(l10nEn.editorPartiesNotCurrentWarning), findsNothing);

      await tester.enterText(find.byType(TextField).first, '10');
      await tester.ensureVisible(find.text('Food'));
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add'));
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      expect(submitted.single.scope, ExpenseScope.personal);
    });
  });

  group('R6 frozen mirror (c)', () {
    testWidgets(
      'departed-payer expense: banner shown, delete disabled, metadata edit '
      'still saves',
      (tester) async {
        await pump(
          tester,
          initial: _expense(
            payer: _gone,
            splitMode: SplitMode.exact,
            splitDistribution: {_gone: Decimal.parse('12.000')},
          ),
          onDelete: () async {},
        );

        expect(find.text(l10nEn.editorDepartedFrozenBanner), findsOneWidget);

        final deleteButton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Delete'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(deleteButton.onPressed, isNull);

        // Metadata-only edit passes through (rules allow it).
        await tester.enterText(
          find.byType(TextField).at(1),
          'Dinner at the riad',
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(submitted, hasLength(1));
      },
    );

    testWidgets('amount change on a frozen expense is blocked', (
      tester,
    ) async {
      await pump(
        tester,
        initial: _expense(
          payer: _gone,
          splitMode: SplitMode.exact,
          splitDistribution: {_gone: Decimal.parse('12.000')},
        ),
      );

      await tester.enterText(find.byType(TextField).first, '99');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(submitted, isEmpty);
      expect(find.text(l10nEn.editorDepartedFrozenBanner), findsWidgets);
    });

    testWidgets(
      'payer-only change on a frozen expense is blocked (the moneyDirty trap)',
      (tester) async {
        await pump(
          tester,
          initial: _expense(
            payer: _gone,
            splitMode: SplitMode.exact,
            splitDistribution: {_gone: Decimal.parse('12.000')},
          ),
        );

        await tester.ensureVisible(find.text('Change'));
      await tester.tap(find.text('Change'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Layla Hassan').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(submitted, isEmpty);
      },
    );

    testWidgets('ghost-payer expense is NOT frozen (full-memberIds set)', (
      tester,
    ) async {
      await pump(
        tester,
        initial: _expense(
          payer: _ghost,
          splitMode: SplitMode.exact,
          splitDistribution: {_ghost: Decimal.parse('12.000')},
        ),
        onDelete: () async {},
      );

      expect(find.text(l10nEn.editorDepartedFrozenBanner), findsNothing);
      final deleteButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(deleteButton.onPressed, isNotNull);
    });

    testWidgets(
      'equal-split expense freezes via the roster branch even with a live '
      'payer',
      (tester) async {
        await pump(tester, initial: _expense(payer: _yasmin), onDelete: () async {});

        expect(find.text(l10nEn.editorDepartedFrozenBanner), findsOneWidget);
      },
    );
  });
}

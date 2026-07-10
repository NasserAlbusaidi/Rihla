import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor/where_card.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _groupId = 'group-1';
const _eventId = 'event-1';
const _uid = 'uid-yasmin';

Future<void> _noopSubmit(ExpenseEditorPayload payload) async {}

final _group = Group(
  id: _groupId,
  name: 'Weekend Travellers',
  inviteCode: 'ABC123',
  createdBy: _uid,
  memberIds: const [_uid],
  createdAt: DateTime(2026, 7, 1),
);

Event _event({String name = 'Salalah Trip'}) => Event(
  id: _eventId,
  name: name,
  type: EventType.trip,
  groupId: _groupId,
  createdBy: _uid,
  participantIds: const [_uid],
  participantNames: const {_uid: 'Yasmin'},
  modules: const EventModules(),
  startDate: DateTime(2026, 7, 10),
  createdAt: DateTime(2026, 7, 1),
);

final _initialExpense = Expense(
  id: 'expense-1',
  tripId: _eventId,
  payerParticipantId: _uid,
  amount: Decimal.parse('10'),
  description: 'Lunch',
  scope: ExpenseScope.global,
  categoryId: 'food',
  splitMode: SplitMode.equally,
  createdAt: DateTime(2026, 7, 10),
  createdBy: _uid,
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  ExpenseEditorMode mode = ExpenseEditorMode.add,
  Expense? initial,
  Event? event,
  TextScaler? textScaler,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final resolvedEvent = event ?? _event();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(_uid),
        userGroupsProvider.overrideWith((ref) => Stream.value([_group])),
        groupEventsProvider(
          _groupId,
        ).overrideWith((ref) => Stream.value([resolvedEvent])),
        eventDetailProvider((
          groupId: _groupId,
          eventId: _eventId,
        )).overrideWith((ref) => Stream.value(resolvedEvent)),
        tripCategoriesProvider(
          _eventId,
        ).overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: ExpenseEditorBody(
          groupId: _groupId,
          eventId: _eventId,
          mode: mode,
          currency: 'OMR',
          initial: initial,
          onSubmit: _noopSubmit,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'add mode shows the destination banner under the top bar (#1088)',
    (tester) async {
      await _pumpEditor(tester);

      final banner = find.byKey(LedgerKeys.editorDestinationBanner);
      expect(banner, findsOneWidget);
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Adding to Salalah Trip'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(find.byType(SingleChildScrollView)).dy),
      );
      expect(tester.getSize(banner).height, greaterThanOrEqualTo(44));
      expect(find.byType(WhereCard), findsOneWidget);
    },
  );

  testWidgets('banner tap on a pristine form opens the target picker (#1088)', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.tap(find.byKey(LedgerKeys.editorDestinationBanner));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(HomeKeys.addExpenseSheet), findsOneWidget);
  });

  testWidgets('banner tap on a dirty form confirms discard first (#1088)', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();
    await tester.tap(find.byKey(LedgerKeys.editorDestinationBanner));
    await tester.pump();

    expect(find.text('Discard this expense?'), findsOneWidget);
    expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);

    await tester.tap(find.text('Keep editing'));
    await tester.pump();

    expect(find.text('Discard this expense?'), findsNothing);
    expect(find.byKey(HomeKeys.addExpenseSheet), findsNothing);
    expect(find.byKey(LedgerKeys.editorDestinationBanner), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '5',
    );
  });

  testWidgets('edit mode has no banner (#1088)', (tester) async {
    await _pumpEditor(
      tester,
      mode: ExpenseEditorMode.edit,
      initial: _initialExpense,
    );

    expect(find.byKey(LedgerKeys.editorDestinationBanner), findsNothing);
  });

  testWidgets('banner is one line at 1.5x text scale (#1088)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpEditor(
      tester,
      event: _event(
        name: 'Salalah Trip With A Deliberately Long Destination Name',
      ),
      textScaler: const TextScaler.linear(1.5),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'the fixed destination banner must not overflow at 1.5x',
    );
    final bannerText = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(LedgerKeys.editorDestinationBanner),
        matching: find.byType(Text),
      ),
    );
    expect(bannerText, hasLength(2));
    expect(bannerText.every((text) => text.maxLines == 1), isTrue);
  });

  testWidgets(
    'banner has button semantics naming destination and change (#1088)',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpEditor(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel(
          RegExp('Salalah Trip.*change', caseSensitive: false),
        ),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().label, contains('Salalah Trip'));
      expect(node.getSemanticsData().label, contains('change'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    },
  );
}

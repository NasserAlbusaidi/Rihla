import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/widgets/split_scope_selector.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// #485: the scope tabs + the single payer control moved onto the unified
// `SplitCard` (see split_card_test.dart). What stays here is the inline custom
// ("Some people") roster, `CustomParticipantSelector`.
void main() {
  testWidgets(
    'custom roster lists every member including yourself and toggles self in (#247)',
    (tester) async {
      Set<String>? selectedParticipants;

      await _pumpSelector(
        tester,
        customSplitParticipants: const {'uid-yasmin'},
        onCustomSplitChanged: (ids) => selectedParticipants = ids,
      );

      expect(find.text('SELECT PARTICIPANTS'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Yasmin Khan'), findsOneWidget);
      expect(find.text('Omar Said'), findsOneWidget);
      // #247: the current user is no longer filtered out of the custom picker.
      expect(find.text('Layla Hassan'), findsOneWidget);

      // Toggling self adds the current user to the custom set.
      await tester.tap(find.text('Layla Hassan'));
      await tester.pump();

      expect(selectedParticipants, {'uid-yasmin', 'uid-layla'});
    },
  );
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  Set<String> customSplitParticipants = const {},
  ValueChanged<Set<String>>? onCustomSplitChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: CustomParticipantSelector(
              event: _event,
              customSplitParticipants: customSplitParticipants,
              onCustomSplitChanged: onCustomSplitChanged ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla', 'uid-omar'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
    'uid-omar': 'Omar Said',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

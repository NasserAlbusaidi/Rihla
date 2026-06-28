import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/widgets/split_scope_selector.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #278 — a placeholder ("shadow") member who has not joined yet must be
/// marked as such in the custom ("Some people") roster, where they appear as a
/// participant. The shadow flag lives on [GroupMember.isShadow]; the rows are
/// built from event data, so the flag is threaded by matching on `userId`.
void main() {
  testWidgets(
    'custom participant picker shows the shadow marker for a shadow member',
    (tester) async {
      await _pumpSelector(tester);

      // Omar is a shadow member → the "Shadow Profile" subtitle renders.
      expect(find.text('Shadow Profile'), findsOneWidget);
      // The two real members carry no shadow marker.
      expect(find.text('Yasmin Khan'), findsOneWidget);
      expect(find.text('Omar Said'), findsOneWidget);
    },
  );
}

Future<void> _pumpSelector(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupMembersProvider(
          'group-1',
        ).overrideWith((ref) => Stream.value(_members)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: CustomParticipantSelector(
              event: _event,
              customSplitParticipants: const {},
              onCustomSplitChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _members = [
  GroupMember(
    id: 'm-yasmin',
    groupId: 'group-1',
    userId: 'uid-yasmin',
    displayName: 'Yasmin Khan',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 5, 30),
  ),
  GroupMember(
    id: 'm-omar',
    groupId: 'group-1',
    userId: 'uid-omar',
    displayName: 'Omar Said',
    role: 'MEMBER',
    isShadow: true,
    joinedAt: DateTime(2026, 5, 30),
  ),
];

final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-omar'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-omar': 'Omar Said',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

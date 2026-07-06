import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/search/widgets/search_results.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #967 — a search result row must announce as one merged button, not a set
/// of separate icon/title/subtitle fragments.
const _uid = 'test-user-id';

Group _group(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: _uid,
  memberIds: const [_uid],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Future<void> _pump(WidgetTester tester, List<Group> groups) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userGroupsProvider.overrideWith((ref) => Stream.value(groups)),
        for (final group in groups)
          groupEventsProvider(
            group.id,
          ).overrideWith((ref) => Stream.value(const <Event>[])),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SearchResults(query: 'Desert')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a search result row merges into one button node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, [_group('g1', 'Desert Crew')]);

    expect(find.text('Desert Crew'), findsOneWidget);

    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Desert Crew')));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });
}

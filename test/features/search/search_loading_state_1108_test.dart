import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/search/keys/search_keys.dart';
import 'package:safar/features/search/widgets/search_results.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

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

Future<void> _pumpResults(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SearchResults(query: 'Alps')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets(
    'cold auth loading does not render confirmed no-matches state (#1108)',
    (tester) async {
      final auth = StreamController<User?>();
      addTearDown(auth.close);

      await _pumpResults(
        tester,
        overrides: [firebaseUserProvider.overrideWith((ref) => auth.stream)],
      );

      expect(find.byKey(SearchKeys.emptyState), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'unresolved event stream does not render confirmed no-matches state (#1108)',
    (tester) async {
      final events = StreamController<List<Event>>();
      addTearDown(events.close);
      final group = _group('g1', 'Desert Crew');

      await _pumpResults(
        tester,
        overrides: [
          firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
          userGroupsProvider.overrideWith((ref) => Stream.value([group])),
          groupEventsProvider(group.id).overrideWith((ref) => events.stream),
        ],
      );

      expect(find.byKey(SearchKeys.emptyState), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );
}

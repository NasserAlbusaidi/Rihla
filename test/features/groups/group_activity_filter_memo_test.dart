// #634 regression: the group activity feed's filtered list must be memoized.
//
// Before the fix `_filtered` re-ran `_activities.where(...).toList()` on EVERY
// build — including re-tapping the already-active chip (no equality guard) and
// any unrelated rebuild (e.g. the group-name stream re-emitting). This pins
// both: re-tapping the active chip is a no-op, and an unrelated rebuild reuses
// the cached result. `debugGroupActivityFilterComputes` counts real recomputes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_activity_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

DateTime _atMidday(int dayOffset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, 12);
}

Group _group({String id = 'grp-memo', String name = 'Test Crew'}) => Group(
      id: id,
      name: name,
      inviteCode: 'TC123',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _seed(FakeFirebaseFirestore db, String gid) async {
  final logs = [
    GroupActivityLog(
      id: 'a1',
      type: 'group_settlement',
      actorId: 'uid-a',
      actorName: 'Alice',
      description: 'paid Bob',
      timestamp: _atMidday(0),
    ),
    GroupActivityLog(
      id: 'a2',
      type: 'event_created',
      actorId: 'uid-b',
      actorName: 'Bob',
      description: 'created a trip',
      timestamp: _atMidday(-1),
    ),
  ];
  for (final a in logs) {
    await db
        .collection('groups')
        .doc(gid)
        .collection('activity')
        .doc(a.id)
        .set({
      'id': a.id,
      'type': a.type,
      'actorId': a.actorId,
      'actorName': a.actorName,
      'description': a.description,
      'metadata': a.metadata,
      'timestamp': a.timestamp.toUtc().toIso8601String(),
    });
  }
}

Widget _screen(String gid, FakeFirebaseFirestore db, SharedPreferences prefs,
    {Stream<Group?>? groupStream}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupActivityServiceProvider
          .overrideWith((ref) => GroupActivityService.withFirestore(db)),
      groupDetailProvider(gid)
          .overrideWith((ref) => groupStream ?? Stream.value(_group(id: gid))),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupActivityScreen(groupId: gid),
    ),
  );
}

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  setUp(() => debugGroupActivityFilterComputes = 0);

  testWidgets('re-tapping the active filter chip does NOT recompute (#634)',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final prefs = await SharedPreferences.getInstance();
    await _seed(db, 'grp-memo');
    await tester.pumpWidget(_screen('grp-memo', db, prefs));
    await tester.pumpAndSettle();

    final before = debugGroupActivityFilterComputes;

    // "All" is the active chip by default — re-tap it three times.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(GroupKeys.activityFilterAll));
      await tester.pump();
    }

    expect(
      debugGroupActivityFilterComputes,
      before,
      reason: 're-tapping the already-active chip must be a no-op (#634)',
    );
  });

  testWidgets('an unrelated rebuild reuses the cached filtered list (#634)',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final prefs = await SharedPreferences.getInstance();
    await _seed(db, 'grp-memo');

    // A group-name stream that re-emits a NEW value forces a rebuild without
    // changing _activities or _filter — the filtered list must be reused.
    final ctrl = StreamController<Group?>();
    addTearDown(ctrl.close);

    await tester.pumpWidget(
      _screen('grp-memo', db, prefs, groupStream: ctrl.stream),
    );
    ctrl.add(_group(name: 'Test Crew'));
    await tester.pumpAndSettle();

    final before = debugGroupActivityFilterComputes;

    ctrl.add(_group(name: 'Renamed Crew')); // unrelated rebuild
    await tester.pumpAndSettle();

    expect(find.text('Renamed Crew'), findsOneWidget); // the rebuild happened
    expect(
      debugGroupActivityFilterComputes,
      before,
      reason: 'a rebuild that changes neither activities nor filter must not '
          'recompute the filtered list (#634)',
    );
  });

  testWidgets('switching to a DIFFERENT filter recomputes once + filters (#634)',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final prefs = await SharedPreferences.getInstance();
    await _seed(db, 'grp-memo');
    await tester.pumpWidget(_screen('grp-memo', db, prefs));
    await tester.pumpAndSettle();

    final before = debugGroupActivityFilterComputes;

    await tester.tap(find.byKey(GroupKeys.activityFilterSettlements));
    await tester.pumpAndSettle();

    expect(
      debugGroupActivityFilterComputes,
      greaterThan(before),
      reason: 'a genuine filter change must recompute',
    );
    // Behaviour preserved: only the settlement row remains.
    expect(
      find.byWidgetPredicate((w) =>
          w is Text &&
          (w.textSpan?.toPlainText().contains('recorded a settlement') ??
              false)),
      findsOneWidget,
    );
  });
}

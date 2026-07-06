import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_activity_screen.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #928 — the group activity screen must render the GOOD rows even when one row
/// is malformed. Before the fence, `_loadPage`'s `.map` threw on a null
/// `description` (an `as String` cast), the whole-page `catch (_)` flipped
/// `_loadFailed`, and the screen showed its error state instead of the rows.
void main() {
  const groupId = 'grp-test';

  final group = Group(
    id: groupId,
    name: 'Test Crew',
    inviteCode: 'TC123',
    createdBy: 'uid-alice',
    memberIds: const ['uid-alice', 'uid-bob'],
    createdAt: DateTime(2026, 1, 1),
  );

  DateTime midday(int dayOffset) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + dayOffset, 12);
  }

  Future<void> seedGoodAndBad(FakeFirebaseFirestore db) async {
    final activity =
        db.collection('groups').doc(groupId).collection('activity');
    // Good row — newest (timestamp is the sort key, valid on both).
    await activity.doc('good').set({
      'id': 'good',
      'type': 'group_settlement',
      'actorId': 'uid-alice',
      'actorName': 'GoodActor',
      'description': 'paid Bob',
      'metadata': <String, dynamic>{},
      'timestamp': midday(0).toUtc().toIso8601String(),
    });
    // Malformed row — null description (NOT the sort key) throws pre-fence.
    await activity.doc('bad').set({
      'id': 'bad',
      'type': 'event_created',
      'actorId': 'uid-bob',
      'actorName': 'BadActor',
      'description': null,
      'metadata': <String, dynamic>{},
      'timestamp': midday(-1).toUtc().toIso8601String(),
    });
  }

  Widget buildScreen(FakeFirebaseFirestore db) => ProviderScope(
        overrides: [
          groupActivityServiceProvider
              .overrideWith((ref) => GroupActivityService.withFirestore(db)),
          groupDetailProvider(groupId)
              .overrideWith((ref) => Stream.value(group)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GroupActivityScreen(groupId: groupId),
        ),
      );

  testWidgets('renders the good row and skips the malformed one', (tester) async {
    final db = FakeFirebaseFirestore();
    await seedGoodAndBad(db);

    await tester.pumpWidget(buildScreen(db));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.textContaining('GoodActor', findRichText: true),
      findsOneWidget,
    );
  });
}

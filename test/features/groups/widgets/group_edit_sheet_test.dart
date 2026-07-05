import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/widgets/group_edit_sheet.dart';
import 'package:safar/features/groups/widgets/group_stamp_icon.dart';
import 'package:safar/features/home/widgets/group_glyph.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Records every [updateGroupIdentity] call so a test can assert the exact
/// args (or that it was never called). Mirrors the recording-fake idiom in
/// `group_settings_screen_test.dart` (`_RemovingGroupService`).
class RecordingGroupService extends GroupService {
  RecordingGroupService(Ref ref)
    : super.withFirestore(ref, FakeFirebaseFirestore());

  final calls = <({String groupId, String name, String? glyph, int? inkIndex})>[];

  @override
  Future<void> updateGroupIdentity({
    required String groupId,
    required String name,
    String? glyph,
    int? inkIndex,
  }) async {
    calls.add((
      groupId: groupId,
      name: name,
      glyph: glyph,
      inkIndex: inkIndex,
    ));
  }
}

Group _seedGroup({String? glyph = 'tent', int? inkIndex = 1}) => Group(
  id: 'group-1',
  name: 'Salalah Crew',
  inviteCode: 'SLLH42',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator'],
  currency: 'OMR',
  createdAt: DateTime(2026, 6, 12),
  glyph: glyph,
  inkIndex: inkIndex,
);

/// Pumps [GroupEditSheet] directly inside a themed app + recording service.
/// Returns the service so callers can read [calls]. The container is read
/// eagerly so the recording service exists even for tests that never tap Save
/// (a lazy `overrideWith` would leave it uninstantiated until the first read).
Future<RecordingGroupService> pumpSheet(
  WidgetTester tester, {
  required Group group,
}) async {
  final container = ProviderContainer(
    overrides: [
      groupServiceProvider.overrideWith(RecordingGroupService.new),
    ],
  );
  addTearDown(container.dispose);
  final service =
      container.read(groupServiceProvider) as RecordingGroupService;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GroupEditSheet(group: group)),
      ),
    ),
  );
  await tester.pump();
  return service;
}

const _saffron = Color(0xFF8A5D0D);

/// True iff the keyed ring container paints a saffron (primary) border — the
/// picker's selection signal (same helper as `group_stamp_picker_test.dart`).
bool hasSaffronRing(WidgetTester tester, Finder ringFinder) {
  final container = tester.widget<Container>(ringFinder);
  final deco = container.decoration as BoxDecoration?;
  final border = deco?.border;
  if (border is! Border) return false;
  return border.top.color == _saffron && border.top.width > 0;
}

void main() {
  group('GroupEditSheet', () {
    testWidgets('seeds the symbol + ink selection and hero from the group', (
      tester,
    ) async {
      await pumpSheet(tester, group: _seedGroup());

      // Seeded symbol cell + ink swatch are ringed.
      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_tent_ring'))),
        isTrue,
        reason: 'tent symbol seeded as selected',
      );
      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampInk_1_ring'))),
        isTrue,
        reason: 'inkIndex 1 seeded as selected',
      );

      // Exactly one hero GroupGlyph (the sheet's own), seeded with the stamp.
      final heroes = tester.widgetList<GroupGlyph>(find.byType(GroupGlyph));
      expect(heroes, hasLength(1), reason: 'one hero, picker hero suppressed');
      expect(heroes.first.glyph, 'tent');
      expect(heroes.first.inkIndex, 1);
      expect(heroes.first.name, 'Salalah Crew');
    });

    testWidgets('changing the symbol selects the new cell, deselects tent', (
      tester,
    ) async {
      await pumpSheet(tester, group: _seedGroup());

      // The symbol grid sits below the fold in the test viewport — scroll the
      // target cell into view before tapping it.
      final wave = find.byKey(const Key('stampSym_wave'));
      await tester.ensureVisible(wave);
      await tester.pump();
      await tester.tap(wave);
      await tester.pump();

      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_wave_ring'))),
        isTrue,
      );
      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_tent_ring'))),
        isFalse,
      );
    });

    testWidgets('removing the symbol selects the monogram + clears the glyph', (
      tester,
    ) async {
      await pumpSheet(tester, group: _seedGroup());

      await tester.tap(find.byKey(const Key('stampSym_monogram')));
      await tester.pump();

      expect(
        hasSaffronRing(tester, find.byKey(const Key('stampSym_monogram_ring'))),
        isTrue,
      );
      // Hero now shows the monogram, not the tent GroupStampIcon.
      final hero = tester.widget<GroupGlyph>(find.byType(GroupGlyph));
      expect(hero.glyph, isNull, reason: 'glyph cleared');
      expect(
        find.descendant(
          of: find.byType(GroupGlyph),
          matching: find.byType(GroupStampIcon),
        ),
        findsNothing,
        reason: 'no symbol icon — monogram letter instead',
      );
    });

    testWidgets('Save writes the edited name + selected stamp once', (
      tester,
    ) async {
      final service = await pumpSheet(tester, group: _seedGroup());

      await tester.enterText(
        find.byKey(GroupKeys.editGroupNameField),
        'Renamed',
      );
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pump();

      expect(service.calls, hasLength(1));
      final call = service.calls.single;
      expect(call.groupId, 'group-1');
      expect(call.name, 'Renamed');
      expect(call.glyph, 'tent', reason: 'seeded glyph carried to save');
      expect(call.inkIndex, 1, reason: 'seeded ink carried to save');
    });

    testWidgets('clearing the symbol then Save records glyph: null', (
      tester,
    ) async {
      final service = await pumpSheet(tester, group: _seedGroup());

      await tester.tap(find.byKey(const Key('stampSym_monogram')));
      await tester.pump();
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pump();

      expect(service.calls, hasLength(1));
      final call = service.calls.single;
      expect(
        call.glyph,
        isNull,
        reason: 'cleared symbol → glyph null → FieldValue.delete in the provider',
      );
      expect(call.name, 'Salalah Crew', reason: 'unedited name carried');
      expect(call.inkIndex, 1, reason: 'untouched ink carried');
    });

    testWidgets('empty name blocks Save (validation, no write)', (
      tester,
    ) async {
      final service = await pumpSheet(tester, group: _seedGroup());

      await tester.enterText(find.byKey(GroupKeys.editGroupNameField), '');
      await tester.tap(find.byKey(GroupKeys.editGroupSaveButton));
      await tester.pump();

      expect(service.calls, isEmpty, reason: 'invalid name must not write');
      // A validation error is surfaced under the field.
      expect(find.text("Name can't be empty."), findsOneWidget);
    });

    testWidgets('Cancel pops the sheet without writing', (tester) async {
      // Drive through a button so the sheet is a real route to pop.
      final container = ProviderContainer(
        overrides: [
          groupServiceProvider.overrideWith(RecordingGroupService.new),
        ],
      );
      addTearDown(container.dispose);
      final service =
          container.read(groupServiceProvider) as RecordingGroupService;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        GroupEditSheet.show(context, group: _seedGroup()),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(GroupKeys.editGroupSheet), findsOneWidget);

      await tester.tap(find.byKey(GroupKeys.editGroupCancelButton));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.editGroupSheet), findsNothing);
      expect(service.calls, isEmpty);
    });
  });
}

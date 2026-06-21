// test/features/events/event_info_section_leak_test.dart
//
// #625 regression: EventInfoSection._buildDateTile rendered each read-only date
// as a `TextField(controller: TextEditingController(...))` allocated INLINE in
// build(). The State only disposes _nameController/_descriptionController, so
// every build orphaned two date controllers (start + end) that were never
// disposed — a leak that grows on each date-pick / save-spinner rebuild.
//
// The fields are readOnly and wrapped in AbsorbPointer (a GestureDetector opens
// the picker), so the editing controller was pure dead weight. The fix renders
// the date as an InputDecorator + Text — no controller, nothing to leak.
//
// A leak-tracker assertion is unreliable here (notDisposed detection is
// finalizer/GC-timed and a short widget test may not collect the orphan), so we
// pin the leak's MECHANISM structurally: the read-only date tiles must not be
// editable, controller-bearing TextFields. Only the name + description fields
// may be TextFields.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/widgets/event_info_section.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

Event _event() => Event(
      id: 'evt-1',
      name: 'Summer Trip',
      type: EventType.trip,
      groupId: 'group-1',
      createdBy: 'uid-creator',
      participantIds: const ['uid-creator'],
      participantNames: const {'uid-creator': 'Alice'},
      modules: EventModules.forType(EventType.trip),
      startDate: DateTime.utc(2026, 3, 1),
      endDate: DateTime.utc(2026, 3, 8),
      createdAt: DateTime(2026, 1, 1),
    );

Widget _wrap(Event event) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: EventInfoSection(event: event)),
        ),
      ),
    );

void main() {
  testWidgets(
    'read-only date tiles are not controller-bearing TextFields (#625 leak)',
    (tester) async {
      await tester.pumpWidget(_wrap(_event()));
      await tester.pump();

      // Only the editable name + description fields may be TextFields. The two
      // date tiles must render as non-editable displays (no inline controller
      // to leak).
      expect(
        find.descendant(
          of: find.byType(EventInfoSection),
          matching: find.byType(TextField),
        ),
        findsNWidgets(2),
        reason: 'each extra TextField is a date tile carrying an undisposed '
            'inline TextEditingController (#625)',
      );

      // Behaviour preserved: both date tiles still render their label AND the
      // formatted date value (en locale → DateFormat.yMMMd).
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
      expect(find.text('Mar 1, 2026'), findsOneWidget);
      expect(find.text('Mar 8, 2026'), findsOneWidget);
    },
  );
}

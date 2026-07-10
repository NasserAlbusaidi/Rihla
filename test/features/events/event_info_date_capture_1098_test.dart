import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/widgets/event_info_section.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1098: the event-settings date tiles must capture the PICKED calendar date
/// (anchored, no `.toUtc()` component shift) and render it back verbatim.
Event _event() => Event(
      id: 'evt-1',
      name: 'Summer Trip',
      type: EventType.trip,
      groupId: 'group-1',
      createdBy: 'uid-creator',
      participantIds: const ['uid-creator'],
      participantNames: const {'uid-creator': 'Alice'},
      modules: EventModules.forType(EventType.trip),
      startDate: DateTime.utc(2026, 3, 1, 12),
      endDate: DateTime.utc(2026, 3, 8, 12),
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
  testWidgets('picking a start date renders that calendar date (#1098)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_event()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mar 1, 2026'));
    await tester.pumpAndSettle();

    // Picker opens on March 2026 (initialDate = current start) — pick the 15th.
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Mar 15, 2026'), findsOneWidget);
    expect(find.text('Mar 1, 2026'), findsNothing);
  });

  testWidgets('picking an end date renders that calendar date (#1098)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_event()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mar 8, 2026'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Mar 20, 2026'), findsOneWidget);
    expect(find.text('Mar 8, 2026'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/widgets/split_scope_selector.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #289 — two members named "Ahmed" must be distinguishable in the custom
/// ("Some people") roster, where money is attributed. The payer picker's own
/// disambiguation is covered by expense_editor_body_same_name_test.dart (#485
/// retired the second, in-roster payer dropdown).
void main() {
  testWidgets('custom participant picker disambiguates two same-named members',
      (tester) async {
    await _pumpSelector(tester);

    expect(find.text('Ahmed (#aaaa)'), findsOneWidget);
    expect(find.text('Ahmed (#bbbb)'), findsOneWidget);
    // Bare "Ahmed" must NOT appear — that is the ambiguous mis-attribution.
    expect(find.text('Ahmed'), findsNothing);
    // Non-colliding member stays bare.
    expect(find.text('Sara Said'), findsOneWidget);
  });
}

Future<void> _pumpSelector(WidgetTester tester) async {
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

final _event = Event(
  id: 'event-1',
  name: 'Muscat weekend',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-sara-3333',
  participantIds: const ['uid-ahmed-aaaa', 'uid-ahmed-bbbb', 'uid-sara-3333'],
  participantNames: const {
    'uid-ahmed-aaaa': 'Ahmed',
    'uid-ahmed-bbbb': 'Ahmed',
    'uid-sara-3333': 'Sara Said',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 30),
);

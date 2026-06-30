import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/settle_scope_note.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #717 — the persistent settle-up scope note. The note tells the user what a
/// recorded payment covers: this event only (event surface) vs the complete
/// whole-group balance (group surface). The load-bearing guard is that the
/// WRONG surface's copy never appears — a group note on an event screen (or
/// vice versa) would misrepresent what a payment settles.
Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  const eventName = 'Salalah road trip';

  testWidgets('event scope shows the event-only copy, not the group copy', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _host(
        const SettleScopeNote(
          scope: SettleScope.event,
          subjectName: eventName,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleScopeNote), findsOneWidget);
    expect(find.text(l10n.settleScopeNoteEvent(eventName)), findsOneWidget);
    // The whole-group copy must NOT leak onto the event surface.
    expect(find.text(l10n.settleScopeNoteGroup), findsNothing);
  });

  testWidgets('group scope shows the whole-group copy, not the event copy', (
    tester,
  ) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _host(
        const SettleScopeNote(
          scope: SettleScope.group,
          subjectName: 'Salalah Squad',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleScopeNote), findsOneWidget);
    expect(find.text(l10n.settleScopeNoteGroup), findsOneWidget);
    // The event-only copy (which interpolates the subject name) must NOT appear.
    expect(
      find.text(l10n.settleScopeNoteEvent('Salalah Squad')),
      findsNothing,
    );
  });

  testWidgets('note is persistent — no dismiss affordance', (tester) async {
    await tester.pumpWidget(
      _host(
        const SettleScopeNote(
          scope: SettleScope.group,
          subjectName: 'Salalah Squad',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Unlike the one-time CurrencyBucketsExplainer, the scope note never offers
    // a "Got it" / dismiss button — it stays on every visit.
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}

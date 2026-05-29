// Coverage-gap closing tests for shared and feature widgets.
//
// Targets:
//   - ModuleHeader (27 uncov)
//   - InviteCodeDisplay (21 uncov)
//   - OfflineBanner (7 uncov)
//   - SkeletonLoader factory methods (6 uncov)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/module_header.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/features/groups/widgets/invite_code_display.dart';

void main() {

  // ---------------------------------------------------------------------------
  // ModuleHeader
  // ---------------------------------------------------------------------------

  group('ModuleHeader', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: child),
    );

    testWidgets('renders title in light theme', (tester) async {
      await tester.pumpWidget(wrap(const ModuleHeader(title: 'Expenses')));
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
    });

    testWidgets('renders subtitle in light theme', (tester) async {
      await tester.pumpWidget(
        wrap(const ModuleHeader(title: 'Gear', subtitle: 'PACK LIST')),
      );
      await tester.pump();

      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('PACK LIST'), findsOneWidget);
    });

    testWidgets('renders actions in light theme', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(
          ModuleHeader(
            title: 'Vault',
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => tapped = true,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders bottom widget in light theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ModuleHeader(
            title: 'Activities',
            bottom: Text('bottom content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('bottom content'), findsOneWidget);
    });

    testWidgets('renders title in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(const ModuleHeader(title: 'Dark Header', useDarkTheme: true)),
      );
      await tester.pump();

      expect(find.text('Dark Header'), findsOneWidget);
    });

    testWidgets('renders subtitle in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ModuleHeader(
            title: 'Trip',
            subtitle: 'JOURNEY',
            useDarkTheme: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('JOURNEY'), findsOneWidget);
    });

    testWidgets('renders actions in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ModuleHeader(
            title: 'Events',
            useDarkTheme: true,
            actions: [Icon(Icons.settings)],
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('renders bottom widget in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ModuleHeader(
            title: 'Members',
            useDarkTheme: true,
            bottom: Text('dark bottom'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('dark bottom'), findsOneWidget);
    });

    testWidgets('back button exists in light theme', (tester) async {
      await tester.pumpWidget(wrap(const ModuleHeader(title: 'Back Test')));
      await tester.pump();

      // Back button uses GestureDetector
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('back button exists in dark theme', (tester) async {
      await tester.pumpWidget(
        wrap(const ModuleHeader(title: 'Dark Back', useDarkTheme: true)),
      );
      await tester.pump();

      expect(find.byType(GestureDetector), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // InviteCodeDisplay
  // ---------------------------------------------------------------------------

  group('InviteCodeDisplay', () {
    Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('renders invite code text', (tester) async {
      await tester.pumpWidget(wrap(const InviteCodeDisplay(code: 'ABC123')));
      await tester.pump();

      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('renders without action buttons when none provided', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const InviteCodeDisplay(code: 'XYZ789')));
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsNothing);
      expect(find.byKey(SharedKeys.inviteCodeShareButton), findsNothing);
    });

    testWidgets('renders Copy Code button when onCopy is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(InviteCodeDisplay(code: 'DEF456', onCopy: () {})),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsOneWidget);
    });

    testWidgets('renders Share button when onShare is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(InviteCodeDisplay(code: 'GHI789', onShare: () {})),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeShareButton), findsOneWidget);
    });

    testWidgets(
      'renders both Copy Code and Share when both callbacks provided',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            InviteCodeDisplay(code: 'JKL012', onCopy: () {}, onShare: () {}),
          ),
        );
        await tester.pump();

        expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsOneWidget);
        expect(find.byKey(SharedKeys.inviteCodeShareButton), findsOneWidget);
      },
    );

    testWidgets('tapping Copy Code calls onCopy', (tester) async {
      var copied = false;
      await tester.pumpWidget(
        wrap(InviteCodeDisplay(code: 'MNO345', onCopy: () => copied = true)),
      );
      await tester.pump();

      await tester.tap(find.byKey(SharedKeys.inviteCodeCopyButton));
      await tester.pump();

      expect(copied, isTrue);
    });

    testWidgets('tapping Share calls onShare', (tester) async {
      var shared = false;
      await tester.pumpWidget(
        wrap(InviteCodeDisplay(code: 'PQR678', onShare: () => shared = true)),
      );
      await tester.pump();

      await tester.tap(find.byKey(SharedKeys.inviteCodeShareButton));
      await tester.pump();

      expect(shared, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // OfflineBanner
  // ---------------------------------------------------------------------------

  group('OfflineBanner', () {
    testWidgets('shows banner text when offline', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith(
              (ref) => ConnectivityNotifier()..setOffline(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OfflineBanner()),
          ),
        ),
      );
      await tester.pump();

      // Offline banner shows the sync message
      expect(find.textContaining("You're offline"), findsOneWidget);
    });

    testWidgets('hides banner when online', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith(
              (ref) => ConnectivityNotifier()..setOnline(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: OfflineBanner()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining("You're offline"), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // SkeletonLoader
  // ---------------------------------------------------------------------------

  group('SkeletonLoader', () {
    testWidgets('cardList factory renders without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: SkeletonLoader.cardList(count: 3),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('documentList factory renders without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: SkeletonLoader.documentList(count: 2),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('groupList factory renders without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: SkeletonLoader.groupList(count: 2),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });
  });
}

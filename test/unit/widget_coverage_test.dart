// Coverage-gap closing tests for shared and feature widgets.
//
// Targets:
//   - AppTabBar (17 uncov)
//   - ModuleHeader (27 uncov)
//   - InviteCodeDisplay (21 uncov)
//   - GroupBalanceHero (21 uncov)
//   - SmartModuleCard (18 uncov)
//   - ShimmerPlaceholder (28 uncov lines in loading_button.dart)
//   - OfflineBanner (7 uncov)
//   - SkeletonLoader factory methods (6 uncov)

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/shared/widgets/app_tab_bar.dart';
import 'package:safar/shared/widgets/loading_button.dart';
import 'package:safar/shared/widgets/module_header.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/shared/widgets/smart_module_card.dart';
import 'package:safar/features/groups/widgets/group_balance_hero.dart';
import 'package:safar/features/groups/widgets/invite_code_display.dart';

// ---------------------------------------------------------------------------
// AppTabBar
// ---------------------------------------------------------------------------

void main() {
  group('AppTabBar', () {
    Widget _buildTabBar({
      required List<String> tabs,
      Color? activeColor,
    }) {
      return MaterialApp(theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DefaultTabController(
            length: tabs.length,
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                return AppTabBar(
                  controller: controller,
                  tabs: tabs,
                  activeColor: activeColor,
                );
              },
            ),
          ),
        ),
      );
    }

    testWidgets('renders tab labels', (tester) async {
      await tester.pumpWidget(_buildTabBar(tabs: ['Alpha', 'Beta']));
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('renders three tabs', (tester) async {
      await tester.pumpWidget(
        _buildTabBar(tabs: ['One', 'Two', 'Three']),
      );
      await tester.pump();

      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
    });

    testWidgets('renders with custom activeColor', (tester) async {
      await tester.pumpWidget(
        _buildTabBar(tabs: ['X', 'Y'], activeColor: Colors.purple),
      );
      await tester.pump();

      // Widget renders without error with custom color
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('renders TabBar widget', (tester) async {
      await tester.pumpWidget(_buildTabBar(tabs: ['Tab1', 'Tab2']));
      await tester.pump();

      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('tapping second tab does not throw', (tester) async {
      await tester.pumpWidget(_buildTabBar(tabs: ['A', 'B', 'C']));
      await tester.pump();

      await tester.tap(find.byKey(SharedKeys.appTabBarTab('B')));
      await tester.pump();

      expect(find.text('B'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // ModuleHeader
  // ---------------------------------------------------------------------------

  group('ModuleHeader', () {
    Widget _wrap(Widget child) =>
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

    testWidgets('renders title in light theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ModuleHeader(title: 'Expenses'),
        ),
      );
      await tester.pump();

      expect(find.text('Expenses'), findsOneWidget);
    });

    testWidgets('renders subtitle in light theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ModuleHeader(
            title: 'Gear',
            subtitle: 'PACK LIST',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Gear'), findsOneWidget);
      expect(find.text('PACK LIST'), findsOneWidget);
    });

    testWidgets('renders actions in light theme', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
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
        _wrap(
          ModuleHeader(
            title: 'Activities',
            bottom: const Text('bottom content'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('bottom content'), findsOneWidget);
    });

    testWidgets('renders title in dark theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ModuleHeader(
            title: 'Dark Header',
            useDarkTheme: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Dark Header'), findsOneWidget);
    });

    testWidgets('renders subtitle in dark theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ModuleHeader(
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
        _wrap(
          ModuleHeader(
            title: 'Events',
            useDarkTheme: true,
            actions: [
              const Icon(Icons.settings),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('renders bottom widget in dark theme', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ModuleHeader(
            title: 'Members',
            useDarkTheme: true,
            bottom: const Text('dark bottom'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('dark bottom'), findsOneWidget);
    });

    testWidgets('back button exists in light theme', (tester) async {
      await tester.pumpWidget(
        _wrap(ModuleHeader(title: 'Back Test')),
      );
      await tester.pump();

      // Back button uses GestureDetector
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('back button exists in dark theme', (tester) async {
      await tester.pumpWidget(
        _wrap(ModuleHeader(title: 'Dark Back', useDarkTheme: true)),
      );
      await tester.pump();

      expect(find.byType(GestureDetector), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // InviteCodeDisplay
  // ---------------------------------------------------------------------------

  group('InviteCodeDisplay', () {
    Widget _wrap(Widget child) =>
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

    testWidgets('renders invite code text', (tester) async {
      await tester.pumpWidget(
        _wrap(const InviteCodeDisplay(code: 'ABC123')),
      );
      await tester.pump();

      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('renders without action buttons when none provided', (tester) async {
      await tester.pumpWidget(
        _wrap(const InviteCodeDisplay(code: 'XYZ789')),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsNothing);
      expect(find.byKey(SharedKeys.inviteCodeShareButton), findsNothing);
    });

    testWidgets('renders Copy Code button when onCopy is provided', (tester) async {
      await tester.pumpWidget(
        _wrap(InviteCodeDisplay(
          code: 'DEF456',
          onCopy: () {},
        )),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsOneWidget);
    });

    testWidgets('renders Share button when onShare is provided', (tester) async {
      await tester.pumpWidget(
        _wrap(InviteCodeDisplay(
          code: 'GHI789',
          onShare: () {},
        )),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeShareButton), findsOneWidget);
    });

    testWidgets('renders both Copy Code and Share when both callbacks provided', (tester) async {
      await tester.pumpWidget(
        _wrap(InviteCodeDisplay(
          code: 'JKL012',
          onCopy: () {},
          onShare: () {},
        )),
      );
      await tester.pump();

      expect(find.byKey(SharedKeys.inviteCodeCopyButton), findsOneWidget);
      expect(find.byKey(SharedKeys.inviteCodeShareButton), findsOneWidget);
    });

    testWidgets('tapping Copy Code calls onCopy', (tester) async {
      var copied = false;
      await tester.pumpWidget(
        _wrap(InviteCodeDisplay(
          code: 'MNO345',
          onCopy: () => copied = true,
        )),
      );
      await tester.pump();

      await tester.tap(find.byKey(SharedKeys.inviteCodeCopyButton));
      await tester.pump();

      expect(copied, isTrue);
    });

    testWidgets('tapping Share calls onShare', (tester) async {
      var shared = false;
      await tester.pumpWidget(
        _wrap(InviteCodeDisplay(
          code: 'PQR678',
          onShare: () => shared = true,
        )),
      );
      await tester.pump();

      await tester.tap(find.byKey(SharedKeys.inviteCodeShareButton));
      await tester.pump();

      expect(shared, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // GroupBalanceHero
  // ---------------------------------------------------------------------------

  group('GroupBalanceHero', () {
    Widget _wrap(Widget child) =>
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('renders GROUP BALANCES label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('100.000'),
            userNetBalance: Decimal.zero,
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('GROUP BALANCES'), findsOneWidget);
    });

    testWidgets('shows All balances settled text when userNetBalance is zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('50.000'),
            userNetBalance: Decimal.zero,
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('All balances settled'), findsOneWidget);
    });

    testWidgets('shows All settled text when balance is zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.zero,
            userNetBalance: Decimal.zero,
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('All settled! No outstanding balances.'),
        findsOneWidget,
      );
    });

    testWidgets('shows YOU OWE label when userNetBalance is negative', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('20.000'),
            userNetBalance: Decimal.parse('-10.000'),
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU OWE'), findsOneWidget);
    });

    testWidgets('shows YOU ARE OWED label when userNetBalance is positive', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('20.000'),
            userNetBalance: Decimal.parse('10.000'),
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU ARE OWED'), findsOneWidget);
    });

    testWidgets('shows Settle Up button when balance is non-zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('30.000'),
            userNetBalance: Decimal.parse('-15.000'),
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(SharedKeys.groupBalanceSettleUpButton), findsOneWidget);
    });

    testWidgets('calls onSettleUp when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('30.000'),
            userNetBalance: Decimal.parse('-15.000'),
            currency: 'OMR',
            onSettleUp: () => tapped = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SharedKeys.groupBalanceSettleUpButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders You owe text when balance is negative', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupBalanceHero(
            totalSpent: Decimal.parse('40.000'),
            userNetBalance: Decimal.parse('-20.000'),
            currency: 'OMR',
            onSettleUp: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final allText = richTexts.map((rt) => rt.text.toPlainText()).join(' ');
      // Either TweenAnimationBuilder text or direct text contains owe
      expect(
        find.textContaining('owe').evaluate().isNotEmpty ||
            allText.contains('owe'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SmartModuleCard
  // ---------------------------------------------------------------------------

  group('SmartModuleCard', () {
    Widget _wrap(Widget child) =>
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.wallet_3,
          title: 'Ledger',
          description: 'Track expenses',
          color: Colors.blue,
          onTap: () {},
        )),
      );
      await tester.pump();

      expect(find.text('Ledger'), findsOneWidget);
    });

    testWidgets('renders description when isEmpty and no summaryText', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.bag_2,
          title: 'Gear',
          description: 'Packing list',
          color: Colors.green,
          onTap: () {},
          isEmpty: true,
        )),
      );
      await tester.pump();

      expect(find.text('Packing list'), findsOneWidget);
    });

    testWidgets('renders summaryText when not empty', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.wallet_3,
          title: 'Ledger',
          description: 'Track expenses',
          color: Colors.blue,
          onTap: () {},
          summaryText: '3 expenses',
          isEmpty: false,
        )),
      );
      await tester.pump();

      expect(find.text('3 expenses'), findsOneWidget);
    });

    testWidgets('renders actionText when provided', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.bag_2,
          title: 'Gear',
          description: 'Packing',
          color: Colors.orange,
          onTap: () {},
          actionText: '2 items unclaimed',
        )),
      );
      await tester.pump();

      expect(find.text('2 items unclaimed'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.wallet_3,
          title: 'Module',
          description: 'Desc',
          color: Colors.purple,
          onTap: () => tapped = true,
        )),
      );
      await tester.pump();

      await tester.tap(find.byType(SmartModuleCard));
      // Wait for the 500ms navigation debounce timer in _PressableWrapper
      await tester.pump(const Duration(milliseconds: 600));

      expect(tapped, isTrue);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.car,
          title: 'Logistics',
          description: 'Cars and rooms',
          color: Colors.teal,
          onTap: () {},
        )),
      );
      await tester.pump();

      expect(find.byIcon(Iconsax.car), findsOneWidget);
    });

    testWidgets('renders chevron icon', (tester) async {
      await tester.pumpWidget(
        _wrap(SmartModuleCard(
          icon: Iconsax.document_text,
          title: 'Vault',
          description: 'Store docs',
          color: Colors.indigo,
          onTap: () {},
        )),
      );
      await tester.pump();

      expect(find.byIcon(Iconsax.arrow_right_3), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // ShimmerPlaceholder (in loading_button.dart)
  // ---------------------------------------------------------------------------

  group('ShimmerPlaceholder', () {
    Widget _wrap(Widget child) =>
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

    testWidgets('renders with specified width and height', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShimmerPlaceholder(width: 200, height: 20),
        ),
      );
      await tester.pump();

      // AnimatedBuilder-based widget renders in the tree
      expect(find.byType(ShimmerPlaceholder), findsOneWidget);
    });

    testWidgets('renders with custom borderRadius', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShimmerPlaceholder(width: 100, height: 10, borderRadius: 16),
        ),
      );
      await tester.pump();

      expect(find.byType(ShimmerPlaceholder), findsOneWidget);
    });

    testWidgets('animation runs without error on pump', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShimmerPlaceholder(width: 150, height: 15),
        ),
      );
      // Run the shimmer animation for a frame
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ShimmerPlaceholder), findsOneWidget);
    });

    testWidgets('disposes animation controller without error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ShimmerPlaceholder(width: 100, height: 12),
        ),
      );
      await tester.pump();

      // Replacing the widget tree causes dispose() to be called
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      // No exception should be thrown
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
          child: MaterialApp(theme: AppTheme.lightTheme,
            home: Scaffold(body: OfflineBanner()),
          ),
        ),
      );
      await tester.pump();

      // Offline banner shows the sync message
      expect(
        find.textContaining("You're offline"),
        findsOneWidget,
      );
    });

    testWidgets('hides banner when online', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityProvider.overrideWith(
              (ref) => ConnectivityNotifier()..setOnline(),
            ),
          ],
          child: MaterialApp(theme: AppTheme.lightTheme,
            home: Scaffold(body: OfflineBanner()),
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
        MaterialApp(theme: AppTheme.lightTheme,
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
        MaterialApp(theme: AppTheme.lightTheme,
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
        MaterialApp(theme: AppTheme.lightTheme,
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


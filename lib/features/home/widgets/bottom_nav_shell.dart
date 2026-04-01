import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../features/settings/screens/profile_screen.dart';
import '../../../shared/widgets/grain_overlay.dart';
import '../keys/home_keys.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Bottom navigation shell for the home dashboard.
///
/// Wraps the dashboard content in a 4-tab bottom navigation bar:
/// Groups, Activity, Chats, Profile.
///
/// The Groups tab (index 0) shows the provided [child] widget.
/// All other tabs show a [_PlaceholderTab] with "Coming soon".
///
/// Uses Stack + AnimatedOpacity for M3 FadeThrough tab switching while
/// preserving all tab widget state (Phase 22 P03, D-07).
/// IgnorePointer prevents interaction with invisible tabs.
///
/// NOTE: GoRouter is NOT used for tab navigation per RESEARCH Pitfall 3.
/// Phase 19 will wire real GoRouter routes for non-Groups tabs.
class BottomNavShell extends StatefulWidget {
  /// The dashboard content shown on the Groups tab.
  final Widget child;

  /// Optional key forwarded to the inner [Scaffold] for widget testing.
  final Key? scaffoldKey;

  const BottomNavShell({super.key, required this.child, this.scaffoldKey});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: AppColorTokens.light.scaffoldBackground,
      body: _buildBody(),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildBody() {
    final tabs = [
      widget.child,
      const _PlaceholderTab(),
      const _PlaceholderTab(),
      const ProfileScreen(),  // Tab 3: Profile (Phase 25)
    ];
    return GrainOverlay(
      opacity: 0.035,
      child: Stack(
        children: List.generate(tabs.length, (index) {
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            opacity: index == _currentIndex ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: index != _currentIndex,
              child: tabs[index],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      backgroundColor: AppColorTokens.light.bottomNavBackground,
      selectedItemColor: AppColorTokens.light.bottomNavActiveIcon,
      unselectedItemColor: AppColorTokens.light.bottomNavInactiveIcon,
      // REQUIRED for 4 tabs: fixed type shows all labels (RESEARCH Pitfall 3)
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Iconsax.people, key: HomeKeys.bottomNavGroups),
          label: 'Groups',
        ),
        BottomNavigationBarItem(
          icon: Icon(Iconsax.activity, key: HomeKeys.bottomNavActivity),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: Icon(Iconsax.message, key: HomeKeys.bottomNavChats),
          label: 'Chats',
        ),
        BottomNavigationBarItem(
          icon: Icon(Iconsax.profile_circle, key: HomeKeys.bottomNavProfile),
          label: 'Profile',
        ),
      ],
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Coming soon',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColorTokens.light.textSecondary,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../keys/home_keys.dart';

/// Bottom navigation shell for the home dashboard.
///
/// Wraps the dashboard content in a 4-tab bottom navigation bar:
/// Groups, Activity, Chats, Profile.
///
/// The Groups tab (index 0) shows the provided [child] widget.
/// All other tabs show a [_PlaceholderTab] with "Coming soon".
///
/// Uses [IndexedStack] to preserve scroll state of the Groups tab.
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
      backgroundColor: AppColors.background,
      body: _buildBody(),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        widget.child,
        const _PlaceholderTab(),
        const _PlaceholderTab(),
        const _PlaceholderTab(),
      ],
    );
  }

  Widget _buildNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      backgroundColor: AppColors.bottomNavBackground,
      selectedItemColor: AppColors.bottomNavActiveIcon,
      unselectedItemColor: AppColors.bottomNavInactiveIcon,
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
    return const Center(
      child: Text(
        'Coming soon',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

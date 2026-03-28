import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../keys/onboarding_keys.dart';

/// Onboarding screen shown to first-time users
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Key used to track onboarding completion
  static const String completedKey = 'onboarding_complete';

  /// Check if onboarding has been completed
  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  /// Mark onboarding as completed
  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPageData> _pages = [
    _OnboardingPageData(
      icon: Iconsax.routing_2,
      title: 'Every journey\nstarts here',
      subtitle:
          'Plan trips with your crew. Split costs, pack gear, share moments — all in one place.',
      accentColor: AppColors.primary,
      backgroundIcon: Iconsax.map_1,
    ),
    _OnboardingPageData(
      icon: Iconsax.people,
      title: 'Travel is better\ntogether',
      subtitle:
          'Invite friends with a code. Everyone sees expenses, gear lists, and documents in real time.',
      accentColor: AppColors.sky,
      backgroundIcon: Iconsax.global,
    ),
    _OnboardingPageData(
      icon: Iconsax.camera,
      title: 'Capture the\nmoments',
      subtitle:
          'Share photos, settle debts instantly, and keep every memory from every adventure.',
      accentColor: AppColors.amber,
      backgroundIcon: Iconsax.gallery,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _completeOnboarding() async {
    await OnboardingScreen.markCompleted();
    if (mounted) {
      context.go('/home');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: OnboardingKeys.screen,
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Animated background
          _buildBackground(),

          // Page content
          SafeArea(
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, top: 12),
                    child: TextButton(
                      onPressed: _completeOnboarding,
                      child: Text(
                        _currentPage < _pages.length - 1 ? 'Skip' : '',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),

                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      return _buildPage(_pages[index], index);
                    },
                  ),
                ),

                // Bottom controls
                _buildBottomControls(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final page = _pages[_currentPage];
    return Stack(
      children: [
        // Dark gradient base
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
        ),
        // Accent blob
        AnimatedPositioned(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          top: _currentPage * -30.0 - 80,
          right: _currentPage * 20.0 - 100,
          child: Container(
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              color: page.accentColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        // Secondary blob
        AnimatedPositioned(
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeOutCubic,
          bottom: -60 + (_currentPage * 30.0),
          left: -80 + (_currentPage * -20.0),
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: const Color(0xFF334155).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPage(_OnboardingPageData data, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Large icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  data.accentColor,
                  data.accentColor.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: data.accentColor.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Icon(data.icon, size: 56, color: Colors.black),
          )
              .animate(key: ValueKey('icon_$index'))
              .fadeIn(duration: 600.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                curve: Curves.easeOutBack,
              ),

          const Spacer(),

          // Title
          Text(
            data.title,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.5,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('title_$index'))
              .fadeIn(delay: 200.ms, duration: 500.ms)
              .slideY(begin: 0.15, end: 0),

          const SizedBox(height: 20),

          // Subtitle
          Text(
            data.subtitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          )
              .animate(key: ValueKey('subtitle_$index'))
              .fadeIn(delay: 400.ms, duration: 500.ms)
              .slideY(begin: 0.1, end: 0),

          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final isLastPage = _currentPage == _pages.length - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // Page indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (index) {
              final isActive = index == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 32 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive
                      ? _pages[_currentPage].accentColor
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 40),

          // CTA button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _pages[_currentPage].accentColor,
                    _pages[_currentPage].accentColor.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _pages[_currentPage]
                        .accentColor
                        .withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLastPage ? 'Get Started' : 'Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      isLastPage ? Iconsax.arrow_right_1 : Iconsax.arrow_right_3,
                      size: 20,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final IconData backgroundIcon;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.backgroundIcon,
  });
}

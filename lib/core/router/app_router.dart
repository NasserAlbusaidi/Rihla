import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/trip/screens/create_trip_screen.dart';
import '../../features/trip/screens/join_trip_screen.dart';

/// Listenable that notifies GoRouter when auth state changes
/// without recreating the entire router
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen<AsyncValue<User?>>(authStateProvider, (_, __) {
      notifyListeners();
    });
  }
}

final _authNotifierProvider = Provider<_AuthNotifier>((ref) {
  return _AuthNotifier(ref);
});

/// Route names for type-safe navigation
class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String home = '/home';
  static const String createTrip = '/create-trip';
  static const String joinTrip = '/join-trip';
  static const String tripDetail = '/trip/:tripId';
  static const String settings = '/settings';
}

/// Provider to track onboarding completion state
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  return await OnboardingScreen.isCompleted();
});

/// Router provider with auth-aware redirects
/// Uses refreshListenable to re-evaluate redirects without recreating the router
final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(_authNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final isLoggedIn = ref.read(authStateProvider).valueOrNull != null;
      final isLoggingIn = state.matchedLocation == AppRoutes.login;
      final isForgotPw = state.matchedLocation == AppRoutes.forgotPassword;
      final isResetPw = state.matchedLocation == AppRoutes.resetPassword;
      final isOnboarding = state.matchedLocation == AppRoutes.onboarding;
      final isSplash = state.matchedLocation == AppRoutes.splash;
      final onboardingDone = ref.read(onboardingCompleteProvider).valueOrNull ?? false;

      // If on splash, redirect based on onboarding + auth state
      if (isSplash) {
        if (!onboardingDone) return AppRoutes.onboarding;
        return isLoggedIn ? AppRoutes.home : AppRoutes.login;
      }

      // Allow onboarding screen
      if (isOnboarding) return null;

      // If not logged in and not on an auth page, redirect to login
      if (!isLoggedIn && !isLoggingIn && !isForgotPw && !isResetPw) {
        return AppRoutes.login;
      }

      // If logged in and on login page, redirect to home
      if (isLoggedIn && isLoggingIn) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      // Splash - auto-redirects based on auth
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Auth
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      // Home / Trip List
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Create Trip
      GoRoute(
        path: AppRoutes.createTrip,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CreateTripScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),

      // Join Trip
      GoRoute(
        path: AppRoutes.joinTrip,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const JoinTripScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),

      // Settings
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            );
          },
        ),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});

/// Splash screen that auto-redirects — branded loading
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF13EC92), Color(0xFF0BAE6B)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF13EC92).withAlpha(100),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(Icons.explore_rounded, size: 40, color: Colors.black),
            ),
            const SizedBox(height: 24),
            const Text(
              'Rihla',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF13EC92),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

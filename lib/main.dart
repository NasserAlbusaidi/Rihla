import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/firebase_config.dart';
import 'core/models/app_settings_model.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/app_bootstrap_provider.dart';
import 'core/providers/settings_provider.dart';
import '../../core/theme/tokens/color_tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.tracesSampleRate = 0.2;
      // ignore: experimental_member_use
      options.profilesSampleRate = 0.1;
    },
    appRunner: () async {
      // Initialize Firebase (includes Firestore offline persistence settings)
      await FirebaseConfig.initialize();

      // Initialize SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // Set system UI overlay style for light theme
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColorTokens.light.scaffoldBackground,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      // Set preferred orientations
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      runApp(
        DefaultAssetBundle(
          bundle: SentryAssetBundle(),
          child: ProviderScope(
            overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
            child: const _AuthGate(),
          ),
        ),
      );
    },
  );
}

/// Gates the app on successful Firebase anonymous auth.
///
/// Shows a retry screen if auth fails instead of crashing.
/// On success, renders [SafarApp]. On retry success, transitions seamlessly.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<void> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = FirebaseConfig.ensureAnonymousSession();
  }

  void _retry() {
    setState(() {
      _authFuture = FirebaseConfig.ensureAnonymousSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          Sentry.captureException(
            snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return _AuthRetryScreen(onRetry: _retry);
        }
        return const SafarApp();
      },
    );
  }
}

/// Minimal retry screen shown when Firebase anonymous auth fails.
class _AuthRetryScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const _AuthRetryScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    const colors = AppColorTokens.light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: colors.scaffoldBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 64, color: colors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Unable to connect. Check your internet and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Main application widget
class SafarApp extends ConsumerWidget {
  const SafarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    // Activate bootstrap listeners (notification sync, etc.)
    ref.watch(appBootstrapProvider);

    return _SystemChromeThemeSync(
      child: MaterialApp.router(
        title: 'Rihla',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: settings.themeMode.toMaterialThemeMode(),
        routerConfig: router,
      ),
    );
  }
}

/// Keeps the OS status-bar + navigation-bar overlay in sync with the active
/// app theme (resolves `AppThemeMode.system` against the platform brightness).
///
/// Inserted inside [SafarApp.build] AFTER `settingsProvider` is read so a
/// theme change triggers a rebuild that repaints the overlay. The initial
/// `SystemChrome.setSystemUIOverlayStyle` call in `main()` remains a
/// first-paint light default covering pre-hydration (auth/bootstrap).
class _SystemChromeThemeSync extends ConsumerWidget {
  const _SystemChromeThemeSync({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final platform = MediaQuery.platformBrightnessOf(context);
    final effective = switch (mode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => platform,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // design-token-justified: SystemChrome overlay must resolve both brightness variants before widget tree builds
      final darkStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        // design-token-justified: SystemChrome overlay must resolve both brightness variants before widget tree builds
        systemNavigationBarColor: AppColorTokens.dark.scaffoldBackground,
        systemNavigationBarIconBrightness: Brightness.light,
      );
      // design-token-justified: SystemChrome overlay must resolve both brightness variants before widget tree builds
      final lightStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        // design-token-justified: SystemChrome overlay must resolve both brightness variants before widget tree builds
        systemNavigationBarColor: AppColorTokens.light.scaffoldBackground,
        systemNavigationBarIconBrightness: Brightness.dark,
      );
      SystemChrome.setSystemUIOverlayStyle(
        effective == Brightness.dark ? darkStyle : lightStyle,
      );
    });
    return child;
  }
}

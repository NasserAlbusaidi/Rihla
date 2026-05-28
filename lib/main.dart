import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/firebase_config.dart';
import 'core/models/app_settings_model.dart';
import 'core/router/app_router.dart';
import 'core/screens/splash_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/app_bootstrap_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/local_database.dart';
import 'core/theme/tokens/color_tokens.dart';
import 'core/services/app_messenger.dart';
import 'core/services/deep_link_service.dart';
import 'features/auth/services/cold_start_cache_barrier.dart';
import 'l10n/generated/app_localizations.dart';

/// Compile-time toggle: point all Firebase SDKs at the local emulator suite.
///
/// Reads from `--dart-define-from-file=config.json`. Production builds MUST
/// omit this key (or set it to `false`) — the value is baked into the binary
/// and cannot be flipped at runtime (T-38-13 mitigation).
const bool _useFirebaseEmulator = bool.fromEnvironment(
  'USE_FIREBASE_EMULATOR',
  defaultValue: false,
);

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
      await FirebaseConfig.initialize(
        useDebugAppCheck: !kReleaseMode || _useFirebaseEmulator,
      );

      // Emulator hookup MUST run AFTER Firebase.initializeApp and BEFORE any
      // service construction or auth call (Pitfall 2 in 38-RESEARCH.md).
      if (_useFirebaseEmulator) {
        // Android emulator maps host's localhost to 10.0.2.2; other platforms use localhost.
        final host = !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';
        FirebaseAuth.instance.useAuthEmulator(host, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
        FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).useFunctionsEmulator(host, 5001);
        if (kDebugMode) {
          debugPrint(
            'Firebase emulators ON host=$host (auth:9099 firestore:8080 functions:5001)',
          );
        }
      }

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
            child: _AuthGate(prefs: prefs),
          ),
        ),
      );
    },
  );
}

/// Gates the app on successful Firebase anonymous auth AND the cold-start
/// cache barrier (issue #45).
///
/// Shows a retry screen if either step fails instead of crashing. On success,
/// renders [SafarApp]. The barrier runs strictly after [FirebaseConfig.ensureAnonymousSession]
/// resolves and strictly before [SafarApp] mounts, which is what guarantees no
/// cache repo or `asyncMap` side-write executes against the previous identity.
class _AuthGate extends StatefulWidget {
  const _AuthGate({required this.prefs});

  final SharedPreferences prefs;

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late Future<void> _authFuture;

  @override
  void initState() {
    super.initState();
    _authFuture = _bootSequence();
  }

  Future<void> _bootSequence() async {
    await FirebaseConfig.ensureAnonymousSession();
    await runColdStartCacheBarrier(
      prefs: widget.prefs,
      currentUid: FirebaseConfig.auth.currentUser?.uid,
      cacheFileExists: LocalDatabase.cacheFileExists,
      wipe: LocalDatabase.wipeAndReinitialize,
    );
  }

  void _retry() {
    setState(() {
      _authFuture = _bootSequence();
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
            home: const SplashScreen(),
          );
        }
        if (snapshot.hasError) {
          Sentry.captureException(
            snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: SplashScreen(hasError: true, onRetry: _retry),
          );
        }
        return const SafarApp();
      },
    );
  }
}

/// Main application widget
class SafarApp extends ConsumerStatefulWidget {
  const SafarApp({super.key});

  @override
  ConsumerState<SafarApp> createState() => _SafarAppState();
}

class _SafarAppState extends ConsumerState<SafarApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(DeepLinkService.instance.init(ref.read(routerProvider)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    // Activate bootstrap listeners (notification sync, etc.)
    ref.watch(appBootstrapProvider);

    return _SystemChromeThemeSync(
      child: MaterialApp.router(
        title: 'Rihla',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: appMessengerKey,
        locale: ref.watch(localeProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

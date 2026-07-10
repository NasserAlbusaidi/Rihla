import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'core/theme/font_bootstrap.dart';
import 'core/theme/system_chrome_theme_sync.dart';
import 'core/providers/app_bootstrap_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/theme/tokens/color_tokens.dart';
import 'core/services/app_messenger.dart';
import 'core/services/cache_isolation_controller.dart';
import 'core/services/cold_start_coordinator.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/install_referrer_service.dart';
import 'core/utils/sentry_pii_scrubber.dart';
import 'features/auth/providers/cache_isolation_controller_provider.dart';
import 'features/auth/services/auth_email_link_recognizer.dart';
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

/// Background/terminated FCM handler (#53). Runs in a separate isolate. The
/// server sends a `notification` payload, so the OS renders the tray
/// notification itself and the tap is routed via `onMessageOpenedApp` /
/// `getInitialMessage` once the app is foregrounded — this handler only needs
/// to exist so FCM also delivers any accompanying `data`. It must touch no
/// app state (the isolate has none); keep it a no-op.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Brand fonts are bundled assets; disable google_fonts CDN fetching and
  // register their OFL licenses (#103).
  configureBundledFonts();

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.tracesSampleRate = 0.2;
      // ignore: experimental_member_use
      options.profilesSampleRate = 0.1;
      // PII protection (#968): never attach the SDK's default PII, and route
      // every outgoing event through the central email scrubber.
      options.sendDefaultPii = false;
      options.beforeSend = (event, hint) => scrubSentryPii(event);
    },
    appRunner: () async {
      // Initialize Firebase (includes Firestore offline persistence settings)
      await FirebaseConfig.initialize(
        useDebugAppCheck: !kReleaseMode || _useFirebaseEmulator,
      );

      // Register the FCM background handler before runApp (#53). Must be after
      // Firebase init and reference a top-level entry-point function.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Emulator hookup MUST run AFTER Firebase.initializeApp and BEFORE any
      // service construction or auth call (Pitfall 2 in 38-RESEARCH.md).
      if (_useFirebaseEmulator) {
        // Android emulator maps host's localhost to 10.0.2.2; other platforms use localhost.
        final host = !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';
        await FirebaseAuth.instance.useAuthEmulator(host, 9099);
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

  /// The last boot error reported to Sentry (#838). The [FutureBuilder]
  /// builder re-runs on every rebuild while `snapshot.hasError` stays true
  /// (e.g. locale/theme changes), so capture is de-duped by identity rather
  /// than re-firing per rebuild.
  Object? _lastReported;

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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SplashScreen(),
          );
        }
        if (snapshot.hasError) {
          if (!identical(snapshot.error, _lastReported)) {
            _lastReported = snapshot.error;
            Sentry.captureException(
              snapshot.error,
              stackTrace: snapshot.stackTrace,
            );
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SplashScreen(
              hasError: true,
              error: snapshot.error,
              onRetry: _retry,
            ),
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
      // An in-session UID swap is restarting the app — don't build the router
      // or start deep-link handling; the cold boot will do it fresh (#45).
      if (ref.read(cacheIsolationProvider)) return;
      final router = ref.read(routerProvider);
      final prefs = ref.read(sharedPreferencesProvider);
      unawaited(
        runColdStartCoordinator(
          resolveDeepLinks: () => DeepLinkService.instance.init(
            router,
            suppressInstallReferrerFor: isRecognizedAuthEmailLink,
          ),
          consumeInstallReferrer: ({required route}) => InstallReferrerService
              .instance
              .consumeDeferredInvite(router, prefs, route: route),
          activateAppBootstrap: () async {
            if (!mounted) return;
            ref.read(appBootstrapProvider);
          },
          runInitialNotificationSync: ({required handleInitialMessage}) async {
            if (!mounted) return;
            kickInitialNotificationSync(
              ref,
              handleInitialMessage: handleInitialMessage,
            );
          },
          onStepError: (error, stack) =>
              Sentry.captureException(error, stackTrace: stack),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Cache-isolation overlay (#45): once an in-session UID swap engages
    // isolation, cover the whole app BEFORE reading router/settings/bootstrap,
    // so no cached financials from the outgoing UID can render during the swap
    // → restart window. Read FIRST (R3 P2-1 ordering).
    if (ref.watch(cacheIsolationProvider)) {
      return const _CacheIsolationApp();
    }

    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    return SystemChromeThemeSync(
      child: MaterialApp.router(
        title: 'Rihla',
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(maxScaleFactor: 1.5),
            ),
            child: child!,
          );
        },
        // Activates a RootRestorationScope so list scroll offsets (and other
        // RestorableState) survive Android process death. Without this, every
        // `restorationId` on a scrollable below is a no-op (#362).
        restorationScopeId: 'rihla',
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

/// Opaque cover shown while an in-session UID swap restarts the app (#45).
///
/// Reuses [SplashScreen] so this brief pre-restart cover is visually identical
/// to the cold boot that immediately follows, and so no cached financials from
/// the outgoing UID can paint during the swap window.
///
/// A `restart()` is expected within moments. If it fails (the channel is absent
/// or threw — flagged via [cacheIsolationRestartFailedProvider]) or silently
/// no-ops past [_restartWatchdog], the cover swaps to a manual restart
/// affordance so the overlay can never strand the user with no escape
/// (#45 §6.3). The dirty flag was persisted before the swap, so a cold boot
/// from a manual relaunch still clears the outgoing UID's cache.
class _CacheIsolationApp extends ConsumerStatefulWidget {
  const _CacheIsolationApp();

  @override
  ConsumerState<_CacheIsolationApp> createState() => _CacheIsolationAppState();
}

class _CacheIsolationAppState extends ConsumerState<_CacheIsolationApp> {
  static const _restartWatchdog = Duration(seconds: 6);
  Timer? _watchdog;
  bool _watchdogElapsed = false;

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(_restartWatchdog, () {
      if (mounted) setState(() => _watchdogElapsed = true);
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restartFailed = ref.watch(cacheIsolationRestartFailedProvider);
    final showManualRestart = restartFailed || _watchdogElapsed;
    // iOS has no native handler on the restart channel, so a retry can never
    // succeed there — show manual close-and-reopen instructions instead (#946).
    final iosManualRestart =
        showManualRestart && defaultTargetPlatform == TargetPlatform.iOS;
    Locale? locale;
    try {
      locale = ref.watch(localeProvider);
    } catch (_) {
      // Prefs unavailable — fall back to system-locale resolution rather than
      // stranding the overlay on a throw (#946 Gate P2).
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: iosManualRestart
          ? const SplashScreen(
              key: Key('cache-isolation-manual-restart'),
              hasError: true,
              manualRestartRequired: true,
            )
          : showManualRestart
              ? SplashScreen(
                  key: const Key('cache-isolation-restart'),
                  hasError: true,
                  onRetry: () {
                    // Re-attempt the native restart. Clear the failed flag
                    // first so a fresh failure can re-trigger the affordance.
                    ref
                        .read(cacheIsolationRestartFailedProvider.notifier)
                        .state = false;
                    unawaited(
                      ref.read(cacheIsolationControllerProvider).restart(),
                    );
                  },
                )
              : const SplashScreen(key: Key('cache-isolation-overlay')),
    );
  }
}

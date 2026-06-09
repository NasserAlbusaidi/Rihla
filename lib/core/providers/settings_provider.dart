import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/generated/app_localizations.dart';
import '../config/firebase_config.dart';
import '../models/app_settings_model.dart';
import '../models/split_mode.dart';
import '../services/settings_service.dart';
import '../utils/name_validators.dart';

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

/// Provider for SettingsService
final settingsServiceProvider = Provider<SettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsService(prefs);
});

/// Notifier to manage global application settings
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _service;

  SettingsNotifier(this._service, {String? deviceLanguageCode})
    : super(_service.loadSettings(deviceLanguageCode: deviceLanguageCode));

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _service.saveThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLanguage(String languageCode) async {
    await _service.saveLanguage(languageCode);
    state = state.copyWith(languageCode: languageCode);
  }

  Future<void> setCurrency(String currencyCode) async {
    await _service.saveCurrency(currencyCode);
    state = state.copyWith(currencyCode: currencyCode);
  }

  Future<void> setPushNotificationsEnabled(bool enabled) async {
    await _service.savePushNotificationsEnabled(enabled);
    state = state.copyWith(pushNotificationsEnabled: enabled);
  }

  /// Records that the natural-moment notification-permission prompt has been
  /// shown, so it fires exactly once across the app's lifetime (#288).
  Future<void> setNotificationPromptSeen(bool seen) async {
    await _service.saveNotificationPromptSeen(seen);
    state = state.copyWith(notificationPromptSeen: seen);
  }

  Future<void> setWeeklyDigestEnabled(bool enabled) async {
    await _service.saveWeeklyDigestEnabled(enabled);
    state = state.copyWith(weeklyDigestEnabled: enabled);
  }

  /// Persists the legacy onboarding-complete flag.
  ///
  /// The shippable v1 router no longer gates launch on this flag, but it is
  /// retained so existing installs and the archived onboarding screen can read
  /// their previous state without a settings migration.
  Future<void> setOnboardingComplete(bool complete) async {
    await _service.saveOnboardingComplete(complete);
    state = state.copyWith(onboardingComplete: complete);
  }

  /// Stores the user's preferred default split mode for new expenses.
  /// Only [SplitMode.equally] is functional today; the picker prevents
  /// selecting locked modes (`SplitMode.isAvailable`).
  Future<void> setDefaultSplitMode(SplitMode mode) async {
    await _service.saveDefaultSplitMode(mode);
    state = state.copyWith(defaultSplitMode: mode);
  }

  /// Updates the device name in SharedPreferences and state, then
  /// fire-and-forgets a Firestore batch propagation to all group member
  /// records (D-14, D-15, D-16).
  ///
  /// SharedPreferences write is awaited (D-16: local-first).
  /// Firestore propagation is unawaited with a try/catch (D-15: silent fail).
  Future<void> setDeviceName(String name) async {
    final normalized = name.trim().isEmpty ? '' : normalizeDisplayName(name);
    if (name.trim().isNotEmpty) {
      final error = validateDisplayName(name);
      if (error != null) {
        throw ArgumentError.value(name, 'name', error);
      }
      // #390: reject a rename that would collide with another live member in
      // ANY group the user belongs to (all-or-nothing). Throws
      // DisplayNameTakenException BEFORE persisting/propagating.
      await _ensureDisplayNameAvailable(normalized);
    }

    await _service.saveDeviceName(normalized); // SharedPreferences first (D-16)
    state = state.copyWith(deviceName: normalized); // Update state immediately
    if (normalized.isNotEmpty) {
      // Fire-and-forget Firestore (D-15)
      unawaited(propagateDisplayName(normalized));
    }
  }

  /// Throws [DisplayNameTakenException] if [normalized] collides with another
  /// live member in any group the current user belongs to (#390).
  ///
  /// Reads `FirebaseConfig.currentUser` / `FirebaseConfig.firestore` (same as
  /// [propagateDisplayName]); the renamer is a member of these groups so the
  /// roster read is permitted. The `currentUser` read is INSIDE the `try` on
  /// purpose: with no Firebase app initialized (unit tests) it throws
  /// `[core/no-app]`, which `catch (_)` swallows → fail-open. Fail-OPEN on ANY
  /// read error (offline cold cache / transient / no-Firebase-app): a rename is
  /// never blocked by a failed read — the #279 join guard is the authoritative
  /// collision boundary and the #196/#289 disambiguator is the display backstop.
  /// A real collision ([DisplayNameTakenException]) is always rethrown.
  Future<void> _ensureDisplayNameAvailable(String normalized) async {
    try {
      final uid = FirebaseConfig.currentUser?.uid;
      if (uid == null) return; // genuinely unauthenticated — nothing to check

      final db = FirebaseConfig.firestore;
      final groupsSnap = await db
          .collection('groups')
          .where('memberIds', arrayContains: uid)
          .get();

      for (final groupDoc in groupsSnap.docs) {
        final membersSnap = await db
            .collection('groups')
            .doc(groupDoc.id)
            .collection('members')
            .get();

        final collides = nameCollidesInDocs(
          candidate: normalized,
          selfUid: uid,
          memberDocs: membersSnap.docs.map((d) => d.data()),
        );
        if (collides) {
          final groupName = (groupDoc.data()['name'] as String?) ?? '';
          throw DisplayNameTakenException(groupName);
        }
      }
    } on DisplayNameTakenException {
      rethrow; // a real collision is a real rejection
    } catch (_) {
      return; // fail-open: read failure / offline cold cache / no Firebase app
    }
  }

  /// Propagates the new display name to all group participant records in
  /// Firestore where the current user is a member.
  ///
  /// Silently catches all errors — offline persistence handles retry.
  /// This method is package-private for testability but should not be
  /// called directly; use [setDeviceName] instead.
  Future<void> propagateDisplayName(String displayName) async {
    try {
      final uid = FirebaseConfig.currentUser?.uid;
      if (uid == null) return;

      final db = FirebaseConfig.firestore;

      // Find all groups the current user belongs to
      final groupsSnap = await db
          .collection('groups')
          .where('memberIds', arrayContains: uid)
          .get();

      final batch = db.batch();
      for (final groupDoc in groupsSnap.docs) {
        // Find the user's member document in this group
        final membersSnap = await db
            .collection('groups')
            .doc(groupDoc.id)
            .collection('members')
            .where('userId', isEqualTo: uid)
            .get();

        for (final memberDoc in membersSnap.docs) {
          batch.update(memberDoc.reference, {'displayName': displayName});
        }
      }
      await batch.commit();
    } catch (_) {
      // Silently fail per D-15 — Firestore offline persistence handles retry
    }
  }
}

/// Device locales in the user's platform-preference order.
///
/// Defaults to the OS-reported list; overridable in tests to make first-run
/// locale seeding deterministic regardless of the host machine's locale.
final deviceLocalesProvider = Provider<List<Locale>>(
  (ref) => PlatformDispatcher.instance.locales,
);

/// Returns the first [deviceLocales] entry whose `languageCode` the app
/// supports (region subtag ignored), or null when none match — in which case
/// the caller falls back to the default language. (#286)
String? resolveSupportedLanguageCode(
  List<Locale> deviceLocales,
  Iterable<Locale> supportedLocales,
) {
  final supported = supportedLocales.map((l) => l.languageCode).toSet();
  for (final locale in deviceLocales) {
    if (supported.contains(locale.languageCode)) return locale.languageCode;
  }
  return null;
}

/// Provider for SettingsNotifier
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final service = ref.watch(settingsServiceProvider);
  final deviceLanguageCode = resolveSupportedLanguageCode(
    ref.watch(deviceLocalesProvider),
    AppLocalizations.supportedLocales,
  );
  return SettingsNotifier(service, deviceLanguageCode: deviceLanguageCode);
});

/// Locale derived from [settingsProvider]'s `languageCode`.
///
/// Pass into `MaterialApp.locale`. Reuses the existing `languageCode` field on
/// [AppSettings] — there is no separate `localeCode`.
final localeProvider = Provider<Locale>((ref) {
  final code = ref.watch(
    settingsProvider.select((s) => s.languageCode),
  );
  return Locale(code);
});

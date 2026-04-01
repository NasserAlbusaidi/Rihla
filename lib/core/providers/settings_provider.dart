import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/firebase_config.dart';
import '../models/app_settings_model.dart';
import '../services/settings_service.dart';

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

  SettingsNotifier(this._service) : super(_service.loadSettings());

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

  /// Updates the device name in SharedPreferences and state, then
  /// fire-and-forgets a Firestore batch propagation to all group member
  /// records (D-14, D-15, D-16).
  ///
  /// SharedPreferences write is awaited (D-16: local-first).
  /// Firestore propagation is unawaited with a try/catch (D-15: silent fail).
  Future<void> setDeviceName(String name) async {
    await _service.saveDeviceName(name); // SharedPreferences first (D-16)
    state = state.copyWith(deviceName: name); // Update state immediately
    unawaited(propagateDisplayName(name)); // Fire-and-forget Firestore (D-15)
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

/// Provider for SettingsNotifier
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final service = ref.watch(settingsServiceProvider);
  return SettingsNotifier(service);
});

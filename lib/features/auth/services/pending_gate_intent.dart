import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-flight create form state persisted across the forced restart of a
/// gate-conflict discard-shell restore (#428, re-architecture mitigation 5).
///
/// Written by the gate sheet immediately BEFORE `restoreWithGoogle` (which
/// ends in a guaranteed process restart), replayed on the next cold boot by
/// `GateIntentReplay` (navigation only), and consumed one-shot by the
/// CreateGroupScreen's prefill (which clears it). Replay never auto-submits —
/// the user always taps the final create button, so marker data passes the
/// same submit-time validation as typed input.
///
/// The `type` discriminator carries a single value today: join was un-gated in
/// #648 and its `join` intent type pruned in #655. It's retained for the next
/// gated flow.
@immutable
class PendingGateIntent {
  PendingGateIntent.create({
    required this.groupName,
    required this.displayName,
    required this.currencyCode,
    int? atMillis,
  }) : type = typeCreate,
       atMillis = atMillis ?? DateTime.now().millisecondsSinceEpoch;

  const PendingGateIntent._({
    required this.type,
    required this.atMillis,
    this.groupName,
    this.displayName,
    this.currencyCode,
  });

  static const String prefsKey = 'auth.pendingGateIntent';
  static const String typeCreate = 'create';
  static const Duration ttl = Duration(minutes: 30);
  static const int _version = 1;

  final String type;
  final String? groupName;
  final String? displayName;
  final String? currencyCode;
  final int atMillis;

  /// Guarded — a failed prefs write must never break the caller (the gate
  /// sheet calls this on the path to a guaranteed restart).
  static Future<void> save(
    SharedPreferences prefs,
    PendingGateIntent intent,
  ) async {
    try {
      await prefs.setString(
        prefsKey,
        jsonEncode({
          'v': _version,
          'type': intent.type,
          if (intent.groupName != null) 'groupName': intent.groupName,
          if (intent.displayName != null) 'displayName': intent.displayName,
          if (intent.currencyCode != null) 'currencyCode': intent.currencyCode,
          'atMillis': intent.atMillis,
        }),
      );
    } catch (_) {
      // Best-effort: losing the intent costs a re-typed form, never the flow.
    }
  }

  /// Null on missing, malformed, unknown-type, or TTL-expired markers.
  static PendingGateIntent? read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(prefsKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['type'];
      if (type != typeCreate) return null;
      final atMillis = decoded['atMillis'];
      if (atMillis is! int) return null;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(atMillis),
      );
      if (age > ttl) return null;
      return PendingGateIntent._(
        type: type as String,
        groupName: decoded['groupName'] as String?,
        displayName: decoded['displayName'] as String?,
        currencyCode: decoded['currencyCode'] as String?,
        atMillis: atMillis,
      );
    } catch (_) {
      return null;
    }
  }

  /// Guarded — clearing must never throw out of a screen's initState.
  static Future<void> clear(SharedPreferences prefs) async {
    try {
      await prefs.remove(prefsKey);
    } catch (_) {
      // Stale marker expires via TTL.
    }
  }
}

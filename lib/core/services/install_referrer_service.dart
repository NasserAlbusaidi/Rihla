import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InstallReferrerService {
  InstallReferrerService({
    Future<String?> Function()? readRawReferrer,
    bool Function()? isAndroid,
    this.nativeReadTimeout = const Duration(milliseconds: 750),
  }) : _readRawReferrer = readRawReferrer ?? _readFromChannel,
       _isAndroid = isAndroid ?? _defaultIsAndroid;

  static final InstallReferrerService instance = InstallReferrerService();

  static const String channelName = 'com.safar.safar/install_referrer';
  static const String methodName = 'getInstallReferrer';
  static const String consumedCodePrefsKey =
      'installReferrerInviteConsumedCode';
  static final RegExp _inviteCodePattern = RegExp(r'^[A-Z0-9]{6}$');
  static const MethodChannel _channel = MethodChannel(channelName);

  final Future<String?> Function() _readRawReferrer;
  final bool Function() _isAndroid;
  final Duration nativeReadTimeout;

  Future<bool> consumeDeferredInvite(
    GoRouter router,
    SharedPreferences prefs, {
    required bool route,
  }) async {
    if (!_isAndroid()) return false;

    final raw = await _readReferrerOrNull();
    if (raw == null || raw.isEmpty) return false;

    final code = parseInviteCode(raw);
    if (code == null) return false;
    if (prefs.getString(consumedCodePrefsKey) == code) return false;

    if (route) {
      router.go('/join/$code');
    }
    await prefs.setString(consumedCodePrefsKey, code);
    return route;
  }

  Future<String?> _readReferrerOrNull() async {
    try {
      return await Future.any<String?>([
        _readRawReferrer(),
        Future<String?>.delayed(nativeReadTimeout, () => null),
      ]);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String? parseInviteCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || _looksLikeAbsoluteUri(trimmed)) return null;

    final code =
        _singleCodeValue(trimmed) ??
        (trimmed.contains('%') ? _singleDecodedCodeValue(trimmed) : null);
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !_inviteCodePattern.hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  static String? _singleDecodedCodeValue(String raw) {
    try {
      final decoded = Uri.decodeQueryComponent(raw);
      if (_looksLikeAbsoluteUri(decoded)) return null;
      return _singleCodeValue(decoded);
    } catch (_) {
      return null;
    }
  }

  static String? _singleCodeValue(String rawQuery) {
    try {
      final values = Uri.parse(
        'rihla://install-referrer?$rawQuery',
      ).queryParametersAll['code'];
      if (values == null || values.length != 1) return null;
      return values.single;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeAbsoluteUri(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme;
  }

  static bool _defaultIsAndroid() {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static Future<String?> _readFromChannel() {
    return _channel.invokeMethod<String>(methodName);
  }
}

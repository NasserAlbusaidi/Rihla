import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class DeepLinkService {
  DeepLinkService._(this._appLinks);

  @visibleForTesting
  DeepLinkService.withAppLinks(this._appLinks);

  static final DeepLinkService instance = DeepLinkService._(AppLinks());
  static final RegExp _inviteCodePattern = RegExp(r'^[A-Z0-9]{6}$');
  static const Set<String> _universalJoinHosts = {
    'rihla-safar.web.app',
    'rihla-safar.firebaseapp.com',
  };

  final AppLinks _appLinks;
  // ignore: cancel_subscriptions, process-lifetime singleton listener
  StreamSubscription<Uri>? _subscription;

  Future<void> init(GoRouter router) async {
    if (_subscription != null) return;

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _openJoinLink(router, uri),
      onError: (Object error, StackTrace stackTrace) {
        _reportError(error, stackTrace);
      },
    );

    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        _openJoinLink(router, initialLink);
      }
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Uri? parseJoinLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();

    if (scheme == 'rihla') {
      return _normalizeJoinCode(_customSchemeInviteCode(uri));
    }

    if (scheme == 'https') {
      return _normalizeJoinCode(_universalLinkInviteCode(uri));
    }

    return null;
  }

  void _openJoinLink(GoRouter router, Uri uri) {
    final joinUri = parseJoinLink(uri);
    if (joinUri == null) return;

    router.go(joinUri.toString());
  }

  String? _customSchemeInviteCode(Uri uri) {
    if (uri.host.toLowerCase() != 'join') return null;

    final segments = _nonEmptyPathSegments(uri);
    if (segments.length == 1) return segments.first;
    if (segments.isEmpty) return uri.queryParameters['code'];

    return null;
  }

  String? _universalLinkInviteCode(Uri uri) {
    if (!_universalJoinHosts.contains(uri.host.toLowerCase())) return null;

    final segments = _nonEmptyPathSegments(uri);
    if (segments.length == 2 && segments.first.toLowerCase() == 'join') {
      return segments[1];
    }
    if (segments.length == 1 && segments.first.toLowerCase() == 'join') {
      return uri.queryParameters['code'];
    }

    return null;
  }

  List<String> _nonEmptyPathSegments(Uri uri) {
    return uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  }

  Uri? _normalizeJoinCode(String? code) {
    final normalized = code?.trim().toUpperCase();
    if (normalized == null || !_inviteCodePattern.hasMatch(normalized)) {
      return null;
    }

    return Uri(path: '/join/$normalized');
  }

  void _reportError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'deep_link_service',
      ),
    );
  }
}

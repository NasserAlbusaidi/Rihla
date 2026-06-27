import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class DeepLinkInitialDecision {
  const DeepLinkInitialDecision({
    required this.joinRouted,
    required this.suppressInstallReferrer,
  });

  final bool joinRouted;
  final bool suppressInstallReferrer;
}

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

  Future<DeepLinkInitialDecision> init(
    GoRouter router, {
    Duration initialStreamWindow = const Duration(milliseconds: 50),
    Duration initialLinkTimeout = const Duration(milliseconds: 250),
    bool Function(Uri uri) suppressInstallReferrerFor = _neverSuppress,
  }) async {
    if (_subscription != null) {
      return const DeepLinkInitialDecision(
        joinRouted: false,
        suppressInstallReferrer: false,
      );
    }

    var collectingInitialStream = true;
    var initialJoinRouted = false;
    var suppressInstallReferrer = false;
    final initialSeenKeys = <String>{};

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        if (collectingInitialStream && suppressInstallReferrerFor(uri)) {
          suppressInstallReferrer = true;
        }
        final routed = openJoinLink(
          router,
          uri,
          dedupeKeys: collectingInitialStream ? initialSeenKeys : null,
        );
        if (collectingInitialStream && routed) {
          initialJoinRouted = true;
          suppressInstallReferrer = true;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _reportError(error, stackTrace);
      },
    );

    Uri? initialLink;
    try {
      initialLink = await Future.any<Uri?>([
        _appLinks.getInitialLink(),
        Future<Uri?>.delayed(initialLinkTimeout, () => null),
      ]);
    } catch (error, stackTrace) {
      _reportError(error, stackTrace);
      initialLink = null;
    }

    if (initialLink != null) {
      if (suppressInstallReferrerFor(initialLink)) {
        suppressInstallReferrer = true;
      }
      final routed = openJoinLink(
        router,
        initialLink,
        dedupeKeys: initialSeenKeys,
      );
      if (routed) {
        initialJoinRouted = true;
        suppressInstallReferrer = true;
      }
    }

    await Future<void>.delayed(initialStreamWindow);
    collectingInitialStream = false;

    return DeepLinkInitialDecision(
      joinRouted: initialJoinRouted,
      suppressInstallReferrer: suppressInstallReferrer,
    );
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

  bool openJoinLink(GoRouter router, Uri uri, {Set<String>? dedupeKeys}) {
    final joinUri = parseJoinLink(uri);
    if (joinUri == null) return false;

    final target = joinUri.toString();
    if (dedupeKeys != null && !dedupeKeys.add(target)) return false;

    router.go(target);
    return true;
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

  static bool _neverSuppress(Uri uri) => false;
}

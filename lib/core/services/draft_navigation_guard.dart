import 'package:flutter/foundation.dart';

/// #1208: guards DECLARATIVE navigation (deep links, notification taps)
/// against silently destroying a dirty editor. PopScope only intercepts the
/// pop channel; router.go() disposes the current stack without any callback,
/// so injected navigation must ask first.
///
/// Editors register a confirm-callback while mounted (register in initState,
/// unregister in dispose). The callback returns true when navigation may
/// proceed (pristine editor, or user confirmed the discard).
class DraftNavigationGuard {
  DraftNavigationGuard._();
  static final DraftNavigationGuard instance = DraftNavigationGuard._();

  final List<Future<bool> Function()> _guards = [];
  bool _consultInFlight = false;

  void register(Future<bool> Function() guard) => _guards.add(guard);
  void unregister(Future<bool> Function() guard) => _guards.remove(guard);

  bool get hasGuards => _guards.isNotEmpty;

  /// True → caller may navigate. Consults the MOST RECENT guard (top-most
  /// editor). While a consult's dialog is showing, concurrent requests are
  /// refused (returns false) — the second deep link loses, the user's
  /// dialog wins.
  Future<bool> mayNavigate() async {
    if (_guards.isEmpty) return true;
    if (_consultInFlight) return false;
    _consultInFlight = true;
    try {
      return await _guards.last();
    } finally {
      _consultInFlight = false;
    }
  }

  @visibleForTesting
  void reset() {
    _guards.clear();
    _consultInFlight = false;
  }
}

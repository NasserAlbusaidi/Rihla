import 'dart:async';
import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';

/// PII-safe diagnostics seam for the email-link recovery flows.
///
/// The recover path ends in a native `System.exit(0)` restart that discards
/// in-flight async Sentry sends, so [captureFailure] (an immediate event) is
/// only reliable on the NON-restarting paths (send-link, link-email, bootstrap
/// dispatch) and on the post-boot failure surface. The restarting recover path
/// instead persists a durable marker (see `recovery_failure_notice.dart`) and
/// emits its authoritative event after the next cold boot.
///
/// Implementations must never log PII: no emails, raw UIDs, oobCodes, or raw
/// deep-link URLs. Callers pass [fingerprint]ed UIDs and error codes only.
abstract class RecoveryDiagnostics {
  void breadcrumb(String phase, {Map<String, Object?> data});

  void captureFailure(
    String phase, {
    required String code,
    Map<String, Object?> data,
  });

  /// Stable, non-reversible 8-hex fingerprint of a UID (FNV-1a, 32-bit).
  ///
  /// NOT a security control — it just lets two breadcrumbs about the same
  /// session be correlated without ever logging the raw UID.
  static String fingerprint(String uid) {
    const offsetBasis = 0x811c9dc5;
    const prime = 0x01000193;
    var hash = offsetBasis;
    for (final byte in utf8.encode(uid)) {
      hash ^= byte;
      hash = (hash * prime) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

/// Default implementation: Sentry breadcrumbs + captured messages.
///
/// All Sentry calls are fire-and-forget (`unawaited`) so diagnostics never
/// block — or fail — the recovery flow. When Sentry is uninitialized (unit
/// tests) the SDK calls are safe no-ops.
class SentryRecoveryDiagnostics implements RecoveryDiagnostics {
  const SentryRecoveryDiagnostics();

  @override
  void breadcrumb(String phase, {Map<String, Object?> data = const {}}) {
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: phase,
          category: 'auth.recovery',
          level: SentryLevel.info,
          data: Map<String, dynamic>.from(data),
        ),
      ),
    );
  }

  @override
  void captureFailure(
    String phase, {
    required String code,
    Map<String, Object?> data = const {},
  }) {
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: phase,
          category: 'auth.recovery',
          level: SentryLevel.error,
          data: <String, dynamic>{'code': code, ...data},
        ),
      ),
    );
    unawaited(
      Sentry.captureMessage(
        'Recovery failed: $phase ($code)',
        level: SentryLevel.error,
        withScope: (scope) {
          scope.setTag('recovery.phase', phase);
          scope.setTag('recovery.code', code);
        },
      ),
    );
  }
}

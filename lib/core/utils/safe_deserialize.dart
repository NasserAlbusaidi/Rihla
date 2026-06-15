import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Deserialize each Firestore doc with [decode], SKIPPING (and reporting) any
/// doc that throws, so one malformed row can't blank an entire list stream
/// (#532). A swallowed decode is a forward-compat signal — a wrong-type or
/// field-absent doc from a future migration / Admin tool / recovery copy — so
/// it is reported to Sentry rather than silently dropped.
///
/// The model factories are themselves total-parse (they salvage present-but-
/// malformed fields), so after them this only fires on a doc-level catastrophe
/// (a null `data()`, or a member with no valid `userId`) — exactly the docs the
/// server oracle also excludes, keeping client/server balances in lockstep.
List<T> decodeDocsSkippingMalformed<T>(
  Iterable<DocumentSnapshot> docs,
  T Function(DocumentSnapshot) decode, {
  required String context,
}) {
  final out = <T>[];
  for (final doc in docs) {
    try {
      out.add(decode(doc));
    } catch (e, st) {
      assert(() {
        debugPrint('[$context] skipped malformed doc ${doc.id}: $e');
        return true;
      }());
      unawaited(Sentry.captureException(e, stackTrace: st));
    }
  }
  return out;
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant 3-way parse of a Firestore date value: a `Timestamp`, an ISO
/// `String`, or anything else (#532). Returns `null` for an absent or
/// unparseable value — uses `DateTime.tryParse` (never `parse`) so a junk
/// String never throws and blanks the whole list stream.
DateTime? dateOrNull(Object? raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}

/// Like [dateOrNull] but for a REQUIRED date field: falls back to [fallback]
/// (default: now) for an absent/unparseable value, so deserialization of a
/// non-null doc never throws on the date. The fallback feeds display/sort only
/// — never money — so a synthesized timestamp can never change a balance.
DateTime dateOrNow(Object? raw, {DateTime? fallback}) =>
    dateOrNull(raw) ?? fallback ?? DateTime.now();

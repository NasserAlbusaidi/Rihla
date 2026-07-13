/// Validation helpers for user-entered display / group / event names.
///
/// Mirrors the server-side rules check `isValidDisplayName` in
/// `security/firestore.rules`: 1–32 characters after trim, no control
/// characters (U+0000–U+001F or U+007F), no bidi-control / zero-width format
/// characters ([kDisallowedFormatChars], #1216), and at least one visible
/// character (the invisible-name floor, [isInvisibleOnlyName]). Validating
/// client-side gives the user a friendly inline error instead of an opaque
/// `permission-denied` when the rules reject the write. The FREE-TEXT
/// validators below are deliberately NOT tightened — only names gain the
/// format-char + floor checks.
///
/// Length is counted in UTF-16 code units on BOTH sides: Dart `String.length`
/// here, and Firestore rules `string.size()` — which is UTF-16-based, NOT
/// code-point-based (verified against the rules emulator; #527 was filed on the
/// opposite assumption and refuted, pinned by
/// `functions/test/firestore-rules-publish-readiness.test.ts`). The two are
/// therefore already aligned; switching either to code points (`runes.length`)
/// would let the client accept astral-char names the server rejects. Don't.
library;

const int kDisplayNameMaxLength = 32;
const String _reservedFormerMemberSuffix =
    ' (former '
    'member)';

/// Bidi-control and zero-width format characters disallowed in display names
/// (the reject-set "K", #1216). RANGE-EXPANDED, one code point per `\u` escape
/// (never a `-` range) so the SAME constant can be enumerated code-point-by-
/// code-point by the full-K iteration test — a dropped char there is a failing
/// test. U+200C (ZWNJ) and U+200D (ZWJ) are DELIBERATELY ABSENT: they are
/// orthographically required in Persian/Kurdish and inside emoji ZWJ sequences
/// (joiners, not bidi controls; emoji/astral names are legal). Mirrored
/// byte-for-byte by `isValidDisplayName` in `security/firestore.rules` and by
/// the two Functions name validators (`shared/displayName.ts`,
/// `joinGroupByInviteCode.ts`). Free text is deliberately NOT tightened.
const String kDisallowedFormatChars =
    '\u00ad' // SOFT HYPHEN
    '\u200b' // ZERO WIDTH SPACE
    '\u200e' // LEFT-TO-RIGHT MARK
    '\u200f' // RIGHT-TO-LEFT MARK
    '\u202a\u202b\u202c\u202d\u202e' // LRE RLE PDF LRO RLO
    '\u2060\u2061\u2062\u2063\u2064' // WORD JOINER, invisible ops
    '\u2066\u2067\u2068\u2069' // LRI RLI FSI PDI
    '\ufeff'; // ZERO WIDTH NO-BREAK SPACE (BOM)

final RegExp _disallowedFormatChar = RegExp('[$kDisallowedFormatChars]');

/// True if [s] contains any C0 control character (U+0000–U+001F) or DEL
/// (U+007F). Allowing these in display names lets attackers smuggle
/// newlines into UI rendering and confuses downstream tooling
/// (logs, push notification bodies). Printable code points across non-Latin
/// scripts stay accepted; bidi/zero-width format chars are rejected separately
/// via [kDisallowedFormatChars] (#1216).
bool _hasControlChar(String s) {
  for (final cu in s.codeUnits) {
    if (cu < 0x20 || cu == 0x7F) return true;
  }
  return false;
}

/// True when [s] has NO visible character — every character is whitespace or a
/// ZWNJ/ZWJ joiner. The display-name "visible-char floor" (#1216): a name that
/// survives the [kDisallowedFormatChars] reject-set but still renders as nothing
/// (e.g. joiners plus spaces) must be rejected. ZWNJ (U+200C) and ZWJ (U+200D)
/// are stripped first (escapes, never raw joiners in source), then [String.trim]
/// removes whitespace; an empty remainder means the name is invisible-only.
bool isInvisibleOnlyName(String s) {
  return s.replaceAll(RegExp('[\u200c\u200d]'), '').trim().isEmpty;
}

enum DisplayNameValidationError {
  empty,
  tooLong,
  controlCharacter,
  reservedWording,
}

/// Returns the validation error for [input], or `null` if it is valid.
DisplayNameValidationError? displayNameValidationError(String? input) {
  final raw = input ?? '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return DisplayNameValidationError.empty;
  }
  // UTF-16 code units — matches the server's `string.size()` (#527). Don't switch
  // to runes.length; the client would then accept names the rules reject.
  if (trimmed.length > kDisplayNameMaxLength) {
    return DisplayNameValidationError.tooLong;
  }
  if (_hasControlChar(raw)) {
    return DisplayNameValidationError.controlCharacter;
  }
  // #1216: reject bidi-control / zero-width format chars. Runs on `raw`, NOT
  // `trimmed` — Dart `trim()` strips U+FEFF (it is Unicode White_Space + the
  // BOM Dart special-cases), so a trailing-BOM name would false-ACCEPT here
  // while the rules (gating the raw string) reject it — the exact
  // PERMISSION_DENIED this guards against. `_hasControlChar(raw)` above is the
  // same raw-not-trimmed precedent.
  if (_disallowedFormatChar.hasMatch(raw)) {
    return DisplayNameValidationError.controlCharacter;
  }
  // #1216 visible-char floor: reject a name that is only whitespace plus
  // ZWNJ/ZWJ joiners (whitespace-only already returned `empty` above).
  if (isInvisibleOnlyName(raw)) {
    return DisplayNameValidationError.controlCharacter;
  }
  if (trimmed.endsWith(_reservedFormerMemberSuffix)) {
    return DisplayNameValidationError.reservedWording;
  }
  return null;
}

/// Returns a user-facing English error message, or `null` if [input] is valid.
///
/// Suitable for direct use as a `TextFormField.validator` in non-localized
/// contexts. Localized widgets should use `validateDisplayNameLocalized`.
String? validateDisplayName(String? input) {
  return switch (displayNameValidationError(input)) {
    DisplayNameValidationError.empty => "Name can't be empty.",
    DisplayNameValidationError.tooLong =>
      'Keep it to $kDisplayNameMaxLength characters or fewer.',
    DisplayNameValidationError.controlCharacter =>
      'Remove line breaks or special characters.',
    DisplayNameValidationError.reservedWording =>
      'That name uses reserved wording.',
    null => null,
  };
}

/// Collapses runs of internal whitespace and trims edges. Use before
/// persisting — the validator does not normalize for you.
String normalizeDisplayName(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Max length for user free text (expense description/note, etc.).
///
/// Mirrors the server-side `validFreeText` check in `security/firestore.rules`
/// (#194): `value.size() <= 280`.
const int kFreeTextMaxLength = 280;

enum FreeTextValidationError { tooLong, controlCharacter }

/// Returns the validation error for free-text [input], or `null` if valid.
///
/// Mirrors the server `validFreeText` rule: empty is allowed (no minimum),
/// `<= 280` chars, and no C0/DEL control characters. The check runs on the
/// trimmed value because the write path persists `controller.text.trim()`
/// (empty becomes `null`), so the trimmed string is what the server validates.
FreeTextValidationError? freeTextValidationError(String? input) {
  final value = (input ?? '').trim();
  // UTF-16 code units — matches the server's `string.size()` (#527). See note above.
  if (value.length > kFreeTextMaxLength) {
    return FreeTextValidationError.tooLong;
  }
  if (_hasControlChar(value)) {
    return FreeTextValidationError.controlCharacter;
  }
  return null;
}

/// Returns a user-facing English error message, or `null` if [input] is valid.
///
/// For localized widgets use `validateFreeTextLocalized`.
String? validateFreeText(String? input) {
  return switch (freeTextValidationError(input)) {
    FreeTextValidationError.tooLong =>
      'Keep it to $kFreeTextMaxLength characters or fewer.',
    FreeTextValidationError.controlCharacter =>
      'Remove line breaks or special characters.',
    null => null,
  };
}

/// Whether [candidate] collides — by the shared #196/#279 collision key
/// `trim().toLowerCase()` — with any LIVE member in [memberDocs] whose
/// `userId` field differs from [selfUid].
///
/// The collision key MUST stay identical to `MemberNameResolver.disambiguate`
/// (`member_name_resolver.dart:96`) and the #279 server guard
/// (`functions/src/callables/joinGroupByInviteCode.ts:318-324`) so prevention
/// and the display disambiguator agree.
///
/// [memberDocs] are RAW Firestore member maps (not `GroupMember`) so a
/// malformed doc is skipped, never thrown on. Own-doc is matched by the
/// `userId` FIELD (legacy docs can be uuid-keyed — #294/#524), and tombstoned
/// (former) members are skipped to match the live-only counting in
/// `disambiguate`. Used by the self-rename pre-check (#390).
bool nameCollidesInDocs({
  required String candidate,
  required String selfUid,
  required Iterable<Map<String, dynamic>> memberDocs,
}) {
  final key = candidate.trim().toLowerCase();
  if (key.isEmpty) return false;
  for (final data in memberDocs) {
    if (data['userId'] == selfUid) continue;
    if (data['isTombstone'] == true) continue;
    final existing = data['displayName'];
    if (existing is String && existing.trim().toLowerCase() == key) {
      return true;
    }
  }
  return false;
}

/// Thrown by `setDeviceName` (#390) when the requested display name already
/// belongs to another live member of [groupName] — the rename is rejected
/// whole (all-or-nothing) so the user picks a different, unambiguous name.
class DisplayNameTakenException implements Exception {
  const DisplayNameTakenException(this.groupName);

  /// Name of the group in which the collision was found (for the UI message).
  final String groupName;

  @override
  String toString() => 'DisplayNameTakenException(groupName: $groupName)';
}

/// Validation helpers for user-entered display / group / event names.
///
/// Mirrors the server-side rules check `isValidDisplayName` in
/// `security/firestore.rules`: 1–32 characters after trim, no control
/// characters (U+0000–U+001F or U+007F). Validating client-side gives the
/// user a friendly inline error instead of an opaque `permission-denied`
/// when the rules reject the write.
library;

const int kDisplayNameMinLength = 1;
const int kDisplayNameMaxLength = 32;
const String _reservedFormerMemberSuffix =
    ' (former '
    'member)';

/// True if [s] contains any C0 control character (U+0000–U+001F) or DEL
/// (U+007F). Allowing these in display names lets attackers smuggle
/// newlines into UI rendering and confuses downstream tooling
/// (logs, push notification bodies). Every printable Unicode code point
/// including non-Latin scripts is accepted.
bool _hasControlChar(String s) {
  for (final cu in s.codeUnits) {
    if (cu < 0x20 || cu == 0x7F) return true;
  }
  return false;
}

/// Returns a user-facing error message, or `null` if [input] is a valid
/// display / group / event name.
///
/// Suitable for direct use as a `TextFormField.validator`.
String? validateDisplayName(String? input) {
  final raw = input ?? '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return "Name can't be empty.";
  }
  if (trimmed.length > kDisplayNameMaxLength) {
    return 'Keep it to $kDisplayNameMaxLength characters or fewer.';
  }
  if (_hasControlChar(raw)) {
    return 'Remove line breaks or special characters.';
  }
  if (trimmed.endsWith(_reservedFormerMemberSuffix)) {
    return 'That name uses reserved wording.';
  }
  return null;
}

/// Collapses runs of internal whitespace and trims edges. Use before
/// persisting — the validator does not normalize for you.
String normalizeDisplayName(String input) {
  return input.trim().replaceAll(RegExp(r'\s+'), ' ');
}

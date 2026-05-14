/// Permissive email validator for the link/recover entry forms.
///
/// Account-recovery spec §10 risk row: "Use a permissive regex; do not block
/// valid-but-uncommon TLDs." Firebase Auth itself is the authoritative
/// validator (it rejects invalid addresses on send); the client check is a
/// usability gate to catch obvious typos before burning a daily quota slot.
const int kEmailMaxLength = 254; // RFC 5321 path length cap

final RegExp _emailRegExp = RegExp(
  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
);

bool isValidEmailFormat(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty || trimmed.length > kEmailMaxLength) return false;
  return _emailRegExp.hasMatch(trimmed);
}

/// Returns null when [input] looks like a deliverable address, or a
/// short, user-facing reason string otherwise.
String? validateEmail(String? input) {
  final raw = input ?? '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Enter your email.';
  if (trimmed.length > kEmailMaxLength) {
    return 'That address is too long.';
  }
  if (!_emailRegExp.hasMatch(trimmed)) {
    return "That doesn't look like an email.";
  }
  return null;
}

String normalizeEmail(String input) => input.trim().toLowerCase();

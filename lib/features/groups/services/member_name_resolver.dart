import '../../events/models/event_model.dart';
import '../models/group_member_model.dart';

final class MemberDisplay {
  const MemberDisplay({required this.rawName, required this.isFormer});

  final String rawName;
  final bool isFormer;
}

final class MemberNameResolver {
  const MemberNameResolver._();

  static const formerSuffix = ' (former member)';
  static const formerMemberLiteral = 'Former member';

  static MemberDisplay resolveGroupScoped({
    required String uid,
    required List<GroupMember> members,
    String? fallbackName,
  }) {
    final live = _findMember(uid, members, isTombstone: false);
    if (live != null) {
      return MemberDisplay(rawName: live.displayName, isFormer: false);
    }

    final tombstone = _findMember(uid, members, isTombstone: true);
    if (tombstone != null) {
      return MemberDisplay(rawName: tombstone.displayName, isFormer: true);
    }

    final fallback = _usableName(fallbackName);
    if (fallback != null) {
      return MemberDisplay(rawName: fallback, isFormer: true);
    }

    return const MemberDisplay(rawName: formerMemberLiteral, isFormer: true);
  }

  static MemberDisplay resolveEventScoped({
    required String uid,
    required Event event,
    required List<GroupMember> members,
    String? fallbackName,
  }) {
    final live = _findMember(uid, members, isTombstone: false);
    final eventName = _usableName(event.participantNames[uid]);
    if (eventName != null) {
      return MemberDisplay(rawName: eventName, isFormer: live == null);
    }

    if (live != null) {
      return MemberDisplay(rawName: live.displayName, isFormer: false);
    }

    final tombstone = _findMember(uid, members, isTombstone: true);
    if (tombstone != null) {
      return MemberDisplay(rawName: tombstone.displayName, isFormer: true);
    }

    final fallback = _usableName(fallbackName);
    if (fallback != null) {
      return MemberDisplay(rawName: fallback, isFormer: true);
    }

    return const MemberDisplay(rawName: formerMemberLiteral, isFormer: true);
  }

  static String format(MemberDisplay display) {
    return display.isFormer
        ? '${display.rawName}$formerSuffix'
        : display.rawName;
  }

  static String stripFormerSuffix(String value) {
    return value.endsWith(formerSuffix)
        ? value.substring(0, value.length - formerSuffix.length)
        : value;
  }

  /// Returns a uid → display-string map where any LIVE member whose name
  /// collides with another LIVE member's name gets a stable
  /// ` (#<last4-of-uid>)` discriminator appended (the whole uid if ≤ 4 chars),
  /// so same-named people are distinguishable in settle-up UI (#196).
  ///
  /// Collisions are counted over LIVE entries only (a lone live member beside a
  /// same-named former member stays undiscriminated — the former already
  /// carries ` (former member)`). Former members are never discriminated.
  /// The suffix is render-only and MUST NOT be persisted: write paths read raw
  /// names, and [stripDiscriminator] is the defensive guard for the fallback.
  /// Returns a fresh map; the input is never mutated.
  static Map<String, String> disambiguate(Map<String, MemberDisplay> byUid) {
    final liveCounts = <String, int>{};
    for (final display in byUid.values) {
      if (display.isFormer) continue;
      final key = display.rawName.trim().toLowerCase();
      liveCounts[key] = (liveCounts[key] ?? 0) + 1;
    }

    return {
      for (final entry in byUid.entries)
        entry.key: _withDiscriminator(entry.key, entry.value, liveCounts),
    };
  }

  static String _withDiscriminator(
    String uid,
    MemberDisplay display,
    Map<String, int> liveCounts,
  ) {
    final formatted = format(display);
    if (display.isFormer) return formatted;
    final key = display.rawName.trim().toLowerCase();
    if ((liveCounts[key] ?? 0) <= 1) return formatted;
    return '$formatted${_discriminatorFor(uid)}';
  }

  static String _discriminatorFor(String uid) {
    final tail = uid.length <= 4 ? uid : uid.substring(uid.length - 4);
    return ' (#$tail)';
  }

  /// uid → render-ready name for an event's CURRENT participants, with the
  /// #196 collision discriminator applied. All participants are treated as
  /// LIVE (a picker shows current participants only), so two same-named people
  /// being picked stay distinct. Render-only — callers key writes by uid, never
  /// by the returned string. Blank-named participants are omitted so the caller
  /// keeps its own unknown fallback. (#289)
  static Map<String, String> disambiguateEventParticipants(Event event) {
    final byUid = <String, MemberDisplay>{};
    for (final uid in event.participantIds) {
      final name = event.participantNames[uid];
      if (name == null || name.trim().isEmpty) continue;
      byUid[uid] = MemberDisplay(rawName: name, isFormer: false);
    }
    return disambiguate(byUid);
  }

  /// uid → render-ready name for [uids] (default: event participants), resolved
  /// with full former-member awareness ([resolveEventScoped]) and then
  /// disambiguated. Use on display surfaces (ledger roster, event hub) that
  /// distinguish same-named LIVE members while still labelling departed ones.
  /// (#289)
  static Map<String, String> disambiguateEventScoped({
    required Event event,
    required List<GroupMember> members,
    Iterable<String>? uids,
  }) {
    return disambiguate({
      for (final uid in uids ?? event.participantIds)
        uid: resolveEventScoped(uid: uid, event: event, members: members),
    });
  }

  /// Live-name collision counts over [displays]; feed to [discriminatedLabel]
  /// to disambiguate a single member while preserving a caller-supplied
  /// fallback name (e.g. a persisted payerName). Former members never count.
  /// (#289)
  static Map<String, int> liveNameCounts(Iterable<MemberDisplay> displays) {
    final counts = <String, int>{};
    for (final display in displays) {
      if (display.isFormer) continue;
      final key = display.rawName.trim().toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// Disambiguated label for ONE [display] given [liveCounts] from its
  /// surrounding set. A live member whose name collides gets the #196
  /// ` (#last4)` suffix; everyone else — and every former member — is returned
  /// via [format] unchanged, so a caller's fallbackName survives. (#289)
  static String discriminatedLabel(
    String uid,
    MemberDisplay display,
    Map<String, int> liveCounts,
  ) {
    return _withDiscriminator(uid, display, liveCounts);
  }

  /// Compact label that PRESERVES any #196 discriminator so same-named members
  /// stay distinct in tight surfaces: "Ahmed Ali (#a1b2)" → "Ahmed (#a1b2)";
  /// "Ahmed Ali" → "Ahmed"; "Ahmed (former member)" → "Ahmed". (#289)
  static String compactDisambiguated(String value) {
    final discriminator =
        RegExp(r' \(#[^)]*\)$').firstMatch(value)?.group(0) ?? '';
    final base = stripDiscriminator(value);
    final firstWord = base.split(' ').first;
    return '$firstWord$discriminator';
  }

  /// Strips a render-only discriminator (and any former-member suffix) so the
  /// write path never persists ` (#…)`. Order matters: former suffix first,
  /// then a trailing ` (#…)` (mirrors how [disambiguate]/[format] compose).
  static String stripDiscriminator(String value) {
    final withoutFormer = stripFormerSuffix(value);
    return withoutFormer.replaceFirst(RegExp(r' \(#[^)]*\)$'), '');
  }

  static GroupMember? _findMember(
    String uid,
    List<GroupMember> members, {
    required bool isTombstone,
  }) {
    for (final member in members) {
      if (member.userId == uid && member.isTombstone == isTombstone) {
        return member;
      }
    }
    return null;
  }

  static String? _usableName(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }
}

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

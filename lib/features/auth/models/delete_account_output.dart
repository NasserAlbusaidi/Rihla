class DeleteAccountOutput {
  const DeleteAccountOutput({
    required this.groupsProcessed,
    required this.tombstoneIds,
    required this.expensesScrubbed,
    required this.settlementsScrubbed,
    required this.activityLogsScrubbed,
    required this.membersDeleted,
    required this.groupsOrphanedAndSoftDeleted,
    required this.fcmTokenDeleted,
    required this.joinAttemptsDeleted,
    required this.authUserDeleted,
  });

  final int groupsProcessed;
  final List<String> tombstoneIds;
  final int expensesScrubbed;
  final int settlementsScrubbed;
  final int activityLogsScrubbed;
  final int membersDeleted;
  final int groupsOrphanedAndSoftDeleted;
  final bool fcmTokenDeleted;
  final bool joinAttemptsDeleted;
  final bool authUserDeleted;

  factory DeleteAccountOutput.fromJson(Map<String, dynamic> json) {
    return DeleteAccountOutput(
      groupsProcessed: _int(json['groupsProcessed']),
      tombstoneIds: ((json['tombstoneIds'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      expensesScrubbed: _int(json['expensesScrubbed']),
      settlementsScrubbed: _int(json['settlementsScrubbed']),
      activityLogsScrubbed: _int(json['activityLogsScrubbed']),
      membersDeleted: _int(json['membersDeleted']),
      groupsOrphanedAndSoftDeleted: _int(json['groupsOrphanedAndSoftDeleted']),
      fcmTokenDeleted: json['fcmTokenDeleted'] == true,
      joinAttemptsDeleted: json['joinAttemptsDeleted'] == true,
      authUserDeleted: json['authUserDeleted'] == true,
    );
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

class DeleteAccountPartialFailure implements Exception {
  const DeleteAccountPartialFailure({
    required this.output,
    required this.code,
    required this.message,
  });

  final DeleteAccountOutput output;
  final String code;
  final String message;

  @override
  String toString() => 'DeleteAccountPartialFailure($code, $message)';
}

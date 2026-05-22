enum AccountJobKind {
  recoveryCleanup,
  deleteAccount,
  cacheWipe;

  String get wireName {
    return switch (this) {
      AccountJobKind.recoveryCleanup => 'recoveryCleanup',
      AccountJobKind.deleteAccount => 'deleteAccount',
      AccountJobKind.cacheWipe => 'cacheWipe',
    };
  }

  static AccountJobKind fromWireName(String value) {
    return switch (value) {
      'recoveryCleanup' => AccountJobKind.recoveryCleanup,
      'deleteAccount' => AccountJobKind.deleteAccount,
      'cacheWipe' => AccountJobKind.cacheWipe,
      _ => throw ArgumentError.value(value, 'value', 'unknown job kind'),
    };
  }
}

enum AccountJobRunStatus {
  idle,
  running,
  blocked,
  failed,
  complete;

  String get wireName {
    return switch (this) {
      AccountJobRunStatus.idle => 'idle',
      AccountJobRunStatus.running => 'running',
      AccountJobRunStatus.blocked => 'blocked',
      AccountJobRunStatus.failed => 'failed',
      AccountJobRunStatus.complete => 'complete',
    };
  }

  static AccountJobRunStatus fromWireName(String value) {
    return switch (value) {
      'idle' => AccountJobRunStatus.idle,
      'running' => AccountJobRunStatus.running,
      'blocked' => AccountJobRunStatus.blocked,
      'failed' => AccountJobRunStatus.failed,
      'complete' => AccountJobRunStatus.complete,
      _ => throw ArgumentError.value(value, 'value', 'unknown job status'),
    };
  }
}

class AccountJobStatusSnapshot {
  const AccountJobStatusSnapshot({
    required this.jobId,
    required this.kind,
    required this.status,
    required this.phase,
    this.current,
    this.total,
    this.retryable = false,
    this.errorCode,
    this.messageKey,
    this.counters = const <String, int>{},
  });

  final String jobId;
  final AccountJobKind kind;
  final AccountJobRunStatus status;
  final String phase;
  final int? current;
  final int? total;
  final bool retryable;
  final String? errorCode;
  final String? messageKey;
  final Map<String, int> counters;

  bool get isBlocking {
    return status == AccountJobRunStatus.running ||
        status == AccountJobRunStatus.blocked ||
        status == AccountJobRunStatus.failed;
  }

  bool get hasCountedProgress {
    return current != null && total != null && total! > 0;
  }

  AccountJobStatusSnapshot copyWith({
    String? jobId,
    AccountJobKind? kind,
    AccountJobRunStatus? status,
    String? phase,
    int? current,
    int? total,
    bool? retryable,
    String? errorCode,
    String? messageKey,
    Map<String, int>? counters,
  }) {
    return AccountJobStatusSnapshot(
      jobId: jobId ?? this.jobId,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      phase: phase ?? this.phase,
      current: current ?? this.current,
      total: total ?? this.total,
      retryable: retryable ?? this.retryable,
      errorCode: errorCode ?? this.errorCode,
      messageKey: messageKey ?? this.messageKey,
      counters: counters ?? this.counters,
    );
  }

  factory AccountJobStatusSnapshot.fromJson(Map<String, dynamic> json) {
    return AccountJobStatusSnapshot(
      jobId: json['jobId'] as String,
      kind: AccountJobKind.fromWireName(json['kind'] as String),
      status: AccountJobRunStatus.fromWireName(json['status'] as String),
      phase: json['phase'] as String? ?? '',
      current: json['current'] as int?,
      total: json['total'] as int?,
      retryable: json['retryable'] as bool? ?? false,
      errorCode: json['errorCode'] as String?,
      messageKey: json['messageKey'] as String?,
      counters: Map<String, int>.from(
        (json['counters'] as Map?) ?? const <String, int>{},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'jobId': jobId,
      'kind': kind.wireName,
      'status': status.wireName,
      'phase': phase,
      'current': current,
      'total': total,
      'retryable': retryable,
      'errorCode': errorCode,
      'messageKey': messageKey,
      'counters': counters,
    };
  }
}

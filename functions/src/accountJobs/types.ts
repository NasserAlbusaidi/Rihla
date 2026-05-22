import { Timestamp } from "firebase-admin/firestore";

export type AccountJobKind = "recoveryCleanup" | "deleteAccount";

export type AccountJobRunStatus = "running" | "blocked" | "failed" | "complete";

export interface AccountJobStatusOutput {
  jobId: string;
  kind: AccountJobKind;
  status: AccountJobRunStatus;
  phase: string;
  current?: number;
  total?: number;
  retryable?: boolean;
  errorCode?: string;
  messageKey?: string;
  counters?: Record<string, number>;
  output?: Record<string, unknown>;
}

export interface RecoveryCleanupCounters {
  groupsProcessed: number;
  groupsFailed: number;
  membersRewritten: number;
  eventsRewritten: number;
  expensesRewritten: number;
  settlementsRewritten: number;
  activityLogsRewritten: number;
}

export interface DeleteAccountCounters {
  groupsProcessed: number;
  tombstoneIds: number;
  expensesScrubbed: number;
  settlementsScrubbed: number;
  activityLogsScrubbed: number;
  membersDeleted: number;
  groupsOrphanedAndSoftDeleted: number;
}

export interface RecoveryCleanupJobDocument {
  kind: "recoveryCleanup";
  oldUid: string;
  newUid: string;
  status: AccountJobRunStatus;
  phase: string;
  current?: number;
  total?: number;
  cursor?: string | null;
  retryable?: boolean;
  errorCode?: string;
  counters: RecoveryCleanupCounters;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface DeleteAccountJobDocument {
  kind: "deleteAccount";
  uid: string;
  status: AccountJobRunStatus;
  phase: string;
  current?: number;
  total?: number;
  cursor?: string | null;
  retryable?: boolean;
  errorCode?: string;
  counters: DeleteAccountCounters;
  authDeleteAttempted?: boolean;
  serverScrubbedAuthDeleteFailed?: boolean;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

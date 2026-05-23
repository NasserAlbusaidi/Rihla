export interface RewriteResult<T> {
  value: T;
  changed: boolean;
}

export type NameRewriteStrategy =
  | { kind: "preserve" }
  | { kind: "replace"; value: string };

export interface IdentityRewritePolicy {
  kind: "recovery" | "deletion";
  sourceUid: string;
  destinationUid: string;
  createdByValue: string;
  nameStrategy: NameRewriteStrategy;
  scrubPii: boolean;
  preserveExistingDestinationNames: boolean;
}

export function recoveryIdentityRewritePolicy(
  oldUid: string,
  newUid: string,
): IdentityRewritePolicy {
  return {
    kind: "recovery",
    sourceUid: oldUid,
    destinationUid: newUid,
    createdByValue: newUid,
    nameStrategy: { kind: "preserve" },
    scrubPii: false,
    preserveExistingDestinationNames: true,
  };
}

export function deletionIdentityRewritePolicy(
  uid: string,
  tombstoneId: string,
  deletedMemberName: string,
  deletedUserSentinel: string,
): IdentityRewritePolicy {
  return {
    kind: "deletion",
    sourceUid: uid,
    destinationUid: tombstoneId,
    createdByValue: deletedUserSentinel,
    nameStrategy: { kind: "replace", value: deletedMemberName },
    scrubPii: true,
    preserveExistingDestinationNames: false,
  };
}

export function replaceUidInArray(
  values: string[],
  sourceUid: string,
  destinationUid: string,
): RewriteResult<string[]> {
  let changed = false;
  const next: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const replacement = value === sourceUid ? destinationUid : value;
    if (replacement !== value) changed = true;
    if (!seen.has(replacement)) {
      seen.add(replacement);
      next.push(replacement);
    }
  }
  return { value: next, changed };
}

export function renameMapKey(
  value: unknown,
  sourceUid: string,
  destinationUid: string,
  options: {
    destinationValue?: unknown;
    preserveExistingDestination?: boolean;
  } = {},
): RewriteResult<Record<string, unknown>> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  const next: Record<string, unknown> = {
    ...(value as Record<string, unknown>),
  };
  if (!Object.prototype.hasOwnProperty.call(next, sourceUid)) {
    return { value: next, changed: false };
  }

  const destinationExists = Object.prototype.hasOwnProperty.call(
    next,
    destinationUid,
  );
  if (!destinationExists || options.preserveExistingDestination !== true) {
    next[destinationUid] = options.destinationValue ?? next[sourceUid];
  }
  delete next[sourceUid];
  return { value: next, changed: true };
}

export function rewriteNestedUidReferences(
  value: unknown,
  sourceUid: string,
  destinationUid: string,
): RewriteResult<unknown> {
  if (typeof value === "string") {
    return {
      value: value === sourceUid ? destinationUid : value,
      changed: value === sourceUid,
    };
  }
  if (Array.isArray(value)) {
    let changed = false;
    const next = value.map((entry) => {
      const rewritten = rewriteNestedUidReferences(
        entry,
        sourceUid,
        destinationUid,
      );
      if (rewritten.changed) changed = true;
      return rewritten.value;
    });
    return { value: next, changed };
  }
  if (value && typeof value === "object") {
    let changed = false;
    const next: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(value)) {
      const nextKey = key === sourceUid ? destinationUid : key;
      const rewritten = rewriteNestedUidReferences(
        entryValue,
        sourceUid,
        destinationUid,
      );
      if (nextKey !== key || rewritten.changed) changed = true;
      next[nextKey] = rewritten.value;
    }
    return { value: next, changed };
  }
  return { value, changed: false };
}

const recoveryMetadataStringFields = new Set([
  "actorId",
  "targetParticipantId",
  "payerParticipantId",
  "recipientParticipantId",
  "recipientId",
  "relatedUserId",
]);

const recoveryMetadataStringArrayFields = new Set([
  "participantIds",
  "customSplitParticipants",
  "actors",
  "actorIds",
]);

function rewriteRecoveryMetadataObject(
  value: Record<string, unknown>,
  sourceUid: string,
  destinationUid: string,
  path: string,
): RewriteResult<Record<string, unknown>> {
  let changed = false;
  const next: Record<string, unknown> = { ...value };

  for (const field of recoveryMetadataStringFields) {
    if (!Object.prototype.hasOwnProperty.call(value, field)) continue;
    const fieldValue = value[field];
    if (fieldValue == null) continue;
    if (typeof fieldValue !== "string") {
      throw new Error(`${path}.${field} must be a string.`);
    }
    if (fieldValue === sourceUid) {
      next[field] = destinationUid;
      changed = true;
    }
  }

  for (const field of recoveryMetadataStringArrayFields) {
    if (!Object.prototype.hasOwnProperty.call(value, field)) continue;
    const fieldValue = value[field];
    if (fieldValue == null) continue;
    if (
      !Array.isArray(fieldValue) ||
      fieldValue.some((entry) => typeof entry !== "string")
    ) {
      throw new Error(`${path}.${field} must be a string array.`);
    }
    const replaced = replaceUidInArray(fieldValue, sourceUid, destinationUid);
    if (replaced.changed) {
      next[field] = replaced.value;
      changed = true;
    }
  }

  return { value: next, changed };
}

export function rewriteRecoveryMetadataUidReferences(
  value: unknown,
  sourceUid: string,
  destinationUid: string,
  path = "metadata",
): RewriteResult<unknown> {
  if (value == null) return { value, changed: false };
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${path} must be an object.`);
  }
  return rewriteRecoveryMetadataObject(
    value as Record<string, unknown>,
    sourceUid,
    destinationUid,
    path,
  );
}

export function rewriteDisplayName(
  value: unknown,
  policy: IdentityRewritePolicy,
): RewriteResult<unknown> {
  if (policy.nameStrategy.kind === "preserve") {
    return { value, changed: false };
  }
  const changed = value !== policy.nameStrategy.value;
  return { value: policy.nameStrategy.value, changed };
}

export function maybeScrubPiiField(
  value: unknown,
  policy: IdentityRewritePolicy,
): RewriteResult<unknown> {
  if (!policy.scrubPii) {
    return { value, changed: false };
  }
  return { value: null, changed: value !== null };
}

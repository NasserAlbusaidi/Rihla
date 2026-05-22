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
  for (const value of values) {
    const replacement = value === sourceUid ? destinationUid : value;
    if (replacement !== value) changed = true;
    if (!next.includes(replacement)) next.push(replacement);
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

import {
  deletionIdentityRewritePolicy,
  maybeScrubPiiField,
  recoveryIdentityRewritePolicy,
  renameMapKey,
  replaceUidInArray,
  rewriteDisplayName,
  rewriteNestedUidReferences,
  rewriteRecoveryMetadataUidReferences,
} from "../../src/accountJobs/identityRewrite";

describe("identity rewrite primitives", () => {
  test("replaceUidInArray dedupes destination collisions", () => {
    expect(
      replaceUidInArray(["old", "new", "other", "old"], "old", "new"),
    ).toEqual({
      value: ["new", "other"],
      changed: true,
    });
  });

  test("recovery map rename preserves an existing destination value", () => {
    expect(
      renameMapKey({ old: "Anonymous name", new: "Real name" }, "old", "new", {
        preserveExistingDestination: true,
      }),
    ).toEqual({
      value: { new: "Real name" },
      changed: true,
    });
  });

  test("deletion map rename replaces destination value when policy asks for tombstone value", () => {
    expect(
      renameMapKey({ old: "Nasser" }, "old", "deleted-1234", {
        destinationValue: "Deleted member",
      }),
    ).toEqual({
      value: { "deleted-1234": "Deleted member" },
      changed: true,
    });
  });

  test("nested metadata rewrites UID keys and values without changing names", () => {
    expect(
      rewriteNestedUidReferences(
        {
          actorId: "old",
          participants: ["old", "other"],
          nested: { old: { targetParticipantId: "old", actorName: "Nasser" } },
        },
        "old",
        "new",
      ),
    ).toEqual({
      value: {
        actorId: "new",
        participants: ["new", "other"],
        nested: { new: { targetParticipantId: "new", actorName: "Nasser" } },
      },
      changed: true,
    });
  });

  test("recovery metadata rewrites only known identity fields", () => {
    expect(
      rewriteRecoveryMetadataUidReferences(
        {
          actorId: "old",
          recipientId: "old",
          actors: ["old", "other"],
          contentHash: "old",
          nested: { actorId: "old" },
        },
        "old",
        "new",
      ),
    ).toEqual({
      value: {
        actorId: "new",
        recipientId: "new",
        actors: ["new", "other"],
        contentHash: "old",
        nested: { actorId: "old" },
      },
      changed: true,
    });
  });

  test("recovery metadata rejects malformed identity arrays", () => {
    expect(() =>
      rewriteRecoveryMetadataUidReferences(
        { actors: ["old", { uid: "other" }] },
        "old",
        "new",
      ),
    ).toThrow("metadata.actors must be a string array");
  });

  test("recovery policy preserves names and PII fields", () => {
    const policy = recoveryIdentityRewritePolicy("old", "new");

    expect(rewriteDisplayName("Nasser", policy)).toEqual({
      value: "Nasser",
      changed: false,
    });
    expect(maybeScrubPiiField("receipt-url", policy)).toEqual({
      value: "receipt-url",
      changed: false,
    });
  });

  test("deletion policy tombstones names and scrubs PII fields", () => {
    const policy = deletionIdentityRewritePolicy(
      "uid",
      "deleted-1234",
      "Deleted member",
      "deleted-user",
    );

    expect(rewriteDisplayName("Nasser", policy)).toEqual({
      value: "Deleted member",
      changed: true,
    });
    expect(maybeScrubPiiField("receipt-url", policy)).toEqual({
      value: null,
      changed: true,
    });
  });
});

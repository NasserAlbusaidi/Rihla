#!/usr/bin/env node

const { createRequire } = require('module');
const path = require('path');

function requireFirebaseAdmin(modulePath) {
  try {
    return require(`firebase-admin/${modulePath}`);
  } catch (error) {
    const functionsRequire = createRequire(
      path.join(__dirname, '../functions/package.json'),
    );
    return functionsRequire(`firebase-admin/${modulePath}`);
  }
}

const { getApps, initializeApp } = requireFirebaseAdmin('app');
const { FieldValue, getFirestore } = requireFirebaseAdmin('firestore');

if (!getApps().length) {
  initializeApp();
}

const args = process.argv.slice(2);
let groupFilter = null;
let dryRun = true;

for (const arg of args) {
  if (arg === '--dry-run') {
    dryRun = true;
  } else if (arg === '--commit') {
    dryRun = false;
  } else if (arg.startsWith('--group=')) {
    groupFilter = arg.slice('--group='.length);
  } else {
    throw new Error(`Unknown argument: ${arg}`);
  }
}

function asStringArray(value, label) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new Error(`${label} must be an array of strings`);
  }
  return value;
}

function asParticipantNames(value, label) {
  if (value == null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be a map`);
  }
  const names = {};
  for (const [uid, displayName] of Object.entries(value)) {
    if (typeof displayName !== 'string') {
      throw new Error(`${label}.${uid} must be a string`);
    }
    names[uid] = displayName;
  }
  return names;
}

async function loadGroups(db) {
  if (groupFilter) {
    const snap = await db.doc(`groups/${groupFilter}`).get();
    if (!snap.exists) {
      throw new Error(`Group not found: ${groupFilter}`);
    }
    return [snap];
  }
  const snap = await db.collection('groups').get();
  return snap.docs;
}

async function loadMemberNames(groupRef, memberIds) {
  const entries = await Promise.all(
    memberIds.map(async (uid) => {
      const snap = await groupRef.collection('members').doc(uid).get();
      const displayName = snap.data()?.displayName;
      return [uid, typeof displayName === 'string' ? displayName : null];
    }),
  );
  return new Map(entries);
}

async function main() {
  const db = getFirestore();
  const groupSnaps = await loadGroups(db);
  let discrepancies = 0;
  let writes = 0;

  for (const groupSnap of groupSnaps) {
    const groupId = groupSnap.id;
    const groupData = groupSnap.data() ?? {};
    const memberIds = asStringArray(groupData.memberIds, `groups/${groupId}.memberIds`);
    const memberNames = await loadMemberNames(groupSnap.ref, memberIds);
    const eventsSnap = await groupSnap.ref.collection('events').get();

    for (const eventSnap of eventsSnap.docs) {
      const eventId = eventSnap.id;
      const eventData = eventSnap.data() ?? {};
      if (eventData.isDeleted === true) {
        continue;
      }

      const participantIds = asStringArray(
        eventData.participantIds,
        `groups/${groupId}/events/${eventId}.participantIds`,
      );
      const participantNames = asParticipantNames(
        eventData.participantNames,
        `groups/${groupId}/events/${eventId}.participantNames`,
      );
      const missingUids = memberIds.filter((uid) => !participantIds.includes(uid));
      const extraUids = participantIds.filter((uid) => !memberIds.includes(uid));

      if (missingUids.length > 0 || extraUids.length > 0) {
        discrepancies += 1;
        console.log(JSON.stringify({
          level: 'discrepancy',
          groupId,
          eventId,
          missingUids,
          extraUids,
        }));
      }

      if (dryRun || missingUids.length === 0) {
        continue;
      }

      const addedUids = missingUids.filter((uid) => memberNames.get(uid) != null);
      const missingNameUids = missingUids.filter((uid) => memberNames.get(uid) == null);
      if (missingNameUids.length > 0) {
        console.warn(JSON.stringify({
          level: 'warning',
          groupId,
          eventId,
          message: 'missing member displayName; uid skipped',
          missingNameUids,
        }));
      }
      if (addedUids.length === 0) {
        continue;
      }

      const nextParticipantNames = { ...participantNames };
      for (const uid of addedUids) {
        nextParticipantNames[uid] = memberNames.get(uid);
      }
      await eventSnap.ref.update({
        participantIds: FieldValue.arrayUnion(...addedUids),
        participantNames: nextParticipantNames,
        updatedAt: FieldValue.serverTimestamp(),
      });
      writes += 1;
      console.log(JSON.stringify({
        level: 'write',
        groupId,
        eventId,
        addedUids,
      }));
    }
  }

  console.log(JSON.stringify({
    level: 'summary',
    dryRun,
    groupsScanned: groupSnaps.length,
    discrepancies,
    writes,
  }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

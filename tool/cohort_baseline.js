#!/usr/bin/env node

// Read-only cohort baseline: per group created in [--start, --end), measure
// activation — members, first real money activity, and whether the group came
// back for a second event.
//
// Groups created since 2026-07-02 (#245, bcb27382) are born with one seeded
// event, so for them event doc #2 is the first deliberately user-created one;
// older groups have no seed and event doc #2 is their second deliberate event.
// Rows count event DOCS uniformly; the summary segments seeded vs unseeded
// groups (seed detected by serverCreatedAt within 10s of group createdAt —
// the founding batch stamps both with the same commit time).
//
// ZERO writes. No analytics SDK. Idempotent — same window, same output files.
//
// Usage (ADC auth, same as backfill_join_event_sync.js):
//   node tool/cohort_baseline.js --start=2026-01-01 --end=2026-07-07
//   [--project=rihla-safar] [--out-dir=audit-reports]
//
// Definitions:
//   membersJoined                 LIVE member docs with isTombstone != true
//                                 (creator + unclaimed shadows included;
//                                 leavers/removed are hard-deleted, invisible)
//   real expense                  isDeleted != true
//   real settlement               no correctionOfSettlementId (server-written
//                                 reversal marker, #889); legacy note-sentinel
//                                 correction pairs are NOT excluded
//   firstRealExpenseOrSettlementAt  min over all events' real expenses
//                                 (createdAt) + real event settlements +
//                                 real group settlements (settledAt)
//   secondEventCreated            >= 2 event docs (soft-deleted included —
//                                 creation is the signal)
//   secondEventHasRealActivity    2nd event chronologically has >= 1 real
//                                 expense or real event settlement
//   daysToSecondEvent             (2nd event time - group createdAt) in days

const { createRequire } = require('module');
const path = require('path');
const fs = require('fs');

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
const { getFirestore, Timestamp } = requireFirebaseAdmin('firestore');

const args = process.argv.slice(2);
let startArg = null;
let endArg = null;
let projectId = 'rihla-safar';
let outDir = path.resolve(__dirname, '..', 'audit-reports');

for (const arg of args) {
  if (arg.startsWith('--start=')) {
    startArg = arg.slice('--start='.length);
  } else if (arg.startsWith('--end=')) {
    endArg = arg.slice('--end='.length);
  } else if (arg.startsWith('--project=')) {
    projectId = arg.slice('--project='.length);
  } else if (arg.startsWith('--out-dir=')) {
    outDir = path.resolve(arg.slice('--out-dir='.length));
  } else {
    throw new Error(`Unknown argument: ${arg}`);
  }
}

function parseUtcDate(value, label) {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${label} must be YYYY-MM-DD, got: ${value}`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime())) {
    throw new Error(`${label} is not a valid date: ${value}`);
  }
  return date;
}

const windowStart = parseUtcDate(startArg, '--start');
const windowEnd = parseUtcDate(endArg, '--end');
if (windowEnd <= windowStart) {
  throw new Error('--end must be after --start (end is exclusive)');
}

// Timestamps are heterogeneous across docs: group.createdAt is a server
// Timestamp; event/expense createdAt and settlement settledAt are client
// ISO-8601 strings (legacy docs may hold Timestamps) — parse both.
function asDate(value) {
  if (value == null) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function isoOrEmpty(date) {
  return date ? date.toISOString() : '';
}

function eventTime(eventData) {
  return asDate(eventData.serverCreatedAt) ?? asDate(eventData.createdAt);
}

function isRealExpense(data) {
  return data.isDeleted !== true;
}

function isRealSettlement(data) {
  const marker = data.correctionOfSettlementId;
  return !(typeof marker === 'string' && marker.trim().length > 0);
}

function minDate(dates) {
  const valid = dates.filter((d) => d != null);
  if (valid.length === 0) return null;
  return valid.reduce((a, b) => (a <= b ? a : b));
}

async function analyzeGroup(groupSnap) {
  const groupId = groupSnap.id;
  const groupData = groupSnap.data() ?? {};
  const groupCreatedAt = asDate(groupData.createdAt);

  const [membersSnap, eventsSnap, groupSettlementsSnap] = await Promise.all([
    groupSnap.ref.collection('members').get(),
    groupSnap.ref.collection('events').get(),
    groupSnap.ref.collection('settlements').get(),
  ]);

  const membersJoined = membersSnap.docs.filter(
    (doc) => (doc.data() ?? {}).isTombstone !== true,
  ).length;

  const events = eventsSnap.docs
    .map((doc) => ({ id: doc.id, ref: doc.ref, time: eventTime(doc.data() ?? {}) }))
    .sort((a, b) => {
      const at = a.time ? a.time.getTime() : Number.MAX_SAFE_INTEGER;
      const bt = b.time ? b.time.getTime() : Number.MAX_SAFE_INTEGER;
      return at === bt ? a.id.localeCompare(b.id) : at - bt;
    });

  const perEvent = await Promise.all(
    events.map(async (event) => {
      const [expensesSnap, settlementsSnap] = await Promise.all([
        event.ref.collection('expenses').get(),
        event.ref.collection('settlements').get(),
      ]);
      const realExpenseTimes = expensesSnap.docs
        .map((doc) => doc.data() ?? {})
        .filter(isRealExpense)
        .map((data) => asDate(data.createdAt));
      const realSettlementTimes = settlementsSnap.docs
        .map((doc) => doc.data() ?? {})
        .filter(isRealSettlement)
        .map((data) => asDate(data.settledAt));
      return {
        eventId: event.id,
        hasRealActivity:
          realExpenseTimes.length > 0 || realSettlementTimes.length > 0,
        firstActivityAt: minDate([...realExpenseTimes, ...realSettlementTimes]),
      };
    }),
  );

  const realGroupSettlementTimes = groupSettlementsSnap.docs
    .map((doc) => doc.data() ?? {})
    .filter(isRealSettlement)
    .map((data) => asDate(data.settledAt));

  const firstRealExpenseOrSettlementAt = minDate([
    ...perEvent.map((e) => e.firstActivityAt),
    ...realGroupSettlementTimes,
  ]);

  const firstEvent = events.length >= 1 ? events[0] : null;
  const hadFoundingSeed =
    firstEvent?.time != null &&
    groupCreatedAt != null &&
    Math.abs(firstEvent.time.getTime() - groupCreatedAt.getTime()) <= 10000;

  const secondEvent = events.length >= 2 ? events[1] : null;
  const secondEventCreated = secondEvent != null;
  const secondEventHasRealActivity = secondEvent
    ? perEvent.find((e) => e.eventId === secondEvent.id)?.hasRealActivity === true
    : false;
  const daysToSecondEvent =
    secondEvent?.time != null && groupCreatedAt != null
      ? Math.round(
          ((secondEvent.time.getTime() - groupCreatedAt.getTime()) / 86400000) *
            100,
        ) / 100
      : null;

  return {
    row: {
      groupId,
      createdAt: isoOrEmpty(groupCreatedAt) || null,
      membersJoined,
      firstRealExpenseOrSettlementAt:
        isoOrEmpty(firstRealExpenseOrSettlementAt) || null,
      secondEventCreated,
      secondEventHasRealActivity,
      daysToSecondEvent,
    },
    hadFoundingSeed,
  };
}

function toCsv(rows) {
  const header = [
    'groupId',
    'createdAt',
    'membersJoined',
    'firstRealExpenseOrSettlementAt',
    'secondEventCreated',
    'secondEventHasRealActivity',
    'daysToSecondEvent',
  ];
  const lines = rows.map((row) =>
    header
      .map((key) => {
        const value = row[key];
        if (value == null) return '';
        const text = String(value);
        return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
      })
      .join(','),
  );
  return [header.join(','), ...lines].join('\n') + '\n';
}

function median(values) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? sorted[mid]
    : Math.round(((sorted[mid - 1] + sorted[mid]) / 2) * 100) / 100;
}

async function main() {
  if (!getApps().length) {
    initializeApp({ projectId });
  }
  const db = getFirestore();

  const groupsSnap = await db
    .collection('groups')
    .where('createdAt', '>=', Timestamp.fromDate(windowStart))
    .where('createdAt', '<', Timestamp.fromDate(windowEnd))
    .orderBy('createdAt')
    .get();

  const analyses = [];
  for (const groupSnap of groupsSnap.docs) {
    analyses.push(await analyzeGroup(groupSnap));
  }
  const rows = analyses.map((a) => a.row);

  const startLabel = startArg;
  const endLabel = endArg;
  const baseName = `cohort_baseline_${startLabel}_${endLabel}`;
  fs.mkdirSync(outDir, { recursive: true });
  const csvPath = path.join(outDir, `${baseName}.csv`);
  const jsonPath = path.join(outDir, `${baseName}.json`);

  const withSecondEvent = rows.filter((r) => r.secondEventCreated);
  const withRealSecondEvent = rows.filter((r) => r.secondEventHasRealActivity);
  const withAnyRealActivity = rows.filter(
    (r) => r.firstRealExpenseOrSettlementAt != null,
  );
  // Pre-#245 (2026-07-02) groups have no founding seed, so their event doc #2
  // is a SECOND deliberate event, not the first — segment so the headline
  // percentages never mix the two meanings.
  const segmentOf = (subset) => ({
    groups: subset.length,
    withSecondEvent: subset.filter((a) => a.row.secondEventCreated).length,
    withRealSecondEvent: subset.filter((a) => a.row.secondEventHasRealActivity)
      .length,
    medianDaysToSecondEvent: median(
      subset.map((a) => a.row.daysToSecondEvent).filter((d) => d != null),
    ),
  });
  const segments = {
    seededGroups: segmentOf(analyses.filter((a) => a.hadFoundingSeed)),
    unseededGroups: segmentOf(analyses.filter((a) => !a.hadFoundingSeed)),
  };
  const summary = {
    window: { start: windowStart.toISOString(), endExclusive: windowEnd.toISOString() },
    projectId,
    generatedAt: new Date().toISOString(),
    groups: rows.length,
    groupsWithAnyRealActivity: withAnyRealActivity.length,
    groupsWithSecondEvent: withSecondEvent.length,
    groupsWithRealSecondEvent: withRealSecondEvent.length,
    pctSecondEvent: rows.length
      ? Math.round((withSecondEvent.length / rows.length) * 1000) / 10
      : null,
    pctRealSecondEvent: rows.length
      ? Math.round((withRealSecondEvent.length / rows.length) * 1000) / 10
      : null,
    medianDaysToSecondEvent: median(
      rows.map((r) => r.daysToSecondEvent).filter((d) => d != null),
    ),
    segments,
    definitions: {
      membersJoined:
        'LIVE member docs with isTombstone != true (creator + shadows included; leavers/removed are hard-deleted and not counted)',
      realExpense: 'isDeleted != true',
      realSettlement:
        'no correctionOfSettlementId marker; legacy note-sentinel correction pairs not excluded',
      secondEvent:
        'second event doc chronologically (serverCreatedAt, else createdAt); for seededGroups (#245, created >= 2026-07-02) event #1 is the founding seed so #2 is the first deliberate event; for unseededGroups #2 is a second deliberate event',
      seedDetection:
        'first event serverCreatedAt within 10s of group createdAt (founding batch shares one commit time)',
    },
  };

  fs.writeFileSync(csvPath, toCsv(rows));
  fs.writeFileSync(jsonPath, JSON.stringify({ summary, rows }, null, 2) + '\n');

  console.log(JSON.stringify({ level: 'summary', ...summary }));
  console.log(JSON.stringify({ level: 'output', csvPath, jsonPath }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import '../admin';
import { runAccountDeletionCascade } from '../callables/deleteAccount';

// #76: server-side backstop for the "user uninstalls / never retries" tail of
// account deletion. A partial or timed-out deleteAccount leaves a
// `deletionAudit/{uid}` marker; this scheduled job re-runs the idempotent,
// convergent (#46) cascade for markers older than the grace window and lets the
// shared core delete the marker once the deletion finally converges. This is the
// FIRST scheduled function in the codebase (new Cloud Scheduler deploy surface).
const defaultGraceMs = 24 * 60 * 60 * 1000;
const defaultBatch = 50;

function resolveGraceMs(): number {
  return Number(process.env.DELETION_REAPER_GRACE_MS) || defaultGraceMs;
}

function resolveBatch(): number {
  return Number(process.env.DELETION_REAPER_BATCH) || defaultBatch;
}

export const deletionReaper = onSchedule(
  { schedule: 'every 24 hours', timeoutSeconds: 540, memory: '1GiB' },
  async () => {
    const db = getFirestore();
    // Grace: never reap a marker a client could still be retrying. On a rare
    // reaper-vs-client overlap the cascade is still safe — it is idempotent and
    // Phase C is transactional (#46); only the observability-only `attemptCount`
    // can under-count by one.
    const cutoff = Timestamp.fromMillis(Date.now() - resolveGraceMs());
    const stale = await db
      .collection('deletionAudit')
      .where('lastAttemptAt', '<', cutoff)
      .limit(resolveBatch())
      .get();

    let resolved = 0;
    for (const doc of stale.docs) {
      const uid = doc.id;
      try {
        // The shared core revokes tokens, scrubs, deletes the Auth user, and
        // manages the marker (deletes on success — incl. an already-gone user —
        // refreshes on re-failure). So an orphaned marker self-heals here.
        const { complete } = await runAccountDeletionCascade(db, uid);
        if (complete) resolved += 1;
      } catch (error) {
        logger.error('deletionReaper cascade error', {
          uid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Surface the counts so a batch-capped run (markers beyond REAPER_BATCH left
    // for the next pass) is visible, never silently truncated.
    logger.info('deletionReaper run', { scanned: stale.size, resolved });
  },
);

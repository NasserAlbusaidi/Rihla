import { DocumentData, DocumentReference, Firestore, WriteBatch } from 'firebase-admin/firestore';

const defaultBatchLimit = 450;

// #46: test seam — lower via DELETE_ACCOUNT_BATCH_LIMIT to force a mid-cascade
// auto-flush with a handful of docs instead of 450+. Read at construction (not
// module load) so a test can set it before invoking the callable. The env var
// keeps its historical DELETE_ACCOUNT_* name so deleteAccount's existing #46
// batched test AND claimShadow's batched-boundary test (#278) share one knob.
function resolveBatchLimit(): number {
  return Number(process.env.DELETE_ACCOUNT_BATCH_LIMIT) || defaultBatchLimit;
}

// Auto-flushing Firestore batch writer. Extracted from deleteAccount.ts (#278)
// so deleteAccount AND claimShadow share ONE batched writer for their idempotent
// Phase-B child-doc cascades (a single 500-write Firestore batch would overflow
// a high-debt-across-many-events claim). Behavior-preserving move —
// deleteAccount.test.ts is the proof. deleteGroup.ts keeps its own independent
// copy; de-duping that is a tracked follow-up, out of scope for this PR.
export class BatchWriter {
  private batch: WriteBatch;
  private writes = 0;
  private readonly limit: number;

  constructor(private readonly db: Firestore) {
    this.batch = db.batch();
    this.limit = resolveBatchLimit();
  }

  async set(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.set(ref, data);
    await this.afterWrite();
  }

  async update(ref: DocumentReference, data: DocumentData): Promise<void> {
    this.batch.update(ref, data);
    await this.afterWrite();
  }

  async delete(ref: DocumentReference): Promise<void> {
    this.batch.delete(ref);
    await this.afterWrite();
  }

  async flush(): Promise<void> {
    if (this.writes === 0) return;
    await this.batch.commit();
    this.batch = this.db.batch();
    this.writes = 0;
  }

  private async afterWrite(): Promise<void> {
    this.writes += 1;
    if (this.writes >= this.limit) {
      await this.flush();
    }
  }
}

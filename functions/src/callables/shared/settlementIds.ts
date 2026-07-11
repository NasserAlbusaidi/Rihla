import { createHash } from 'crypto';

// #1129: TS port of the #1093 deterministic settlement ids
// (lib/features/ledger/services/settlement_service.dart — the Dart originals
// are DELETED by #1129; derivation is server-side only now). BYTE-PARITY IS
// LOAD-BEARING: pre-#1129 client-minted ids and server-minted ids share one
// dedup namespace, so the same observed settle state must derive the same id
// across the transition. functions/test/settlementIds.test.ts pins this port
// to golden vectors computed with the Dart helpers before their deletion.
// Never add inputs that differ across devices (names, timestamps, notes) and
// never change the joiner/truncation — see CLAUDE.md "deterministic dedup ids".

const US = '\x1f';

function sd1(canonical: string): string {
  return `sd1${createHash('sha256').update(canonical, 'utf8').digest('hex').substring(0, 40)}`;
}

export interface DeterministicSettlementIdInput {
  // 'event:<groupId>:<eventId>' | 'group:<groupId>' | 'gsu:<groupId>' —
  // disjoint namespaces, no cross-scope collision.
  scopeKey: string;
  payerParticipantId: string;
  recipientParticipantId: string;
  currency: string;
  // Integer subunits (MoneySerializer.toSubunits output). The Dart helper
  // converted from Decimal internally and stringified the same integer, so
  // passing the int keeps id-amount and stored amountFils in lockstep.
  amountFils: number;
  // The CLIENT's observed count of live directed-pair settlements on the
  // scope's #1093 basis — a dedup nonce, never a money input.
  pairEpoch: number;
}

export function deterministicSettlementId(input: DeterministicSettlementIdInput): string {
  return sd1(
    [
      'sd1',
      input.scopeKey,
      input.payerParticipantId,
      input.recipientParticipantId,
      input.currency,
      `${input.amountFils}`,
      `${input.pairEpoch}`,
    ].join(US),
  );
}

// Decompose legs/residual derive from the parent groupSettleUpId alone —
// deliberately amount- and epoch-free (two racing decomposes collide on every
// leg, so the loser's whole transaction rejects atomically).
export function decomposeLegSettlementId(groupSettleUpId: string, eventId: string): string {
  return sd1(['sd1leg', groupSettleUpId, eventId].join(US));
}

export function decomposeResidualSettlementId(groupSettleUpId: string): string {
  return sd1(['sd1res', groupSettleUpId].join(US));
}

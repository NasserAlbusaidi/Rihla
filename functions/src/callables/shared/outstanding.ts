import Decimal from 'decimal.js';
import { Money, currencyScale } from '../groupNetBalance';

// #1129: TS mirror of BalanceCalculator.outstandingForPair
// (lib/features/ledger/providers/expense_provider.dart:970-987) — the directed
// per-currency cap `min(max(-fromNet, 0), max(toNet, 0))`, converted to integer
// subunits. Consumes the oracle's RecomputeResult.net (or a perEventNet slice),
// so parity with the client cap holds by construction wherever the snapshot
// basis matches (the callable is responsible for matching the basis per mode).

export function outstandingForPairFils(
  net: Map<string, Map<string, Decimal>>,
  currency: string,
  fromUserId: string,
  toUserId: string,
): number {
  // VERBATIM currency-key lookup — never .toUpperCase() here. The oracle
  // buckets case-preserved (currencyOf), and the client reads
  // `bucketed[currency]` verbatim (settle_up_screen.dart:617-618). A
  // wrong-case query finds no bucket → outstanding 0 → conservative reject.
  const bucket = net.get(currency);
  const zero = new Money(0);
  const netFor = (uid: string): Decimal => bucket?.get(uid) ?? zero;

  const fromNet = netFor(fromUserId); // debtor when negative
  const toNet = netFor(toUserId); // creditor when positive
  const payable = fromNet.isNegative() ? fromNet.abs() : zero;
  const receivable = toNet.isPositive() ? toNet : zero;
  const outstanding = payable.lt(receivable) ? payable : receivable;

  // Oracle nets are whole-subunit by allocator quantization (#596 lockstep),
  // so × scale lands on an integer. Legacy/garbage sub-subunit residue is
  // FLOORED toward zero — the cap may only shrink, never grow.
  return outstanding.times(currencyScale(currency)).floor().toNumber();
}

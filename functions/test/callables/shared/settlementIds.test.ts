// #1129 Task 1: golden-vector pins for the TS port of the #1093 deterministic
// settlement ids. The expected literals below were computed with the ORIGINAL
// Dart helpers (SettlementService.deterministicSettlementId/
// decomposeLegSettlementId/decomposeResidualSettlementId) on 2026-07-11,
// immediately before their deletion — cross-language byte-parity is the whole
// point: pre-#1129 client-minted ids and server-minted ids share one dedup
// namespace. Pure functions, no Firestore.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/settlementIds.test.ts" npm run test:emulator`

import {
  decomposeLegSettlementId,
  decomposeResidualSettlementId,
  deterministicSettlementId,
} from '../../../src/callables/shared/settlementIds';

const BASE = {
  scopeKey: 'event:g1:e1',
  payerParticipantId: 'alice',
  recipientParticipantId: 'bob',
  currency: 'OMR',
  amountFils: 2900,
  pairEpoch: 0,
};

describe('deterministicSettlementId — Dart golden vectors (2026-07-11)', () => {
  // Dart calls passed Decimal amounts; the fils column is what
  // MoneySerializer.toSubunits produced (OMR 2.900 → 2900, USD 29.00 → 2900,
  // JPY 2900 → 2900) — all three share amountFils 2900 yet derive DISTINCT
  // ids because currency is its own id input.
  const vectors: Array<[string, typeof BASE, string]> = [
    ['event OMR 2.900 epoch 0', BASE, 'sd1b67ca4d833ed0fa3ed898c523af3ff5c18dea940'],
    ['event OMR 2.900 epoch 1', { ...BASE, pairEpoch: 1 }, 'sd1753c335015f5a7811e481634fa011cf25180c041'],
    ['group USD 29.00 epoch 0', { ...BASE, scopeKey: 'group:g1', currency: 'USD' }, 'sd16e1cf4512c7d71a98466d5c91c75b6b0ec58e725'],
    ['gsu JPY 2900 epoch 0', { ...BASE, scopeKey: 'gsu:g1', currency: 'JPY' }, 'sd1f3b529bc7e76123bd817c092bc01096fcd4c9849'],
    ['event reversed pair epoch 0', { ...BASE, payerParticipantId: 'bob', recipientParticipantId: 'alice' }, 'sd1b2ce39855f70d43d399b0f9f600a08f1d7e255a2'],
    ['group OMR 2.900 epoch 0', { ...BASE, scopeKey: 'group:g1' }, 'sd10723a1010ea45e04c6195e505115e9361253fd74'],
  ];

  test.each(vectors)('%s', (_name, input, expected) => {
    expect(deterministicSettlementId(input)).toBe(expected);
  });

  test('determinism: same input twice → same id', () => {
    expect(deterministicSettlementId(BASE)).toBe(deterministicSettlementId(BASE));
  });

  test('shape: ^sd1[0-9a-f]{40}$ (43 chars, Firestore-safe)', () => {
    for (const [, input] of vectors) {
      expect(deterministicSettlementId(input)).toMatch(/^sd1[0-9a-f]{40}$/);
    }
  });

  test('every input perturbs the id', () => {
    const base = deterministicSettlementId(BASE);
    const perturbed: Array<Partial<typeof BASE>> = [
      { scopeKey: 'event:g1:e2' },
      { payerParticipantId: 'alicf' },
      { recipientParticipantId: 'bobb' },
      { currency: 'USD' },
      { amountFils: 2901 },
      { pairEpoch: 1 },
    ];
    for (const p of perturbed) {
      expect(deterministicSettlementId({ ...BASE, ...p })).not.toBe(base);
    }
  });

  test('same amountFils, different currency scale origin → distinct ids (OMR 2900 vs USD 2900 vs JPY 2900)', () => {
    const omr = deterministicSettlementId(BASE);
    const usd = deterministicSettlementId({ ...BASE, currency: 'USD' });
    const jpy = deterministicSettlementId({ ...BASE, currency: 'JPY' });
    expect(new Set([omr, usd, jpy]).size).toBe(3);
  });
});

describe('decompose leg/residual ids — Dart golden vectors (2026-07-11)', () => {
  test('leg(sd1abc, e1)', () => {
    expect(decomposeLegSettlementId('sd1abc', 'e1')).toBe(
      'sd109d6b733870c776aaaa933176f323bae2ba24355',
    );
  });

  test('residual(sd1abc)', () => {
    expect(decomposeResidualSettlementId('sd1abc')).toBe(
      'sd12f5751e941919b68f580727d58b5fa40f6a4528c',
    );
  });

  test('leg ids vary by eventId; residual disjoint from legs', () => {
    const l1 = decomposeLegSettlementId('sd1abc', 'e1');
    const l2 = decomposeLegSettlementId('sd1abc', 'e2');
    const r = decomposeResidualSettlementId('sd1abc');
    expect(new Set([l1, l2, r]).size).toBe(3);
    expect(r).toMatch(/^sd1[0-9a-f]{40}$/);
  });
});

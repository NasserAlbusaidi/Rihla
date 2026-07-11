// #1129 Task 1: table-driven pins for outstandingForPairFils — the TS mirror
// of BalanceCalculator.outstandingForPair (expense_provider.dart:970-987)
// converted to integer subunits. Money code → clean/boundary/garbage rows.
// Pure functions, no Firestore.
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/outstanding.test.ts" npm run test:emulator`

import Decimal from 'decimal.js';
import { Money } from '../../../src/callables/groupNetBalance';
import { outstandingForPairFils } from '../../../src/callables/shared/outstanding';

function net(
  currency: string,
  entries: Record<string, string>,
): Map<string, Map<string, Decimal>> {
  const bucket = new Map<string, Decimal>();
  for (const [uid, value] of Object.entries(entries)) {
    bucket.set(uid, new Money(value));
  }
  return new Map([[currency, bucket]]);
}

describe('outstandingForPairFils — clean rows', () => {
  test('both-sided debt → min(|fromNet|, toNet) in fils (OMR 3dp)', () => {
    // alice owes 5.000, bob is owed 3.000 → pair outstanding 3.000 → 3000 fils
    expect(
      outstandingForPairFils(net('OMR', { alice: '-5', bob: '3' }), 'OMR', 'alice', 'bob'),
    ).toBe(3000);
  });

  test('creditor side smaller on the payer → payable governs', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-2.900', bob: '10' }), 'OMR', 'alice', 'bob'),
    ).toBe(2900);
  });

  test('USD 2dp scale', () => {
    expect(
      outstandingForPairFils(net('USD', { alice: '-29', bob: '29' }), 'USD', 'alice', 'bob'),
    ).toBe(2900);
  });

  test('JPY scale 1 (the easy-to-forget one)', () => {
    expect(
      outstandingForPairFils(net('JPY', { alice: '-2900', bob: '2900' }), 'JPY', 'alice', 'bob'),
    ).toBe(2900);
  });
});

describe('outstandingForPairFils — zero rows', () => {
  test('same-sign pair (both creditors) → 0', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '5', bob: '3' }), 'OMR', 'alice', 'bob'),
    ).toBe(0);
  });

  test('reversed direction of a real debt → 0 (directed cap)', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-5', bob: '5' }), 'OMR', 'bob', 'alice'),
    ).toBe(0);
  });

  test('absent uid treated as settled → 0', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-5' }), 'OMR', 'alice', 'ghost'),
    ).toBe(0);
  });

  test('missing currency bucket → 0', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-5', bob: '5' }), 'USD', 'alice', 'bob'),
    ).toBe(0);
  });

  test('VERBATIM bucket lookup: lowercase query misses the case-preserved bucket → 0 (never uppercased)', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-5', bob: '5' }), 'omr', 'alice', 'bob'),
    ).toBe(0);
  });
});

describe('outstandingForPairFils — garbage rows', () => {
  test('whole-subunit net × scale is exact (no float residue)', () => {
    expect(
      outstandingForPairFils(net('OMR', { alice: '-2.900', bob: '2.900' }), 'OMR', 'alice', 'bob'),
    ).toBe(2900);
  });

  test('legacy sub-subunit residue FLOORS toward zero — the cap never grows', () => {
    // 2.9005 OMR → 2900.5 fils → 2900, never 2901
    expect(
      outstandingForPairFils(net('OMR', { alice: '-2.9005', bob: '2.9005' }), 'OMR', 'alice', 'bob'),
    ).toBe(2900);
  });
});

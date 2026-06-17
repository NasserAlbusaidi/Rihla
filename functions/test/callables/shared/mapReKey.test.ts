// RED → GREEN: #278 claim/merge PR6. Restores the SUM-on-collision map
// re-keyer `mergeUidMapKey` that #441 PR5 (c009b700) deleted along with the
// cross-UID merge engine. It is the SUM sibling of deleteAccount.ts's
// `renameMapKey` (OVERWRITE): when a claim re-keys a shadow uuid to the
// claimer's uid and BOTH already hold a slice in one expense's
// `splitDistribution`, the values must SUM (D2) — an overwrite would silently
// delete money. PR7 imports it for `splitDistribution` ONLY.
//
// This is a PURE function (no Firestore), but it runs under the same emulator
// harness as the rest of the callable suite for consistency (bare `npm test`
// hangs without the emulator — see CLAUDE.md).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/mapReKey.test.ts" npm run test:emulator`

import { mergeUidMapKey, toFiniteNumber } from '../../../src/callables/shared/mapReKey';

describe('mergeUidMapKey — SUM-on-collision map re-keyer (#278 PR6)', () => {
  it('a: no collision (claimer absent) → plain rename', () => {
    expect(mergeUidMapKey({ shadow: 5, x: 3 }, 'shadow', 'ali')).toEqual({
      value: { ali: 5, x: 3 },
      changed: true,
    });
  });

  it('b: collision (claimer already a key) → values SUM, money not lost', () => {
    expect(mergeUidMapKey({ shadow: 5, ali: 4, x: 3 }, 'shadow', 'ali')).toEqual({
      value: { ali: 9, x: 3 },
      changed: true,
    });
  });

  it('c: claimer-is-the-only-other-key (exact subunit encoding) → SUM', () => {
    expect(mergeUidMapKey({ shadow: 6000, ali: 6000 }, 'shadow', 'ali')).toEqual({
      value: { ali: 12000 },
      changed: true,
    });
  });

  it('d: oldUid absent entirely → unchanged passthrough, changed:false', () => {
    expect(mergeUidMapKey({ x: 3, ali: 4 }, 'shadow', 'ali')).toEqual({
      value: { x: 3, ali: 4 },
      changed: false,
    });
  });

  it('e: percent encoding (humanPercent×1000) → SUM to 100%', () => {
    expect(mergeUidMapKey({ shadow: 40000, ali: 60000 }, 'shadow', 'ali')).toEqual({
      value: { ali: 100000 },
      changed: true,
    });
  });

  it('f: shares encoding (raw weights) → SUM', () => {
    expect(mergeUidMapKey({ shadow: 2, ali: 1, x: 1 }, 'shadow', 'ali')).toEqual({
      value: { ali: 3, x: 1 },
      changed: true,
    });
  });

  it('g: forged non-numeric collision value → toFiniteNumber zeroes it (0+5)', () => {
    expect(mergeUidMapKey({ shadow: 5, ali: 'bad' }, 'shadow', 'ali')).toEqual({
      value: { ali: 5 },
      changed: true,
    });
  });

  it('h: forged non-numeric oldUid value → 4+0, no NaN', () => {
    expect(mergeUidMapKey({ shadow: 'bad', ali: 4 }, 'shadow', 'ali')).toEqual({
      value: { ali: 4 },
      changed: true,
    });
  });

  it('i: non-map input (null / array / string) → null', () => {
    expect(mergeUidMapKey(null, 'shadow', 'ali')).toBeNull();
    expect(mergeUidMapKey([1, 2], 'shadow', 'ali')).toBeNull();
    expect(mergeUidMapKey('x', 'shadow', 'ali')).toBeNull();
  });

  it('j: empty map → empty, changed:false', () => {
    expect(mergeUidMapKey({}, 'shadow', 'ali')).toEqual({
      value: {},
      changed: false,
    });
  });

  it('k: oldUid === newUid → defensive no-op, MUST NOT double (5 stays 5)', () => {
    expect(mergeUidMapKey({ ali: 5, x: 3 }, 'ali', 'ali')).toEqual({
      value: { ali: 5, x: 3 },
      changed: false,
    });
  });

  it('does not mutate the input map (immutability)', () => {
    const input = { shadow: 5, ali: 4 };
    mergeUidMapKey(input, 'shadow', 'ali');
    expect(input).toEqual({ shadow: 5, ali: 4 });
  });
});

describe('toFiniteNumber — forged-value guard (#278 PR6)', () => {
  it('passes through finite numbers', () => {
    expect(toFiniteNumber(5)).toBe(5);
    expect(toFiniteNumber(0)).toBe(0);
    expect(toFiniteNumber(-12000)).toBe(-12000);
  });

  it('zeroes non-numbers / NaN / Infinity (never emits NaN)', () => {
    expect(toFiniteNumber('5')).toBe(0);
    expect(toFiniteNumber(NaN)).toBe(0);
    expect(toFiniteNumber(Infinity)).toBe(0);
    expect(toFiniteNumber(null)).toBe(0);
    expect(toFiniteNumber(undefined)).toBe(0);
    expect(toFiniteNumber({})).toBe(0);
  });
});

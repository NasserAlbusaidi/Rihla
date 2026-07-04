// RED → GREEN: #889 correction marker foundation — pure-function coverage of
// the shared classifier module (no Firestore). Runs under the same emulator
// harness as the rest of the callable suite for consistency (bare `npm test`
// hangs without the emulator — see CLAUDE.md).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/settlementCorrection.test.ts" npm run test:emulator`

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  CORRECTION_NOTE_SENTINELS,
  buildEventReverseData,
  buildGroupReverseData,
  directReverseId,
  hasLiveLegacyCorrectionOf,
  isExactInverseMoney,
  isExpectedReverse,
  isItselfLegacyCorrection,
  isLegacyCorrectionPair,
  isMarkedCorrection,
  isSentinelNote,
  logicalReverseId,
  normalizeCorrectionNote,
  normalizedGroupSettleUpId,
} from '../../../src/callables/shared/settlementCorrection';

const EN_ARB = resolve(__dirname, '../../../../lib/l10n/app_en.arb');
const AR_ARB = resolve(__dirname, '../../../../lib/l10n/app_ar.arb');

function arbValue(path: string, key: string): string {
  const arb = JSON.parse(readFileSync(path, 'utf8'));
  const value = arb[key];
  if (typeof value !== 'string') {
    throw new Error(`${key} missing from ${path}`);
  }
  return value;
}

describe('CORRECTION_NOTE_SENTINELS — cross-list guard (#889)', () => {
  test('EN/AR frozen constants equal the current shipped ARB strings', () => {
    expect(CORRECTION_NOTE_SENTINELS).toContain(arbValue(EN_ARB, 'settleUpCorrectionNote'));
    expect(CORRECTION_NOTE_SENTINELS).toContain(arbValue(AR_ARB, 'settleUpCorrectionNote'));
    expect(CORRECTION_NOTE_SENTINELS).toHaveLength(2);
  });
});

describe('normalizeCorrectionNote — generic free-text bounds ONLY', () => {
  test('non-string throws invalid-argument', () => {
    expect(() => normalizeCorrectionNote(undefined)).toThrow(/must be a string/);
  });

  test('empty / whitespace-only throws', () => {
    expect(() => normalizeCorrectionNote('')).toThrow(/must not be empty/);
    expect(() => normalizeCorrectionNote('   ')).toThrow(/must not be empty/);
  });

  test('over 280 chars throws', () => {
    expect(() => normalizeCorrectionNote('x'.repeat(281))).toThrow(/280 characters/);
  });

  test('control character throws', () => {
    expect(() => normalizeCorrectionNote('bad\x01note')).toThrow(/invalid characters/);
  });

  test('a NON-sentinel note is ACCEPTED and returned verbatim (untrimmed)', () => {
    expect(normalizeCorrectionNote('  paid you back  ')).toBe('  paid you back  ');
  });

  test('a sentinel note is also accepted verbatim — the note is never validated against the sentinel set', () => {
    expect(normalizeCorrectionNote(CORRECTION_NOTE_SENTINELS[0])).toBe(CORRECTION_NOTE_SENTINELS[0]);
  });
});

describe('isSentinelNote / isMarkedCorrection / normalizedGroupSettleUpId', () => {
  test('isSentinelNote matches only the frozen EN/AR strings', () => {
    expect(isSentinelNote(CORRECTION_NOTE_SENTINELS[0])).toBe(true);
    expect(isSentinelNote(CORRECTION_NOTE_SENTINELS[1])).toBe(true);
    expect(isSentinelNote('Correction of a recorded payment ')).toBe(false); // trailing space
    expect(isSentinelNote('random note')).toBe(false);
    expect(isSentinelNote(null)).toBe(false);
  });

  test('isMarkedCorrection: absent / non-string / blank → false; non-blank string → true', () => {
    expect(isMarkedCorrection({})).toBe(false);
    expect(isMarkedCorrection({ correctionOfSettlementId: null })).toBe(false);
    expect(isMarkedCorrection({ correctionOfSettlementId: '' })).toBe(false);
    expect(isMarkedCorrection({ correctionOfSettlementId: '   ' })).toBe(false);
    expect(isMarkedCorrection({ correctionOfSettlementId: 42 })).toBe(false);
    expect(isMarkedCorrection({ correctionOfSettlementId: 'orig1' })).toBe(true);
  });

  test('normalizedGroupSettleUpId: absent/blank → null; non-blank → the string', () => {
    expect(normalizedGroupSettleUpId({})).toBeNull();
    expect(normalizedGroupSettleUpId({ groupSettleUpId: '' })).toBeNull();
    expect(normalizedGroupSettleUpId({ groupSettleUpId: '   ' })).toBeNull();
    expect(normalizedGroupSettleUpId({ groupSettleUpId: 'su-1' })).toBe('su-1');
  });
});

const A = { payerParticipantId: 'p', recipientParticipantId: 'r', amountFils: 5000, currency: 'OMR' };
const B_INVERSE = { payerParticipantId: 'r', recipientParticipantId: 'p', amountFils: 5000, currency: 'OMR' };

describe('isExactInverseMoney', () => {
  test('symmetric exact inverse → true both directions', () => {
    expect(isExactInverseMoney(A, B_INVERSE)).toBe(true);
    expect(isExactInverseMoney(B_INVERSE, A)).toBe(true);
  });

  test('same parties (not swapped) → false', () => {
    expect(isExactInverseMoney(A, A)).toBe(false);
  });

  test('different amount → false', () => {
    expect(isExactInverseMoney(A, { ...B_INVERSE, amountFils: 4999 })).toBe(false);
  });

  test('different currency → false', () => {
    expect(isExactInverseMoney(A, { ...B_INVERSE, currency: 'USD' })).toBe(false);
  });
});

describe('isLegacyCorrectionPair — bounded legacy note-only classifier', () => {
  const source = { ...A, isDeleted: false, deletedAt: null, note: 'dinner' };
  const legacyCorrection = {
    ...B_INVERSE,
    isDeleted: false,
    deletedAt: null,
    note: CORRECTION_NOTE_SENTINELS[0],
  };

  test('sentinel-note exact inverse of a live unmarked non-sentinel source → true', () => {
    expect(isLegacyCorrectionPair(legacyCorrection, source)).toBe(true);
  });

  test('non-sentinel correction note → false (a real independent offsetting payment is NOT a correction)', () => {
    expect(isLegacyCorrectionPair({ ...legacyCorrection, note: 'paid back' }, source)).toBe(false);
  });

  test('source itself carries the sentinel → false (source must be non-sentinel)', () => {
    expect(isLegacyCorrectionPair(legacyCorrection, { ...source, note: CORRECTION_NOTE_SENTINELS[1] })).toBe(false);
  });

  test('deleted correction or deleted source → false', () => {
    expect(isLegacyCorrectionPair({ ...legacyCorrection, isDeleted: true }, source)).toBe(false);
    expect(isLegacyCorrectionPair(legacyCorrection, { ...source, isDeleted: true })).toBe(false);
  });

  test('marked source (already has a marker reverse) → false', () => {
    expect(
      isLegacyCorrectionPair(legacyCorrection, { ...source, correctionOfSettlementId: 'x' }),
    ).toBe(false);
  });

  test('mismatched groupSettleUpId state → false; matching state → true', () => {
    expect(
      isLegacyCorrectionPair(
        { ...legacyCorrection, groupSettleUpId: 'su-1' },
        source,
      ),
    ).toBe(false);
    expect(
      isLegacyCorrectionPair(
        { ...legacyCorrection, groupSettleUpId: 'su-1' },
        { ...source, groupSettleUpId: 'su-1' },
      ),
    ).toBe(true);
  });

  test('isItselfLegacyCorrection / hasLiveLegacyCorrectionOf wrap the pairing in both directions', () => {
    expect(isItselfLegacyCorrection(legacyCorrection, [source])).toBe(true);
    expect(isItselfLegacyCorrection(source, [legacyCorrection])).toBe(false);
    expect(hasLiveLegacyCorrectionOf(source, [legacyCorrection])).toBe(true);
    expect(hasLiveLegacyCorrectionOf(legacyCorrection, [source])).toBe(false);
  });
});

describe('isExpectedReverse — idempotency validator', () => {
  const original = { ...A, isDeleted: false, deletedAt: null };
  const reverse = { ...B_INVERSE, isDeleted: false, deletedAt: null, correctionOfSettlementId: 'orig1' };

  test('valid expected reverse → true', () => {
    expect(isExpectedReverse(reverse, 'orig1', original)).toBe(true);
  });

  test('wrong correctionOfSettlementId → false', () => {
    expect(isExpectedReverse(reverse, 'someone-else', original)).toBe(false);
  });

  test('not an exact inverse → false', () => {
    expect(isExpectedReverse({ ...reverse, amountFils: 1 }, 'orig1', original)).toBe(false);
  });

  test('does NOT require createdBy == callerUid or note == correctionNote (retry by a different member/locale stays idempotent)', () => {
    expect(
      isExpectedReverse(
        { ...reverse, createdBy: 'someone-else', note: 'تصحيح لدفعة مُسجَّلة' },
        'orig1',
        original,
      ),
    ).toBe(true);
  });

  test('deleted reverse → false', () => {
    expect(isExpectedReverse({ ...reverse, isDeleted: true }, 'orig1', original)).toBe(false);
  });
});

describe('directReverseId / logicalReverseId — deterministic, path-safe, bounded', () => {
  test('directReverseId is deterministic and path-safe', () => {
    const id = directReverseId('groups/g1/events/e1/settlements/s1');
    expect(id).toMatch(/^correction_[0-9a-f]{16,}$/);
    expect(id).toBe(directReverseId('groups/g1/events/e1/settlements/s1'));
    expect(id).not.toContain('/');
  });

  test('different original paths → different ids', () => {
    expect(directReverseId('groups/g1/events/e1/settlements/s1'))
      .not.toBe(directReverseId('groups/g1/events/e1/settlements/s2'));
  });

  test('logicalReverseId is deterministic, path-safe, and scoped by groupSettleUpId AND original path', () => {
    const id = logicalReverseId('su-1', 'groups/g1/events/e1/settlements/s1');
    expect(id).toMatch(/^correction_[0-9a-f]{16,}_[0-9a-f]{16,}$/);
    expect(id).toBe(logicalReverseId('su-1', 'groups/g1/events/e1/settlements/s1'));
    expect(id).not.toBe(logicalReverseId('su-2', 'groups/g1/events/e1/settlements/s1'));
    expect(id).not.toContain('/');
  });
});

describe('buildEventReverseData / buildGroupReverseData — exact reverse map shapes', () => {
  const originalData = {
    payerParticipantId: 'payer',
    recipientParticipantId: 'recipient',
    payerName: 'Payer',
    recipientName: 'Recipient',
    amountFils: 5000,
    currency: 'OMR',
  };

  test('event reverse map: swapped parties, verbatim note, marker set, groupSettleUpId omitted when absent', () => {
    const data = buildEventReverseData('e1', {
      newId: 'correction_abc',
      originalId: 'orig1',
      originalData,
      correctionNote: 'Correction of a recorded payment',
      callerUid: 'caller',
      nowIso: '2026-07-04T00:00:00.000Z',
    });
    expect(data).toEqual({
      id: 'correction_abc',
      eventId: 'e1',
      payerParticipantId: 'recipient',
      recipientParticipantId: 'payer',
      payerName: 'Recipient',
      recipientName: 'Payer',
      amountFils: 5000,
      currency: 'OMR',
      note: 'Correction of a recorded payment',
      isDeleted: false,
      deletedAt: null,
      settledAt: '2026-07-04T00:00:00.000Z',
      createdBy: 'caller',
      correctionOfSettlementId: 'orig1',
    });
    expect('groupSettleUpId' in data).toBe(false);
  });

  test('event reverse map preserves a present groupSettleUpId', () => {
    const data = buildEventReverseData('e1', {
      newId: 'correction_abc',
      originalId: 'orig1',
      originalData: { ...originalData, groupSettleUpId: 'su-1' },
      correctionNote: 'note',
      callerUid: 'caller',
      nowIso: '2026-07-04T00:00:00.000Z',
    });
    expect(data.groupSettleUpId).toBe('su-1');
  });

  test('group reverse map carries groupId/eventId=groupId/scope=group', () => {
    const data = buildGroupReverseData('g1', {
      newId: 'correction_def',
      originalId: 'orig2',
      originalData,
      correctionNote: 'note',
      callerUid: 'caller',
      nowIso: '2026-07-04T00:00:00.000Z',
    });
    expect(data).toMatchObject({
      id: 'correction_def',
      groupId: 'g1',
      eventId: 'g1',
      scope: 'group',
      payerParticipantId: 'recipient',
      recipientParticipantId: 'payer',
      correctionOfSettlementId: 'orig2',
    });
  });
});

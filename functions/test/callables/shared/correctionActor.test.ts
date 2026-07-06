// RED → GREEN: correction actor policy — pure-function coverage of the shared
// creator-or-party guard (no Firestore). Runs under the same emulator harness
// as the rest of the callable suite for consistency (bare `npm test` hangs
// without the emulator — see CLAUDE.md).
//
// kind: functions-jest (Firestore emulator + firebase-functions-test, Java 21)
// runCommand: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/shared/correctionActor.test.ts" npm run test:emulator`

import { assertCorrectionActor } from '../../../src/callables/shared/correctionActor';

const UID = 'caller-uid';
const OTHER = 'other-uid';
const SHADOW_UUID = '7f3b2a10-9c4d-4e8f-b1a2-3d5c6e7f8a9b';

function settlement(payer: unknown, recipient: unknown): Record<string, unknown> {
  return { payerParticipantId: payer, recipientParticipantId: recipient };
}

describe('assertCorrectionActor — creator branch', () => {
  test('caller == createdBy passes even when not a party', () => {
    expect(() =>
      assertCorrectionActor(UID, UID, [settlement(OTHER, SHADOW_UUID)]),
    ).not.toThrow();
  });

  test('null/undefined/non-string createdBy never matches', () => {
    for (const createdBy of [null, undefined, 42, { uid: UID }]) {
      expect(() =>
        assertCorrectionActor(UID, createdBy, [settlement(OTHER, SHADOW_UUID)]),
      ).toThrow(expect.objectContaining({ code: 'permission-denied' }));
    }
  });
});

describe('assertCorrectionActor — party branch', () => {
  test('payer on every original passes', () => {
    expect(() =>
      assertCorrectionActor(UID, OTHER, [
        settlement(UID, OTHER),
        settlement(UID, SHADOW_UUID),
      ]),
    ).not.toThrow();
  });

  test('recipient on every original passes', () => {
    expect(() =>
      assertCorrectionActor(UID, OTHER, [settlement(SHADOW_UUID, UID)]),
    ).not.toThrow();
  });

  test('party on some but not all originals is denied', () => {
    expect(() =>
      assertCorrectionActor(UID, OTHER, [
        settlement(UID, OTHER),
        settlement(SHADOW_UUID, OTHER),
      ]),
    ).toThrow(expect.objectContaining({ code: 'permission-denied' }));
  });

  test('neither party nor creator is denied', () => {
    expect(() =>
      assertCorrectionActor(UID, OTHER, [settlement(OTHER, SHADOW_UUID)]),
    ).toThrow(expect.objectContaining({ code: 'permission-denied' }));
  });

  test('null / absent / non-string participant fields never match', () => {
    for (const doc of [
      settlement(null, null),
      settlement(undefined, undefined),
      {},
      settlement(42, ['x']),
    ]) {
      expect(() => assertCorrectionActor(UID, OTHER, [doc])).toThrow(
        expect.objectContaining({ code: 'permission-denied' }),
      );
    }
  });

  test('a shadow uuid party can never be satisfied by a different auth uid', () => {
    expect(() =>
      assertCorrectionActor(UID, OTHER, [settlement(SHADOW_UUID, OTHER)]),
    ).toThrow(expect.objectContaining({ code: 'permission-denied' }));
  });

  test('empty originals list is denied (defensive — callers guard not-found first)', () => {
    expect(() => assertCorrectionActor(UID, OTHER, [])).toThrow(
      expect.objectContaining({ code: 'permission-denied' }),
    );
  });
});

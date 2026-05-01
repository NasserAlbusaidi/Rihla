import { seedGroupWithEvent, clearFirestore } from '../fixtures';
import { assertMemberOfEvent } from '../../src/lib/membership';

beforeEach(async () => { await clearFirestore(); });
afterAll(async () => { await clearFirestore(); });

describe('assertMemberOfEvent', () => {
  test('throws not-found when group missing', async () => {
    await expect(assertMemberOfEvent('alice', 'gX', 'eX')).rejects.toMatchObject({ code: 'not-found' });
  });

  test('throws not-found when event missing', async () => {
    const { getFirestore } = await import('firebase-admin/firestore');
    await getFirestore().doc('groups/g1').set({ memberIds: ['alice'] });
    await expect(assertMemberOfEvent('alice', 'g1', 'eX')).rejects.toMatchObject({ code: 'not-found' });
  });

  test('throws permission-denied when uid not in memberIds', async () => {
    await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
    await expect(assertMemberOfEvent('eve', 'g1', 'e1')).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('throws permission-denied when uid is group member but not event participant', async () => {
    const { getFirestore } = await import('firebase-admin/firestore');
    await getFirestore().doc('groups/g1').set({ memberIds: ['alice', 'bob'] });
    await getFirestore().doc('groups/g1/events/e1').set({ participantIds: ['alice'] });

    await expect(assertMemberOfEvent('bob', 'g1', 'e1')).rejects.toMatchObject({ code: 'permission-denied' });
  });

  test('resolves when uid is member and event participant', async () => {
    await seedGroupWithEvent({ groupId: 'g1', eventId: 'e1', memberIds: ['alice'] });
    await expect(assertMemberOfEvent('alice', 'g1', 'e1')).resolves.toBeUndefined();
  });
});

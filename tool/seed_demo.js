// Seed the curated marketing demo group into the Firebase emulator.
//
// Ports the `_seed` fixture from integration_test/marketing_shots_test.dart so a
// manually-driven app (installed debug build pointed at the emulator) shows the
// same demo content the automated capture used. Writes under the app's live anon
// uid so the home query (`groups where memberIds arrayContains uid`) matches.
//
// Usage (run from functions/ so firebase-admin resolves):
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
//   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   GCLOUD_PROJECT=rihla-safar \
//   node ../tool/seed_demo.js <uid> <en|ar>

const admin = require('firebase-admin');

const uidArg = process.argv[2];
const localeCode = (process.argv[3] || 'en').toLowerCase();

const GID = 'demo_grp_rihla';
const EID = 'demo_evt_salalah';
const SARA = 'demo_uid_sara';
const KHALID = 'demo_uid_khalid';
const MAHA = 'demo_uid_maha';

const LOC = {
  en: {
    me: 'Nasser', sara: 'Sara', khalid: 'Khalid', maha: 'Maha',
    groupName: 'The Crew',
    eventName: 'Salalah Khareef Trip',
    eventDesc: 'Three nights chasing the khareef mist.',
    dinner: 'Dinner at the souq', fuel: 'Fuel for the drive',
    chalet: 'Mountain chalet (2 nights)', kayak: 'Wadi kayaking',
    groceries: 'Groceries run', coffee: 'Coffee & karak',
    actEvent: 'created Salalah Khareef Trip', actJoin: 'joined the group',
    actSettle: 'settled OMR 20.000 with Khalid',
  },
  ar: {
    me: 'ناصر', sara: 'سارة', khalid: 'خالد', maha: 'مها',
    groupName: 'الشلة',
    eventName: 'رحلة خريف صلالة',
    eventDesc: 'ثلاث ليالٍ خلف ضباب الخريف.',
    dinner: 'عشاء في السوق', fuel: 'وقود الطريق',
    chalet: 'شاليه جبلي (ليلتان)', kayak: 'تجديف في الوادي',
    groceries: 'تسوق البقالة', coffee: 'قهوة وكرك',
    actEvent: 'أنشأ رحلة خريف صلالة', actJoin: 'انضم إلى المجموعة',
    actSettle: 'سدّد 20.000 ر.ع. مع خالد',
  },
}[localeCode === 'ar' ? 'ar' : 'en'];

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'rihla-safar' });
const db = admin.firestore();
const TS = admin.firestore.Timestamp;
const FV = admin.firestore.FieldValue;

// Resolve the app's anon uid: explicit arg, or auto-detect the newest
// anonymous user (no email, no linked providers) in the auth emulator.
async function resolveUid(arg) {
  if (arg && arg !== 'auto') return arg;
  const res = await admin.auth().listUsers(1000);
  const anons = res.users.filter(
    (u) => !u.email && (!u.providerData || u.providerData.length === 0),
  );
  if (!anons.length) throw new Error('no anonymous user found in auth emulator');
  anons.sort(
    (a, b) => new Date(b.metadata.creationTime) - new Date(a.metadata.creationTime),
  );
  return anons[0].uid;
}

const isoUtc = (d, h) => new Date(Date.UTC(2026, 5, d, h)).toISOString();

async function main() {
  const uid = await resolveUid(uidArg);
  const ts = TS.fromDate(new Date(Date.UTC(2026, 5, 12, 9))); // months are 0-based
  const names = { [uid]: LOC.me, [SARA]: LOC.sara, [KHALID]: LOC.khalid, [MAHA]: LOC.maha };
  const memberIds = [uid, SARA, KHALID, MAHA];

  const group = db.collection('groups').doc(GID);

  await group.set({
    id: GID, name: LOC.groupName, inviteCode: 'KHAR26', createdBy: uid,
    memberIds, currency: 'OMR', createdAt: ts, updatedAt: ts,
  });

  for (const [memberId, displayName] of Object.entries(names)) {
    await group.collection('members').doc(memberId).set({
      id: memberId, userId: memberId, displayName,
      role: memberId === uid ? 'CREATOR' : 'MEMBER', isShadow: false, joinedAt: ts,
    });
  }

  const event = group.collection('events').doc(EID);
  await event.set({
    name: LOC.eventName, type: 'trip', groupId: GID, createdBy: uid,
    participantIds: memberIds, participantNames: names,
    modules: { ledger: true },
    startDate: TS.fromDate(new Date(Date.UTC(2026, 5, 12))),
    endDate: TS.fromDate(new Date(Date.UTC(2026, 5, 15))),
    isDeleted: false, deletedAt: null,
    createdAt: new Date(Date.UTC(2026, 5, 12, 9)).toISOString(),
    serverCreatedAt: FV.serverTimestamp(), updatedAt: null,
    description: LOC.eventDesc,
  });

  const expenses = [
    ['demo_exp_1', uid, 45500, LOC.dinner, 'food', 12, 5],
    ['demo_exp_2', SARA, 30000, LOC.fuel, 'transport', 12, 18],
    ['demo_exp_3', KHALID, 120000, LOC.chalet, 'accommodation', 13, 9],
    ['demo_exp_4', MAHA, 24750, LOC.kayak, 'activities', 13, 16],
    ['demo_exp_5', uid, 18500, LOC.groceries, 'shopping', 14, 8],
    ['demo_exp_6', SARA, 12000, LOC.coffee, 'food', 14, 20],
  ];
  for (const [id, payer, fils, desc, category, day, hour] of expenses) {
    await event.collection('expenses').doc(id).set({
      id, eventId: EID, payerParticipantId: payer, amountFils: fils,
      currency: 'OMR', description: desc, scope: 'global', subGroupId: null,
      // Omit customSplitParticipants (null) for global/equal split so the ledger
      // row falls back to participantCount and shows "split 4 ways" rather than
      // "0 ways". (The real app writes [] here — a separate display bug.)
      receiptUrl: null, categoryId: category,
      note: null, isDeleted: false, deletedAt: null,
      createdAt: isoUtc(day, hour), createdBy: uid,
    });
  }

  await event.collection('settlements').doc('demo_evt_set_1').set({
    id: 'demo_evt_set_1', eventId: EID, createdBy: uid,
    payerParticipantId: MAHA, recipientParticipantId: KHALID,
    amountFils: 20000, currency: 'OMR', note: null,
    isDeleted: false, deletedAt: null, settledAt: isoUtc(14, 21),
  });

  const activity = group.collection('activity');
  await activity.doc('demo_act_1').set({
    id: 'demo_act_1', type: 'event_created', actorId: uid, actorName: LOC.me,
    description: LOC.actEvent, metadata: { eventId: EID, eventName: LOC.eventName },
    timestamp: new Date(Date.UTC(2026, 5, 12, 9, 5)).toISOString(),
  });
  await activity.doc('demo_act_2').set({
    id: 'demo_act_2', type: 'member_joined', actorId: SARA, actorName: LOC.sara,
    description: LOC.actJoin, metadata: {},
    timestamp: new Date(Date.UTC(2026, 5, 12, 10, 30)).toISOString(),
  });
  await activity.doc('demo_act_3').set({
    id: 'demo_act_3', type: 'group_settlement', actorId: MAHA, actorName: LOC.maha,
    description: LOC.actSettle, metadata: { amount: '20.000', recipientId: KHALID },
    timestamp: new Date(Date.UTC(2026, 5, 14, 21, 0)).toISOString(),
  });

  console.log(`seeded locale=${localeCode} under uid=${uid}: 1 group, 4 members, 1 event, 6 expenses, 1 settlement, 3 activity`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });

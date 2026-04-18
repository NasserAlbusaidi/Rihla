import {
  initializeTestEnvironment,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';

// Inline tightened rules — matches the final shape planned for Plan 04.
// This test proves the RULE BEHAVIOR is correct before Plan 04 swaps the
// live security/storage.rules file. When Plan 04 ships, update this suite
// to read the real file path instead of this inline string.
const TIGHTENED_RULES = `
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /trip-documents/{eventId}/{allPaths=**} {
      allow read, write: if false;
    }
    match /trip-memories/{eventId}/{allPaths=**} {
      allow read, write: if false;
    }
    match /receipts/{eventId}/{allPaths=**} {
      allow read, write: if false;
    }
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
`;

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'rihla-safar-rules-test',
    storage: { rules: TIGHTENED_RULES, host: '127.0.0.1', port: 9199 },
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

describe('Storage rules — direct SDK access (INFRA-01 #3)', () => {
  test('anonymous read trip-documents denied', async () => {
    const ctx = testEnv.unauthenticatedContext();
    const ref = ctx.storage().ref('trip-documents/e1/x.pdf');
    await assertFails(ref.getDownloadURL());
  });

  test('authenticated write trip-memories denied', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    const ref = ctx.storage().ref('trip-memories/e1/y.jpg');
    // UploadTask is thenable; wrap as a real Promise for assertFails typing.
    const upload = (async () => ref.putString('hello'))();
    await assertFails(upload);
  });

  test('authenticated delete receipts denied', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    const ref = ctx.storage().ref('receipts/e1/exp1/z.png');
    await assertFails(ref.delete());
  });

  test('authenticated read non-trip path denied (default deny)', async () => {
    const ctx = testEnv.authenticatedContext('alice');
    const ref = ctx.storage().ref('other/random/file');
    await assertFails(ref.getDownloadURL());
  });
});

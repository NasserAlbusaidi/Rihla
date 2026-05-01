import {
  initializeTestEnvironment,
  assertFails,
  RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const RULES_PATH = resolve(__dirname, '../../security/storage.rules');

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'rihla-safar-rules-test',
    storage: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
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

import { assertEmulatorEnv } from './emulatorEnvGuard';

describe('assertEmulatorEnv (#1157 fail-fast guard)', () => {
  const injected = {
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18080',
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19099',
  };

  it('passes when both emulator hosts are injected', () => {
    expect(() => assertEmulatorEnv(injected)).not.toThrow();
  });

  it.each([['FIRESTORE_EMULATOR_HOST'], ['FIREBASE_AUTH_EMULATOR_HOST']])(
    'throws with run instructions when %s is missing',
    (missing) => {
      const env: NodeJS.ProcessEnv = { ...injected, [missing]: undefined };
      expect(() => assertEmulatorEnv(env)).toThrow(/test:emulator/);
      expect(() => assertEmulatorEnv(env)).toThrow(new RegExp(missing));
    },
  );

  it('treats an empty-string host as missing, not as configured', () => {
    expect(() =>
      assertEmulatorEnv({ ...injected, FIRESTORE_EMULATOR_HOST: '' }),
    ).toThrow(/FIRESTORE_EMULATOR_HOST/);
  });
});

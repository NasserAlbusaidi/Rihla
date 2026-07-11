const REQUIRED_EMULATOR_HOSTS = [
  'FIRESTORE_EMULATOR_HOST',
  'FIREBASE_AUTH_EMULATOR_HOST',
] as const;

/**
 * Functions tests must run under tool/run_firebase_emulator_tests.sh
 * (`npm run test:emulator`), which starts a private emulator pair on
 * per-invocation free ports and injects these hosts. A silent 127.0.0.1
 * default here once let bare jest runs adopt whatever emulator happened to
 * be listening — two jest runtimes sharing one Firestore instance produced
 * the nondeterministic claimShadow failures in #1157.
 */
export function assertEmulatorEnv(env: NodeJS.ProcessEnv): void {
  for (const name of REQUIRED_EMULATOR_HOSTS) {
    if (!env[name]) {
      throw new Error(
        `${name} is not set. Run functions tests via \`npm run test:emulator\` ` +
          '(tool/run_firebase_emulator_tests.sh); a bare jest run would hang or ' +
          'silently connect to an unrelated already-running emulator and ' +
          'cross-contaminate its data (#1157).',
      );
    }
  }
}

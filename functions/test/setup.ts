import { assertEmulatorEnv } from './emulatorEnvGuard';

// Fail fast instead of defaulting to 127.0.0.1:8080/9099 — see #1157.
assertEmulatorEnv(process.env);
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.GCLOUD_PROJECT = 'rihla-safar-test';

/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['<rootDir>/test/**/*.test.ts'],
  setupFiles: ['<rootDir>/test/setup.ts'],
  collectCoverageFrom: [
    'src/**/*.ts',
    '!src/**/*.d.ts',
    '!src/index.ts'
  ],
  // Ratchet floors: baseline 2026-07-12 was lines 94.5 / branches 82.0 /
  // functions 98.7 (full suite via test:emulator). Floor = baseline − 2pp;
  // raise when the baseline improves, never lower to admit an under-tested PR.
  // Only enforced when jest runs with --coverage — readiness CI passes it.
  coverageThreshold: {
    global: { branches: 80, functions: 96, lines: 92, statements: 92 },
    'src/callables/shared/': { branches: 85, functions: 96, lines: 92, statements: 92 }
  },
  testTimeout: 30000
};

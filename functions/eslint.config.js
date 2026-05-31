const js = require('@eslint/js');
const tseslint = require('typescript-eslint');

// Flat config (ESLint 9). Replaces the stranded .eslintrc.js that referenced an
// uninstalled parser. Non-type-checked recommended set: fast enough for CI, no
// tsconfig project wiring, still catches the bug classes that matter on
// money/identity Functions code (unused vars, unsafe shadowing, no-floating-style
// mistakes the compiler misses). `tsc` (strict) already covers type safety.
module.exports = tseslint.config(
  { ignores: ['lib/**', 'node_modules/**'] },
  {
    files: ['**/*.ts'],
    extends: [js.configs.recommended, ...tseslint.configs.recommended],
    rules: {
      quotes: ['error', 'single', { avoidEscape: true }],
    },
  },
);

module.exports = {
  root: true,
  env: { es6: true, node: true },
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 2020, sourceType: 'module' },
  ignorePatterns: ['/lib/**/*', '/node_modules/**/*'],
  rules: { quotes: ['error', 'single'] }
};

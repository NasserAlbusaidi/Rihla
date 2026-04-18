# Patterns & Priorities

## Cross-Cutting Patterns Observed

### Error handling is optimistic to a fault
The app assumes every Firestore operation succeeds. When operations fail, the typical pattern is either catch-and-swallow or catch-and-debugPrint. The user almost never sees an error message. Works perfectly on fast connections. On flaky connections, the app becomes a silent data loss machine.

### Careful where it matters most (money), careless where it matters second-most (security)
The Decimal-everywhere approach is excellent. MoneySerializer with integer fils storage is correct. BalanceCalculator tests are thorough. But the security rules were written to get things working and never tightened. Storage rules are essentially `allow all`.

### Clean macro architecture, messy micro level
Feature-first directory structure is solid. Provider patterns are consistent. But individual screens grow unbounded (5 over 600 lines), shared widgets don't use the spacing tokens they were designed to use, and two cache implementations coexist with subtly different behavior.

### Tests optimize for easy, not risky
Pure functions (BalanceCalculator, MoneySerializer, formatters) are thoroughly tested. Screens, error paths, security rules, and concurrent operations have zero tests. Coverage is high where risk is low.

### Immutability stated but not enforced
CLAUDE.md says "Immutability is non-negotiable" but `group_balance_provider.dart`, `dashboard_providers.dart`, `group_activity_screen.dart`, and multiple other files build mutable lists via `.add()` and `.sort()` in provider bodies. Data models are properly immutable (const constructors, copyWith). The computation layer is not.

## Recommended Fix Order

| Priority | Area | Why |
|----------|------|-----|
| 1 | Security rules | Only things exploitable by someone outside the app |
| 2 | Split rounding + wrong user balance | Silently give users wrong financial information — trust-destroying |
| 3 | Silent auth failure | Single line of defense with no fallback |
| 4 | Memory photos | Entire feature doesn't work |
| 5 | Edit expense discarding changes | Form that lies to the user |
| 6+ | Everything else | Quality-of-life and architectural health |

## Key Insight

> The highest-risk code (security rules, auth flow, error recovery) has the lowest test coverage. The lowest-risk code (formatters, model serialization, color token values) has the highest. This is the natural entropy of software projects — we test what's easy to test, not what's dangerous to break. Reversing that tendency is the single highest-leverage improvement this project could make.

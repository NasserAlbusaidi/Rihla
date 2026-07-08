#!/usr/bin/env bash
# tool/check_theme_purity.sh — Phase 37 Wave 5 CI enforcement.
#
# Exits 1 on any violation with file:line output. Five checks:
#   1. Direct AppColorTokens.light.* reads outside lib/core/theme/tokens/
#      (widgets must read via context.colors instead).
#   2. Hardcoded Color(0xFF...) literals outside lib/core/theme/tokens/ without
#      a preceding `// design-token-justified:` comment within 5 lines above.
#   3. `.textMuted` reads outside lib/core/theme/tokens/ without a preceding
#      `// textMuted-decorative-justified:` comment on the line immediately
#      above.
#   4. Direct AppShadowTokens.standard.* reads outside lib/core/theme/tokens/
#      (widgets must read via context.shadows instead).
#   5. Material `Colors.<name>` constants outside lib/core/theme/tokens/ without
#      a preceding `// design-token-justified:` comment within 5 lines above.
#      `Colors.transparent` is allowlisted (it's palette-independent). Use
#      context.colors tokens so light/dark track Theme.of(context).brightness.
#
# Exemption list:
#   lib/core/theme/tokens/*            (source of truth — token files)
#   lib/core/theme/app_theme.dart      (top-level ThemeData assembly — reads
#                                       tokens directly by design)
#   lib/main.dart                      (SystemChrome overlay + _AuthRetryScreen
#                                       run pre-widget-tree / pre-hydration,
#                                       before context.colors is available;
#                                       Plan 01 D-16 / research R6 justify)
set -euo pipefail

EXIT_CODE=0

# ---------------------------------------------------------------------------
# Check 1: Direct AppColorTokens.light.* reads outside tokens/
# ---------------------------------------------------------------------------
echo "Check 1: Direct AppColorTokens.light.* reads outside lib/core/theme/tokens/"
V1=$(grep -rn 'AppColorTokens\.light\.' lib/ \
    --include='*.dart' \
    | grep -v '^lib/core/theme/tokens/' \
    | grep -v '^lib/core/theme/app_theme.dart:' \
    | grep -v '^lib/main.dart:' \
    | grep -v '^lib/core/theme/system_ui_overlay_style.dart:' \
    || true)
    # system_ui_overlay_style.dart is context-free theme infra (like app_theme
    # /main above): it resolves the exact light/dark scaffold background for the
    # SystemChrome overlay during a live appearance switch, where context.colors
    # would return the stale variant. Direct token access is required, not a smell.
if [ -n "$V1" ]; then
  echo "::error::Direct AppColorTokens.light.* reads found. Use context.colors instead."
  echo "$V1"
  EXIT_CODE=1
fi

# ---------------------------------------------------------------------------
# Check 2: Hardcoded Color(0xFF...) literals without justification
# ---------------------------------------------------------------------------
# Look up to 5 lines above the literal for the `// design-token-justified:`
# comment so multiline LinearGradient blocks (where the comment can sit
# 2-4 lines above the first Color literal) are not flagged as violations.
echo "Check 2: Hardcoded Color(0xFF...) literals"
while IFS=: read -r file line _rest; do
  [ -z "$file" ] && continue
  start_line=$((line - 5))
  [ "$start_line" -lt 1 ] && start_line=1
  end_line=$((line - 1))
  if [ "$end_line" -lt 1 ]; then
    echo "$file:$line: Color(0xFF...) at top of file — missing justification"
    EXIT_CODE=1
    continue
  fi
  window=$(sed -n "${start_line},${end_line}p" "$file")
  if ! echo "$window" | grep -q '// design-token-justified:'; then
    echo "$file:$line: Color(0xFF...) literal without // design-token-justified: comment within 5 preceding lines"
    EXIT_CODE=1
  fi
done < <(grep -rn 'Color(0x[0-9A-Fa-f]\{6,8\}' lib/ \
           --include='*.dart' \
           | grep -v '^lib/core/theme/tokens/' \
           | grep -v '^lib/core/theme/app_theme.dart:' \
           | grep -v '^lib/main.dart:')

# ---------------------------------------------------------------------------
# Check 3: textMuted reads without justification
# ---------------------------------------------------------------------------
# Look up to 5 lines above the read for the `// textMuted-decorative-justified:`
# marker. Multi-line justification comments (up to 5-line blocks) must not
# trigger false positives — this matches the window used for Check 2.
echo "Check 3: textMuted use without justification comment"
while IFS=: read -r file line _rest; do
  [ -z "$file" ] && continue
  start_line=$((line - 5))
  [ "$start_line" -lt 1 ] && start_line=1
  end_line=$((line - 1))
  if [ "$end_line" -lt 1 ]; then
    echo "$file:$line: textMuted use at top of file — missing justification"
    EXIT_CODE=1
    continue
  fi
  window=$(sed -n "${start_line},${end_line}p" "$file")
  if ! echo "$window" | grep -q '// textMuted-decorative-justified:'; then
    echo "$file:$line: textMuted use without // textMuted-decorative-justified: comment within 5 preceding lines"
    EXIT_CODE=1
  fi
done < <(grep -rn '\.textMuted\b' lib/ \
           --include='*.dart' \
           | grep -v '^lib/core/theme/tokens/' \
           | grep -v '^lib/core/theme/app_theme.dart:' \
           | grep -v '^lib/main.dart:')

# ---------------------------------------------------------------------------
# Check 4: Direct AppShadowTokens.standard.* reads outside tokens/
# ---------------------------------------------------------------------------
# The `standard` alias was removed in Plan 37-06 — every shadow read must go
# through `context.shadows.*` so elevation tracks Theme.of(context).brightness.
# Exempt paths: lib/core/theme/tokens/ (source of truth). No justification
# window — the alias is eliminated, so any usage is a regression.
echo "Check 4: Direct AppShadowTokens.standard.* reads outside lib/core/theme/tokens/"
V4=$(grep -rn 'AppShadowTokens\.standard\.' lib/ \
    --include='*.dart' \
    | grep -v '^lib/core/theme/tokens/' \
    || true)
if [ -n "$V4" ]; then
  echo "::error::Direct AppShadowTokens.standard.* reads found. Use context.shadows.* (theme-aware) instead."
  echo "$V4"
  EXIT_CODE=1
fi

# ---------------------------------------------------------------------------
# Check 5: Material Colors.<name> constants without justification
# ---------------------------------------------------------------------------
# Material's `Colors.*` palette is theme-blind — a `Colors.white` label stays
# white in dark mode where a token would flip. Flag every `Colors.<name>`
# outside tokens/ that lacks a `// design-token-justified:` comment within 5
# lines above (same window/escape-hatch as Check 2). `Colors.transparent` is
# palette-independent and always allowed.
echo "Check 5: Material Colors.<name> constants (use context.colors tokens instead)"
while IFS=: read -r file line _rest; do
  [ -z "$file" ] && continue
  start_line=$((line - 5))
  [ "$start_line" -lt 1 ] && start_line=1
  end_line=$((line - 1))
  if [ "$end_line" -lt 1 ]; then
    echo "$file:$line: Colors.<name> at top of file — missing justification"
    EXIT_CODE=1
    continue
  fi
  window=$(sed -n "${start_line},${end_line}p" "$file")
  if ! echo "$window" | grep -q '// design-token-justified:'; then
    echo "$file:$line: Material Colors.<name> without // design-token-justified: comment within 5 preceding lines"
    EXIT_CODE=1
  fi
done < <(grep -rn '\bColors\.[a-zA-Z]' lib/ \
           --include='*.dart' \
           | grep -v '\bColors\.transparent\b' \
           | grep -v '^lib/core/theme/tokens/' \
           | grep -v '^lib/core/theme/app_theme.dart:' \
           | grep -v '^lib/main.dart:')

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "Theme purity check FAILED"
  exit 1
fi
echo "Theme purity check PASS"

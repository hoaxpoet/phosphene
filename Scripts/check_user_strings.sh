#!/usr/bin/env bash
# check_user_strings.sh
#
# Phase QR.4 / D-091 lint gate. Bans hardcoded user-facing string literals in
# `PhospheneApp/Views/`. Every `Text("...")`, `.help("...")`, and
# `.accessibilityLabel("...")` argument must resolve through
# `Localizable.strings` via `String(localized:)` / `NSLocalizedString` /
# `Text(verbatim:)`.
#
# Allowlisted files (developer-only surfaces, never displayed to end users):
#   - DebugOverlayView.swift          (gated on showDebug; D-key toggle)
#   - DashboardOverlayView*.swift     (gated on showDebug; D-key toggle)
#   - Dashboard*View.swift            (developer dashboard cards, same gate)
#
# Any other occurrence is a regression. Run from repo root.
#
# Exit non-zero on first hit so CI fails loud.

set -euo pipefail

ROOTS=(
  "PhospheneApp/Views"
)

# Files whose hardcoded strings are intentional (developer-only surfaces).
# Any new entry must come with a comment in the file explaining why and must
# be visible only when showDebug is true (D shortcut).
ALLOWLIST_FILES=(
  "PhospheneApp/Views/DebugOverlayView.swift"
)

escape_for_regex() {
  printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\]/\\&/g'
}
EXCLUDE_PARTS=()
for f in "${ALLOWLIST_FILES[@]}"; do
  EXCLUDE_PARTS+=("$(escape_for_regex "$f")")
done
EXCLUDE_PATTERN=$(printf "|%s" "${EXCLUDE_PARTS[@]}")
EXCLUDE_PATTERN="${EXCLUDE_PATTERN:1}"  # drop leading |

# Match a literal-starting Text("X..."), .help("X..."), or
# .accessibilityLabel("X...") where X is an uppercase letter. The leading-cap
# heuristic skips numeric-only / variable-interpolation patterns like
# Text("\(foo)") which start with `\` after the open quote.
PATTERN='Text\("[A-Z]|\.help\("[A-Z]|\.accessibilityLabel\("[A-Z]'

violations=$(
  grep -rEnH --include='*.swift' "$PATTERN" "${ROOTS[@]}" 2>/dev/null \
    | grep -vE "($EXCLUDE_PATTERN)" \
    | grep -v 'Text(verbatim:' \
    | grep -v 'String(localized:' \
    | grep -v 'NSLocalizedString' \
    || true
)

if [ -n "$violations" ]; then
  echo "ERROR: hardcoded user-facing strings found in PhospheneApp/Views/:" >&2
  echo "$violations" >&2
  echo >&2
  echo "QR.4 / D-091: every Text(...) / .help(...) / .accessibilityLabel(...)" >&2
  echo "argument must resolve through Localizable.strings via" >&2
  echo "  String(localized: \"key\")" >&2
  echo "  NSLocalizedString(\"key\", comment: \"\")" >&2
  echo "  Text(verbatim: nonLocalizedString)   // for dynamic non-translatable values" >&2
  echo "Add the key to PhospheneApp/en.lproj/Localizable.strings before" >&2
  echo "introducing the call site." >&2
  exit 1
fi

exit 0

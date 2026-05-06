#!/usr/bin/env bash
# check_sample_rate_literals.sh
#
# Phase QR.1 / D-079 lint gate. Bans the literal `44100` from any code path
# that should consume the live tap sample rate. The literal is allowlisted
# only inside:
#   - StemSeparator.modelSampleRate              (stem separator native rate)
#   - BeatThisPreprocessor.sourceSampleRate      (Beat This! native rate, 22050)
#   - Tests/.../Fixtures/*                       (fixture data files)
#   - Tests/...                                  (test code uses 44100 for fixture audio)
#   - Scripts/*                                  (helper scripts)
#   - Sources/Diagnostics/SoakTestHarness*       (synthetic procedural audio)
#
# Any other occurrence is a regression of Failed Approach #52. Literals like
# `44100.0`, `44100.5`, `44_100`, etc. are caught by the regex.
#
# Exit non-zero on first hit so CI fails loud. Run from repo root.

set -euo pipefail

# Roots to scan: production sources only (engine + app). Tests + fixtures
# legitimately reference 44100 for fixture data; scripts likewise.
ROOTS=(
  "PhospheneEngine/Sources"
  "PhospheneApp"
)

# Files within those roots whose 44100 use is intentional and load-bearing.
# Any new entry must come with a comment in the file explaining why.
ALLOWLIST_FILES=(
  "PhospheneEngine/Sources/ML/StemSeparator.swift"
  "PhospheneEngine/Sources/ML/StemSeparator+Reconstruct.swift"
  "PhospheneEngine/Sources/ML/StemModel.swift"
  "PhospheneEngine/Sources/DSP/BeatThisPreprocessor.swift"
  "PhospheneEngine/Sources/Diagnostics/SoakTestHarness+AudioGen.swift"
  # Default-argument boilerplate; live wiring overrides via
  # StemSeparator.modelSampleRate or the captured tapSampleRate. Keeping the
  # literal here lets tests / fixture code instantiate these types without
  # threading a rate through; production callers always pass an explicit value.
  "PhospheneEngine/Sources/Shared/StemSampleBuffer.swift"
  "PhospheneEngine/Sources/DSP/StemAnalyzer.swift"
  "PhospheneEngine/Sources/DSP/PitchTracker.swift"
)

# Build a `grep -v` pattern from the allowlist. Escape the `+` since it has
# regex meta-meaning in extended regex, and the SoakTestHarness path uses one.
escape_for_regex() {
  printf '%s' "$1" | sed 's/[][\.^$*+?(){}|\\]/\\&/g'
}
EXCLUDE_PARTS=()
for f in "${ALLOWLIST_FILES[@]}"; do
  EXCLUDE_PARTS+=("$(escape_for_regex "$f")")
done
EXCLUDE_PATTERN=$(printf "|%s" "${EXCLUDE_PARTS[@]}")
EXCLUDE_PATTERN="${EXCLUDE_PATTERN:1}"  # drop leading |

# Match the literal 44100 with optional decimal/grouping variants. Must be a
# token boundary to avoid matching e.g. 144100.
PATTERN='\b44_?100(\.[0-9]+)?\b'

violations=$(
  grep -rEnH --include='*.swift' --include='*.metal' "$PATTERN" "${ROOTS[@]}" 2>/dev/null \
    | grep -vE "($EXCLUDE_PATTERN)" \
    | grep -vE '^\s*//' \
    || true
)

# Filter out comment lines (lines whose match is inside a // line comment).
# Since we already filtered allowlist files, anything else with 44100 in
# non-comment text is a violation.
non_comment_violations=$(
  echo "$violations" \
    | awk -F: '{
        path=$1; line=$2;
        # rebuild content (everything after second :)
        $1=""; $2=""; sub(/^  */, ""); content=$0;
        # strip trailing \n
        # find // outside of a string (best-effort)
        if (match(content, /\/\//)) {
          before = substr(content, 1, RSTART - 1);
          # crude string detection — count quotes before //
          n = gsub(/"/, "&", before);
          if (n % 2 == 0) { next }
        }
        print path":"line":"content
      }' \
    | grep -v '^$' \
    || true
)

if [ -n "$non_comment_violations" ]; then
  echo "ERROR: literal 44100 found outside the allowlist:" >&2
  echo "$non_comment_violations" >&2
  echo >&2
  echo "QR.1 / D-079: capture tapSampleRate immutably and thread it through" >&2
  echo "every consumer; reference StemSeparator.modelSampleRate when the" >&2
  echo "intent is the model's native rate. See Failed Approach #52." >&2
  exit 1
fi

# Phase QR.1 also bans absolute-threshold use of AGC-normalized energy in
# .metal preset code (D-026 / Failed Approach #31). Flag any occurrence of
# `f.<band>` followed by `*` / `+` / `-` (not `f.<band>_dev`/`_rel`/`_att_*`).
# Whitelist: `_dev`, `_rel`, `_att_rel`, `_att`. Beat-pulse (`f.beat_<band>`)
# is also exempt — beats are inherently event-driven and not AGC-centred.
metal_violations=$(
  grep -rEnH --include='*.metal' \
    'f\.(bass|mid|treble|sub_bass|low_bass|low_mid|mid_high|high_mid|high)[ ]*[*+\-]' \
    PhospheneEngine/Sources/Presets/Shaders 2>/dev/null \
    | grep -vE 'f\.(bass|mid|treb|sub_bass|low_bass|low_mid|mid_high|high_mid|high)(_dev|_rel|_att_rel|_att)\b' \
    | grep -vE '//.*f\.' \
    || true
)

if [ -n "$metal_violations" ]; then
  echo "WARNING: .metal preset code uses raw AGC-normalized energy in arithmetic." >&2
  echo "         D-026 / Failed Approach #31 — drive from deviation primitives" >&2
  echo "         (f.bass_dev, f.bass_rel, f.bass_att_rel) instead." >&2
  echo "$metal_violations" >&2
  # Soft warning: comments and beat-pulse arithmetic still pass. If the only
  # "hits" are intended (commented examples, beat-pulse arith), no error.
  # Treat as warning, not error, until manually reviewed across catalog.
fi

exit 0

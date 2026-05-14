#!/usr/bin/env bash
# check_drums_beat_intensity.sh
#
# V.9 Session 4 Phase 0 lint gate. Bans `drumsBeat` / `drums_beat` from any
# code path that drives matID == 2 stage-rig intensity (Ferrofluid Ocean's
# §5.8 dispatch) — the §5.8 contract requires the *deviation primitive*
# `drums_energy_dev` per D-026, never the beat-onset rising edge. Mirrors
# the structural shape of `Scripts/check_sample_rate_literals.sh`.
#
# Rationale (CLAUDE.md Failed Approach #4 + §5.8 audio-routing rule):
#   Beat-onset is an accent layer, not a primary visual driver. Threshold-
#   crossing has ±80 ms jitter that gets amplified by feedback and feels
#   "machine-gun" against the music. The §5.8 spec routes intensity from
#   the smoothed deviation envelope `drums_energy_dev`, which centers on
#   AGC and shifts up/down with sustained energy changes — exactly the
#   musical signal stage-beam intensity should track.
#
# Scope: Sources/Presets/FerrofluidOcean/*, Sources/Shared/StageRigState.swift,
# Shaders/RayMarch.metal's matID == 2 branch. Other files are unscoped because
# they consume drumsBeat for legitimate reasons (e.g. SessionRecorder CSV
# logging, beat-strobed *accent* layers in other presets).
#
# Exit non-zero on first hit so CI fails loud. Run from repo root.

set -euo pipefail

# Files whose `drumsBeat`/`drums_beat` use would violate §5.8 intensity routing.
SCOPED_FILES=(
  "PhospheneEngine/Sources/Presets/FerrofluidOcean/FerrofluidStageRig.swift"
  "PhospheneEngine/Sources/Shared/StageRigState.swift"
)

# Stage-rig adjacent files in the presets directory (any future Sources/Presets/*StageRig*.swift).
STAGE_RIG_GLOB="PhospheneEngine/Sources/Presets"

# Match the symbol drumsBeat (camelCase, Swift) or drums_beat (snake_case, MSL),
# with word boundaries so substrings like `drumsBeatX` would also catch.
PATTERN='\b(drumsBeat|drums_beat)\b'

violations=""

# Filter helper: drop `//` / `///` line comments and `(void)` cast lines.
filter_comments_and_voidcasts() {
  awk -F: '{
    path=$1; line=$2;
    $1=""; $2=""; sub(/^  */, ""); content=$0;
    # Skip pure comment lines (//, ///)
    if (match(content, /^[ \t]*\/\/\//)) next;
    if (match(content, /^[ \t]*\/\//))  next;
    # Skip (void) casts (used to discard unused parameters)
    if (match(content, /\(void\)[^;]*\b(drumsBeat|drums_beat)\b/)) next;
    print path":"line":"content
  }' | grep -v '^$' || true
}

# 1. Scan the explicit file list.
for f in "${SCOPED_FILES[@]}"; do
  if [ -f "$f" ]; then
    raw=$(grep -EnH "$PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$raw" ]; then
      filtered=$(echo "$raw" | filter_comments_and_voidcasts)
      if [ -n "$filtered" ]; then
        violations+="$filtered"$'\n'
      fi
    fi
  fi
done

# 2. Scan any Sources/Presets/*StageRig*.swift files (future stage-rig consumers).
if [ -d "$STAGE_RIG_GLOB" ]; then
  while IFS= read -r f; do
    raw=$(grep -EnH "$PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$raw" ]; then
      filtered=$(echo "$raw" | filter_comments_and_voidcasts)
      if [ -n "$filtered" ]; then
        violations+="$filtered"$'\n'
      fi
    fi
  done < <(find "$STAGE_RIG_GLOB" -name "*StageRig*" -type f 2>/dev/null)
fi

# 3. Scan the matID == 2 branch in RayMarch.metal. We can't easily slice a
#    branch with grep alone, so scan the file but exclude:
#      - lines whose match is inside a `// ...` line comment
#      - lines whose match is inside a `(void)stems.drumsBeat;` cast (used to
#        silence unused-parameter warnings without consuming the field)
#      - lines containing `matID == 3` (the single-light fallback branch is
#        not part of the §5.8 contract; if a future increment routes its
#        intensity from drumsBeat that's a separate concern)
#    Since we want the gate to fire specifically on matID == 2 use, the
#    simplest robust rule is: any occurrence of `drumsBeat` / `drums_beat` in
#    RayMarch.metal outside a `//`-comment or `(void)` cast is a violation.
RAYMARCH_FILE="PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal"
if [ -f "$RAYMARCH_FILE" ]; then
  raymarch_hits=$(grep -EnH "$PATTERN" "$RAYMARCH_FILE" 2>/dev/null || true)
  if [ -n "$raymarch_hits" ]; then
    filtered_raymarch=$(echo "$raymarch_hits" | filter_comments_and_voidcasts)
    if [ -n "$filtered_raymarch" ]; then
      violations+="$filtered_raymarch"$'\n'
    fi
  fi
fi

if [ -n "$violations" ]; then
  echo "ERROR: drumsBeat / drums_beat found in §5.8 stage-rig intensity scope:" >&2
  echo "$violations" >&2
  echo >&2
  echo "Failed Approach #4 + V.9 §5.8: beat-onset is an accent, NOT a primary" >&2
  echo "visual driver. Route stage-rig intensity from drums_energy_dev (the" >&2
  echo "D-026 deviation primitive) instead. See CLAUDE.md 'Audio Data" >&2
  echo "Hierarchy' and SHADER_CRAFT §5.8 for the routing contract." >&2
  exit 1
fi

exit 0

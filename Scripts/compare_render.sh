#!/usr/bin/env bash
# compare_render.sh — [QG.2]
#
# Mechanizes the mid-session side-by-side perception check (D-<n>, REVIEW.1).
# Composites the newest RENDER_VISUAL=1 frames for a preset against its curated
# reference images into ONE comparison sheet — reference left, render frames
# right, filenames burned into each panel — and prints the sheet path on exit.
#
# Usage:
#   Scripts/compare_render.sh <preset> [session-dir]
#
#   <preset>       reference-set slug, e.g. lumen_mosaic
#                  (matches docs/VISUAL_REFERENCES/<preset>/ and the render PNG
#                   prefix, case-insensitive with spaces→underscores).
#   [session-dir]  explicit RENDER_VISUAL output dir; overrides "newest under
#                  /tmp/phosphene_visual". Optional.
#
# Missing references or render frames → non-zero exit with a one-line reason.
# Reader-facing only: no auto-scoring (D-064 — the reader is Claude's eyes).

set -euo pipefail

die() { printf 'compare_render: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: compare_render.sh <preset> [session-dir]"
PRESET="$1"
SESSION_DIR="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REF_DIR="$REPO_ROOT/docs/VISUAL_REFERENCES/$PRESET"
[ -d "$REF_DIR" ] || die "no reference dir: docs/VISUAL_REFERENCES/$PRESET"

# References: every image in the folder (README lives alongside; skip non-images).
REFS=()
while IFS= read -r f; do REFS+=("$f"); done < <(
  find "$REF_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) | sort
)
[ ${#REFS[@]} -gt 0 ] || die "no reference images in $REF_DIR"

# Session dir: explicit override, else newest under the RENDER_VISUAL output root.
VISUAL_ROOT="/tmp/phosphene_visual"
if [ -z "$SESSION_DIR" ]; then
  [ -d "$VISUAL_ROOT" ] || die "no RENDER_VISUAL output at $VISUAL_ROOT — run a RENDER_VISUAL=1 render first"
  SESSION_DIR="$(find "$VISUAL_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
  [ -n "$SESSION_DIR" ] || die "no session dirs under $VISUAL_ROOT — run a RENDER_VISUAL=1 render first"
fi
[ -d "$SESSION_DIR" ] || die "session dir not found: $SESSION_DIR"

# Render frames: PNGs whose name (lowercased, spaces→_) starts with the slug,
# excluding composite artifacts (contact sheets, palette grids, prior compares).
SLUG_LC="$(printf '%s' "$PRESET" | tr '[:upper:] ' '[:lower:]_')"
RENDERS=()
while IFS= read -r f; do
  base="$(basename "$f")"
  base_lc="$(printf '%s' "$base" | tr '[:upper:] ' '[:lower:]_')"
  case "$base_lc" in
    "$SLUG_LC"_*)
      case "$base_lc" in
        *contact_sheet*|*palette*|*_compare.png) ;;   # skip composites
        *) RENDERS+=("$f") ;;
      esac
      ;;
  esac
done < <(find "$SESSION_DIR" -maxdepth 1 -type f -iname '*.png' | sort)
[ ${#RENDERS[@]} -gt 0 ] || die "no render frames for '$PRESET' in $SESSION_DIR (looked for ${SLUG_LC}_*.png)"

OUT="$SESSION_DIR/${SLUG_LC}_compare.png"
swift "$SCRIPT_DIR/compare_render_composite.swift" "$OUT" \
  --refs "${REFS[@]}" --renders "${RENDERS[@]}"

[ -f "$OUT" ] || die "compositor did not produce $OUT"
printf 'Comparison sheet: %s\n' "$OUT"
printf '  %d references × %d render frames\n' "${#REFS[@]}" "${#RENDERS[@]}"

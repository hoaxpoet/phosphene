#!/usr/bin/env bash
# motion_gate.sh — [PG.MG] pre-M7 motion review gate.
#
# The still-frame review harness (PresetVisualReviewTests + compare_render.sh)
# only ever produced 3 disconnected stills per preset, so temporal defects —
# jitter, structure-pop, strobe — were invisible until a live M7. Truchet Loom
# passed still-review and jittered "like a bug" alive. This gate closes that
# hole: it turns a preset's MOTION into (a) a frame-to-frame magnitude signal
# that spikes on jitter/pops and (b) a handful of extracted frames the reader
# (Claude) actually views as a sequence, plus a pointer to the curated
# target_animated.gif to diff against.
#
# Reader-facing, like compare_render.sh (D-064): the script computes the signal
# and stages the frames; the smooth/jitter/ugly/off-concept VERDICT is the
# reader's. No auto-pass — the spike count is evidence, not a gate value.
#
# Usage:
#   Scripts/motion_gate.sh <preset> <frames-src>
#
#   <preset>      reference-set slug (docs/VISUAL_REFERENCES/<preset>/),
#                 case-insensitive, spaces->underscores.
#   <frames-src>  one of:
#                   - a video/gif file (.gif/.mp4/.mov)  -> analyzed directly
#                   - a directory of sequence PNGs        -> globbed, sorted
#                   - omitted -> newest RENDER_SEQUENCE dump under
#                     /tmp/phosphene_visual/*/  matching <preset>_seq_*.png
#
# Requires ffmpeg (frame diff + extraction) and python3 (stats). Both are the
# only deps; no ImageMagick.

set -euo pipefail

die() { printf 'motion_gate: %s\n' "$*" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: motion_gate.sh <preset> [frames-src]"
PRESET="$1"
SRC="${2:-}"

command -v ffmpeg >/dev/null || die "ffmpeg not found (brew install ffmpeg)"
command -v python3 >/dev/null || die "python3 not found"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SLUG="$(printf '%s' "$PRESET" | tr '[:upper:] ' '[:lower:]_')"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/motion_gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FRAMES="$WORK/frames"; mkdir -p "$FRAMES"

# --- Resolve <frames-src> to a contiguous PNG sequence in $FRAMES -------------
resolve_frames() {
  local src="$1"
  if [ -z "$src" ]; then
    local root="/tmp/phosphene_visual"
    [ -d "$root" ] || die "no frames-src and no $root — run a RENDER_SEQUENCE=1 render first"
    local dir; dir="$(find "$root" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
    [ -n "$dir" ] || die "no session dirs under $root"
    src="$dir"
  fi
  if [ -f "$src" ]; then
    ffmpeg -y -i "$src" "$FRAMES/f_%05d.png" >/dev/null 2>&1 \
      || die "ffmpeg could not decode $src"
  elif [ -d "$src" ]; then
    # Prefer <slug>_seq_* frames; fall back to any PNGs in the dir, sorted.
    local n=0
    while IFS= read -r f; do
      n=$((n+1)); cp "$f" "$(printf '%s/f_%05d.png' "$FRAMES" "$n")"
    done < <(find "$src" -maxdepth 1 -type f -iname "${SLUG}_seq_*.png" | sort)
    if [ "$n" -eq 0 ]; then
      while IFS= read -r f; do
        n=$((n+1)); cp "$f" "$(printf '%s/f_%05d.png' "$FRAMES" "$n")"
      done < <(find "$src" -maxdepth 1 -type f -iname '*.png' | sort)
    fi
    [ "$n" -gt 0 ] || die "no PNG frames found in $src"
  else
    die "frames-src not found: $src"
  fi
}
resolve_frames "$SRC"

NFRAMES="$(find "$FRAMES" -type f -iname '*.png' | wc -l | tr -d ' ')"
[ "$NFRAMES" -ge 3 ] || die "need >=3 frames for a motion signal (got $NFRAMES)"

# --- Motion signal: mean luminance of the consecutive-frame difference --------
# Smooth flow -> steady moderate values. Jitter/pop/strobe -> high-freq spikes.
ffmpeg -y -framerate 60 -i "$FRAMES/f_%05d.png" \
  -vf "tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
  -f null - 2>/dev/null | awk -F= '/YAVG/{printf "%.3f\n",$2}' > "$WORK/motion.txt"

# --- Sample frames for the reader to view as a sequence -----------------------
REVIEW_DIR="${TMPDIR:-/tmp}/motion_gate_review/${SLUG}"
rm -rf "$REVIEW_DIR"; mkdir -p "$REVIEW_DIR"
python3 - "$FRAMES" "$REVIEW_DIR" "$NFRAMES" <<'PY'
import sys,glob,os,shutil
frames=sorted(glob.glob(os.path.join(sys.argv[1],"*.png")))
out,n=sys.argv[2],int(sys.argv[3])
picks=[round(i*(len(frames)-1)/7) for i in range(8)] if len(frames)>=8 else range(len(frames))
seen=set()
for k,i in enumerate(picks):
    if i in seen: continue
    seen.add(i)
    shutil.copy(frames[i], os.path.join(out, f"sample_{k:02d}.png"))
PY

REF_GIF="$REPO_ROOT/docs/VISUAL_REFERENCES/$SLUG/target_animated.gif"

# --- Report (evidence only; verdict is the reader's) --------------------------
python3 - "$WORK/motion.txt" "$NFRAMES" "$REVIEW_DIR" "$REF_GIF" <<'PY'
import sys,statistics as st,glob,os
v=[float(x) for x in open(sys.argv[1]) if x.strip()]
nf,review,ref=sys.argv[2],sys.argv[3],sys.argv[4]
med=st.median(v) if v else 0.0
spikes=[i for i,x in enumerate(v) if med>0 and x>3*med]
print("── motion gate ──────────────────────────────────────────")
print(f"frames analysed   : {nf}  ({len(v)} inter-frame diffs)")
print(f"mean / stdev      : {st.mean(v):.2f} / {st.pstdev(v):.2f}")
print(f"median / max      : {med:.2f} / {max(v):.2f}")
print(f"spike frames >3x  : {len(spikes)} / {len(v)}"
      + (f"   at {spikes[:12]}{'…' if len(spikes)>12 else ''}" if spikes else "   (smooth)"))
print(f"frozen frames (~0): {sum(1 for x in v if x<0.5)} / {len(v)}")
print("─────────────────────────────────────────────────────────")
print("READER (Claude) must now:")
for p in sorted(glob.glob(os.path.join(review,'*.png'))):
    print(f"  view  {p}")
if os.path.exists(ref):
    print(f"  diff against reference motion:  {ref}")
else:
    print(f"  (no target_animated.gif at docs/VISUAL_REFERENCES/{os.path.basename(os.path.dirname(ref))}/ — new preset)")
print("Verdict = smooth+on-concept+matches-reference? If not, fix BEFORE M7.")
PY

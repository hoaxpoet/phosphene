#!/bin/bash
# Median frame_gpu_ms from a recorded session, in 8 buckets.
#
# ponytail: buckets, not one median. A session ramps through resolutions and
# preset switches; a single median over the whole file straddles them and lies
# (PERF.12 published a 16.44 ms figure from 89 frames spanning a transition and
# had to retract it). Read the buckets, take the ones that agree, ignore the ramp.
#
# Usage: Scripts/read_frame_gpu.sh [session-dir]   (default: newest session)
set -euo pipefail
DIR="${1:-$(ls -dt "$HOME"/Documents/phosphene_sessions/*/ | head -1)}"
echo "session: $DIR"
grep -E "RENDER_TARGET|preset →|THERMAL_STATE" "$DIR/session.log" || true
echo
python3 - "$DIR/features.csv" <<'PY'
import csv, statistics, sys
rows = [float(r["frame_gpu_ms"]) for r in csv.DictReader(open(sys.argv[1])) if r.get("frame_gpu_ms")]
if len(rows) < 400:
    print(f"only {len(rows)} frames — too few to trust; need a few hundred inside one resolution")
b = len(rows) // 8
for i in range(8):
    s = rows[i * b:(i + 1) * b]
    if s:
        print(f"bucket {i}: n={len(s)} median={statistics.median(s):.2f} ms  ({1000 / statistics.median(s):.1f} fps)")
PY

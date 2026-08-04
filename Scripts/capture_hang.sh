#!/usr/bin/env bash
# capture_hang.sh — grab the evidence for BUG-085 while the app is STILL FROZEN.
#
# The whole reason BUG-085 is filable is that Matt left a frozen app running instead of
# force-quitting it. BUG-060 and the Volumetric Lithograph "~3.7 min crash" both sat
# unactionable for want of exactly this. Run this BEFORE force-quitting; it takes ~15 s and
# writes everything to one directory.
#
#   Scripts/capture_hang.sh
#
# Safe to run any time — if the app is healthy it just records a healthy sample.

set -uo pipefail

OUT="${TMPDIR:-/tmp}/phosphene_hang_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT"

PID=$(pgrep -x PhospheneApp | head -1)
if [ -z "$PID" ]; then
    echo "capture_hang: PhospheneApp is not running — nothing to sample." >&2
    exit 1
fi

echo "capture_hang: PhospheneApp pid $PID → $OUT"

# 1. The stack. This is the artifact that matters most: it says WHERE it is stuck.
#    5 s at 1 ms gives ~4250 samples, enough to prove a hard block vs a slow frame.
sample "$PID" 5 -file "$OUT/sample.txt" >/dev/null 2>&1 && echo "  ✓ sample.txt"

# 2. Process state. 0.0 %% CPU distinguishes a BLOCK from a spin — the two have completely
#    different causes and the stack alone does not tell you which.
ps -o pid,stat,etime,%cpu,%mem,wq,command -p "$PID" > "$OUT/ps.txt" 2>&1 && echo "  ✓ ps.txt"

# 3. Is the window occluded/minimised? The leading BUG-085 hypothesis is that rendering
#    continues into a layer that is not being composited, which makes nextDrawable block
#    forever. Needs assistive access; records the failure if it is not granted.
osascript -e 'tell application "System Events" to tell process "PhospheneApp" to get {value of attribute "AXMinimized" of window 1, value of attribute "AXHidden"}' \
    > "$OUT/window_state.txt" 2>&1 && echo "  ✓ window_state.txt"

# 4. Did the display sleep or reconfigure? Rules the power path in or out.
pmset -g log 2>/dev/null | grep -iE "display|sleep|wake" | tail -40 > "$OUT/power.txt" && echo "  ✓ power.txt"

# 5. The session that was running — log tail plus frame count, which dates the freeze.
SESSION=$(ls -dt "$HOME"/Documents/phosphene_sessions/2*/ 2>/dev/null | head -1)
if [ -n "$SESSION" ]; then
    { echo "session: $SESSION"
      echo "features rows: $(( $(wc -l < "$SESSION/features.csv" 2>/dev/null || echo 1) - 1 ))"
      echo; tail -40 "$SESSION/session.log" 2>/dev/null
    } > "$OUT/session.txt" && echo "  ✓ session.txt"
fi

echo
echo "capture_hang: done. Send this directory (or just sample.txt):"
echo "  $OUT"

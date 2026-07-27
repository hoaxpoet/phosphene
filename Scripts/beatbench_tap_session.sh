#!/usr/bin/env bash
# beatbench_tap_session.sh — drive a GT.2 tapping sitting (Matt at the keyboard).
#
# Tapping is the scarce resource, so this spends it where uncertainty is highest
# rather than uniformly: the tracks where the independent reference tools disagree
# with Phosphene's grid get tapped first, plus two easy 4/4 tracks as a control on
# the tapping itself. Where taps and a reference AGREE on the tapped segment, the
# validated reference is trusted for the rest of the track — that is what keeps a
# ~90 s tap useful for full-length scoring (e.g. the BUG-065 drift curve).
#
# Resumable: TapCapture skips a track+pass that is already captured, so re-running
# picks up where you stopped. Ctrl-C between tracks is safe.
#
# Usage: Scripts/beatbench_tap_session.sh [hard|control|all]
#
# ponytail: a list + a loop. Per-track limits live in the table, not in flags you
# have to remember.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../PhospheneEngine" || exit 1
export BEATBENCH_FIXTURES_DIR="${BEATBENCH_FIXTURES_DIR:-$HOME/phosphene_beatbench_fixtures}"

GROUP="${1:-hard}"

# track            beats_s  downbeats_s   why
HARD=(
  "take_five        100  80   5/4 — librosa read 126 vs grid 166"
  "bleed            100  80   librosa 115 matches the DRUMS stem, not the 175 grid"
  "clair_de_lune    120  90   rubato — 'no stable grid' is a valid annotation"
  "bohemian_rhapsody 200 150  mid-song tempo changes; span at least one"
  "pyramid_song     100  80   grouped meter (grid 70 vs drums 164)"
)
CONTROL=(
  "billie_jean       90  70   steady 4/4 — a control on the tapping itself"
  "superstition      90  70   steady 4/4 control"
)
REST=(
  "around_the_world  90  70   "
  "stayin_alive      90  70   "
  "solsbury_hill    100  80   7/4"
  "yyz              100  80   10/8"
  "giorgio_by_moroder 200 150 progressive tempo build"
  "dance_yrself_clean 200 150 the ~3:05 change"
  "girl_from_ipanema  90  70   weak transients"
)

case "$GROUP" in
  hard)    SET=("${HARD[@]}") ;;
  control) SET=("${CONTROL[@]}") ;;
  all)     SET=("${HARD[@]}" "${CONTROL[@]}" "${REST[@]}") ;;
  *) echo "usage: $0 [hard|control|all]" >&2; exit 1 ;;
esac

echo "BeatBench tapping — group '$GROUP' (${#SET[@]} tracks, 2 passes each)"
echo "Tap SPACE on the beat; 'q' ends a pass early. Ctrl-C between tracks is safe."
echo

for row in "${SET[@]}"; do
  read -r id beats downs why <<< "$row"
  echo "──────────────────────────────────────────────────────────────"
  echo "$id  ${why:+— $why}"
  for spec in "beats:$beats" "downbeats:$downs"; do
    pass="${spec%%:*}"; secs="${spec##*:}"
    swift run TapCapture --track "$id" --pass "$pass" --limit-seconds "$secs"
    status=$?
    # exit 1 = already captured (skip) or no taps; neither should abort the sitting.
    if [ $status -ne 0 ] && [ $status -ne 1 ]; then
      echo "aborted ($status)"; exit $status
    fi
  done
done

echo
swift run TapCapture --status

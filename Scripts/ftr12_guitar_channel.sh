#!/bin/bash
# ftr12_guitar_channel.sh — FTR.12: run the guitar-channel report over the whole corpus.
#
# The QUESTION: is there any per-stem feature Phosphene already computes that separates a
# guitar from the drums on real material? Fractal Tree's tips have been routed to
# `other_onset_rate` since FTR.8 on the strength of one track.
#
# The CONTROLS ARE THE DESIGN, not padding. If `otherOnsetRate` on a guitarless track is
# distributionally indistinguishable from a guitar track, the feature is not reading guitar and
# no coefficient fixes that. Three negatives cover three different ways that could happen:
#   nancarrow — dense plucked/struck mid-register transients, no guitar, no drums
#   autechre  — heavy programmed percussion, no guitar, no acoustic instrument at all
#   beethoven — sparse solo piano, the low-density guitarless case
#
# Guitarlessness rests on the works' DEFINITIONAL instrumentation (solo player piano, solo
# piano, pure synthesis), which is a stronger basis than a genre bucket. It was not verified by
# ear — see the findings doc's limitations note.
#
# Usage:  Scripts/ftr12_guitar_channel.sh [out.txt] [seconds]
# Single track:  FTR12_AUDIO=… FTR12_LABEL=… swift test --package-path PhospheneEngine \
#                  --filter GuitarChannel

set -uo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-/tmp/ftr12_guitar_channel.txt}"
SECONDS_PER_TRACK="${2:-120}"
LIB="${FTR12_LIB:-/Volumes/Extreme SSD}"

# label|role|relpath
CORPUS=(
  "brouwer|positive — SOLO classical guitar, nothing else on the record|B/Brouwer, Leo/[1997] - John Williams - The Black Decameron/09 El Decameron Negro - El Arpa del guerrero.m4a"
  "wesmont|positive — clean electric guitar lead, WITH drums and bass so the control stem is real|M/Montgomery, Wes/[1960] - The Incredible Jazz Guitar Of Wes Montgomery/04 Four On Six.mp3"
  "nancarrow|negative — solo player piano; dense plucked transients, no guitar, no drums|N/Nancarrow, Conlon/[1999] - Studies for Player Piano/1-01 Study for Player Piano No. 3a.mp3"
  "autechre|negative — pure synthesis with heavy programmed percussion; no guitar, no acoustic source|A/Autechre/[2016] - Elseq 1-5/103 - 13x0 step.mp3"
  "beethoven|negative — sparse solo piano (Pathetique Rondo); the low-density guitarless case|B/Beethoven/[1989] - The Complete Piano Sonatas (Daniel Barenboim)/CD05/03 - Sonata No. 8 in C minor, Op.13 Pathétique - 3. Rondo- Allegro.flac"
  "sna|hard — distorted guitar in a SPARSE mix; FTR.11 measured otherOnsetRate r +0.71 here|UVW/The White Stripes/[2003] - Elephant/01 Seven Nation Army.m4a"
  "cherub|hard — distorted guitar in a DENSE mix; the single track FTR.8 justified the route with (+0.14)|S/Smashing Pumpkins/[1993] - Siamese Dream/01 Cherub Rock.mp3"
)

: > "$OUT"
fail=0
for entry in "${CORPUS[@]}"; do
  label="${entry%%|*}"
  rest="${entry#*|}"
  role="${rest%%|*}"
  rel="${rest#*|}"
  path="$LIB/$rel"
  if [ ! -f "$path" ]; then
    echo "MISSING  $label  $path" | tee -a "$OUT"
    fail=1
    continue
  fi
  echo "==> $label ($role)"
  {
    echo "FTR12ROLE|$label|$role"
    echo "FTR12PATH|$label|$rel"
  } >> "$OUT"
  FTR12_AUDIO="$path" FTR12_LABEL="$label" FTR12_SECONDS="$SECONDS_PER_TRACK" \
    swift test --package-path PhospheneEngine --filter GuitarChannel 2>&1 | tee -a "$OUT" \
    | grep -E "^\s+(FTR12PANNS|guitar classes)" || fail=1
done

echo
echo "full report: $OUT"
exit "$fail"

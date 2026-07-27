#!/usr/bin/env bash
# beatbench_copy_fixtures.sh
#
# Copy the BeatBench suite tracks that already live in the corpus into
# BEATBENCH_FIXTURES_DIR (~/phosphene_beatbench_fixtures/ by default), with
# canonical filenames. Candidate paths were located by
# tools/beatbench_find_fixtures.py against the committed corpus manifest.
#
# The 3 tracks NOT in the corpus (Solsbury Hill, Bohemian Rhapsody, Bleed) are
# backfilled from a recorded live-session raw_tap.wav (hybrid, GT.1 decision) —
# not copied here.
#
# Usage: Scripts/beatbench_copy_fixtures.sh [corpus_root] [dest_dir]
#   corpus_root default: /Volumes/Extreme SSD   (must be mounted)
#   dest_dir    default: ~/phosphene_beatbench_fixtures
#
# ponytail: resolved relpaths are inlined (located once via the finder). If the
# library reorganizes, re-run the finder and update the table below.

set -uo pipefail

CORPUS_ROOT="${1:-/Volumes/Extreme SSD}"
DEST="${2:-$HOME/phosphene_beatbench_fixtures}"

# canonical_name<TAB>corpus_relpath   (⚠ around_the_world = Alive 2007 live medley, not studio)
ENTRIES=(
  "billie_jean.mp3	C/Compilations/[2008] - Fantastic 80s!/1-01 Michael Jackson - Billie Jean.mp3"
  "around_the_world.mp3	D/Daft Punk/[2007] - Alive 2007/05 Around the World_Harder Better Faster Stronger.mp3"
  "stayin_alive.mp3	S/Soundtracks/[1977] - Saturday Night Fever/Saturday Night Fever/01 The Bee Gees - Stayin' Alive.mp3"
  "superstition.flac	UVW/Wonder, Stevie/[1972] - Talking Book - FLAC/06-Superstition.flac"
  "take_five.mp3	B/Brubeck, Dave/[1959] - Time Out/1-03 Take Five.mp3"
  "giorgio_by_moroder.mp3	D/Daft Punk/[2013] - Random Access Memories/03 Giorgio by Moroder.mp3"
  "dance_yrself_clean.mp3	L/LCD Soundsystem/[2010] - This Is Happening/01 Dance Yrself Clean.mp3"
  "girl_from_ipanema.mp3	G/Getz, Stan & João Gilberto/[1964 ] - Getz : Gilberto/01 The Girl From Ipanema 1.mp3"
  "clair_de_lune.mp3	S/Soundtracks/[2007] - The Darjeeling Limited/13 Alexis Weissenberg - Suite Bergmanesque - 3. 'Clair De Lune'.mp3"
)

if [ ! -d "$CORPUS_ROOT" ]; then
  echo "corpus root not found (SSD mounted?): $CORPUS_ROOT" >&2
  exit 1
fi
mkdir -p "$DEST"

copied=0 missing=0
for e in "${ENTRIES[@]}"; do
  name="${e%%$'\t'*}"
  rel="${e#*$'\t'}"
  src="$CORPUS_ROOT/$rel"
  dst="$DEST/$name"
  if [ ! -f "$src" ]; then
    echo "MISSING in corpus: $rel" >&2
    missing=$((missing + 1))
    continue
  fi
  cp "$src" "$dst" && { echo "copied $name"; copied=$((copied + 1)); }
done

echo "beatbench_copy_fixtures: $copied copied, $missing missing → $DEST"
echo "Next: source the 3 tap-backfill tracks from a recorded session, then generate the manifest."

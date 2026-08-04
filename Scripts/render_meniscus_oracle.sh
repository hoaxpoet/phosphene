#!/usr/bin/env bash
# render_meniscus_oracle.sh — [MEN.2b] render the Meniscus SOURCE preset as the oracle.
#
# MEN.2b's deliverable is a side-by-side against the butterchurn render on the same
# track, so the oracle has to be reproducible rather than a thing someone did once by
# hand. Per the `reference-port` skill: stand the cross-check up BEFORE porting, so the
# port has a target to match from line one.
#
# Renders `Martin - QBikal - Surface Turbulence IIb` through the existing butterchurn
# harness, driven by REAL music (the presets look dead on synthetic input — see
# tools/milkdrop-render/README.md), extracts the frames, and builds a contact sheet.
#
# Usage:
#   Scripts/render_meniscus_oracle.sh [audio-source] [start-seconds]
#
#   [audio-source]  wav/m4a/mp3 to drive the render. Default: the newest session's
#                   raw_tap.wav under ~/Documents/phosphene_sessions, so the oracle is
#                   driven by the same audio the app was last watched on.
#   [start-seconds] offset into that audio. Default 8.
#
# Nothing from the source preset is copied into the repo (D-116 bullet 4) and the audio
# is a copyrighted capture — both stay under ~/mdrender/. `tools/milkdrop-render/music.wav`
# is gitignored; this script relies on that.
#
# ponytail: no venv, no new deps — reuses the harness that already renders the gallery.

set -euo pipefail

die() { printf 'render_meniscus_oracle: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$REPO_ROOT/tools/milkdrop-render"
SOURCE_PRESET="$HOME/mdrender/builtins/Martin - QBikal - Surface Turbulence IIb.json"
OUT="$HOME/mdrender/men2b"

command -v ffmpeg >/dev/null || die "ffmpeg not found (brew install ffmpeg)"
command -v node   >/dev/null || die "node not found"
[ -f "$SOURCE_PRESET" ] || die "source preset absent: $SOURCE_PRESET
  The butterchurn built-ins are a dev-machine artifact, never committed. Regenerate per
  tools/milkdrop-render/README.md (\"Render the legends gallery\")."
[ -d "$HARNESS/node_modules" ] || die "harness deps missing — run:
  cd $HARNESS && npm install butterchurn butterchurn-presets milkdrop-preset-converter puppeteer"

AUDIO="${1:-}"
START="${2:-8}"
if [ -z "$AUDIO" ]; then
  SESSION_ROOT="$HOME/Documents/phosphene_sessions"
  [ -d "$SESSION_ROOT" ] || die "no session dir and no audio argument"
  # NEWEST BY MTIME, not alphabetically last: session dirs are ISO-timestamped, but
  # hand-named ones (`beat-match-test-session`) sort after them and would silently win.
  AUDIO="$(find "$SESSION_ROOT" -name raw_tap.wav -maxdepth 2 -print0 2>/dev/null \
           | xargs -0 ls -t 2>/dev/null | head -1)"
  [ -n "$AUDIO" ] || die "no raw_tap.wav under $SESSION_ROOT — pass an audio file explicitly"
fi
[ -f "$AUDIO" ] || die "audio not found: $AUDIO"

# The harness reads music.wav from its OWN directory, at 22050 Hz mono.
printf 'oracle audio : %s (from %ss)\n' "$AUDIO" "$START"
ffmpeg -y -loglevel error -ss "$START" -t 12 -i "$AUDIO" -ac 1 -ar 22050 "$HARNESS/music.wav"
[ -s "$HARNESS/music.wav" ] || die "extracted music.wav is empty — is [start-seconds] past the end of the audio?"

mkdir -p "$OUT"
( cd "$HARNESS" && node render-gif.js "$OUT/oracle" "$SOURCE_PRESET" )

GIF="$OUT/oracle/Martin - QBikal - Surface Turbulence IIb.gif"
[ -f "$GIF" ] || die "harness produced no GIF"

rm -rf "$OUT/oracle_frames"
mkdir -p "$OUT/oracle_frames"
ffmpeg -y -loglevel error -i "$GIF" -vsync 0 "$OUT/oracle_frames/f_%03d.png"
ffmpeg -y -loglevel error -i "$GIF" \
  -vf "select='not(mod(n\,4))',scale=210:-1,tile=5x3" -frames:v 1 "$OUT/oracle_sheet.png"

printf '\noracle frames : %s (%d)\n' "$OUT/oracle_frames" "$(find "$OUT/oracle_frames" -name '*.png' | wc -l | tr -d ' ')"
printf 'contact sheet : %s\n' "$OUT/oracle_sheet.png"
printf 'animated      : %s\n' "$GIF"

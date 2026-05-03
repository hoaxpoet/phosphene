#!/usr/bin/env bash
# fetch_tempo_fixtures.sh — Download 30s preview clips for DSP.1 reference
# tracks via the iTunes Search API.
#
# These are the same public-CDN clips PreviewDownloader uses in production.
# Files land in PhospheneEngine/Tests/Fixtures/tempo/ which is gitignored
# (preview clips are licensed; do not commit).
#
# Usage:
#   Scripts/fetch_tempo_fixtures.sh
#
# Re-run any time. Existing files are kept; pass --force to overwrite.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE_DIR="$ROOT/PhospheneEngine/Tests/Fixtures/tempo"
mkdir -p "$FIXTURE_DIR"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; fi

fetch () {
    local label="$1"
    local term="$2"
    local artist_filter="$3"  # substring match against artistName for safety
    local out="$FIXTURE_DIR/$label.m4a"

    if [[ -f "$out" && $FORCE -eq 0 ]]; then
        echo "==> $label  (cached at $out)"
        return 0
    fi

    echo "==> $label  searching iTunes for '$term'"
    local encoded
    encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$term")
    local url="https://itunes.apple.com/search?term=${encoded}&media=music&limit=10"

    local preview_url
    preview_url=$(curl -sS "$url" | python3 -c "
import sys, json
data = json.load(sys.stdin)
filt = sys.argv[1].lower()
for r in data.get('results', []):
    if filt in r.get('artistName', '').lower():
        if r.get('previewUrl'):
            print(r['previewUrl'])
            break
" "$artist_filter")

    if [[ -z "$preview_url" ]]; then
        echo "    !! no previewUrl found for $label (artist filter '$artist_filter')"
        return 1
    fi

    echo "    downloading $preview_url"
    curl -sSL "$preview_url" -o "$out"
    local size
    size=$(stat -f%z "$out")
    echo "    wrote $out ($size bytes)"
}

# Reference tracks from CLAUDE.md "Validated Onset Counts" table.
# Artist filter is a substring used to disambiguate (e.g. "Miles Davis"
# excludes covers, "Radiohead" picks the original from many There There live
# versions).
fetch love_rehab    "love rehab chaim"           "chaim"
fetch so_what       "so what miles davis"        "miles davis"
fetch there_there   "there there radiohead"      "radiohead"

echo
echo "Fixtures ready in $FIXTURE_DIR"
echo "Next: Scripts/dump_tempo_baselines.sh"
